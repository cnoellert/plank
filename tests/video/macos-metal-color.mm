// Execute the production shader and uniform builder on the GPU. No GUI/TCC.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "vt_colors.h"
#include <cmath>
#include <cstdio>

struct Vertex { simd_float4 position; simd_float2 uv; };
int main(int argc, char** argv) {
    @autoreleasepool {
        if (argc != 2) return 2;
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        NSError *error = nil;
        NSString *source = [NSString stringWithContentsOfFile:@(argv[1]) encoding:NSUTF8StringEncoding error:&error];
        id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
        if (!library) { NSLog(@"%@", error); return 3; }
        auto descriptor = [MTLRenderPipelineDescriptor new];
        descriptor.vertexFunction = [library newFunctionWithName:@"vs_draw"];
        descriptor.fragmentFunction = [library newFunctionWithName:@"ps_draw_biplanar"];
        descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA32Float;
        auto pipeline = [device newRenderPipelineStateWithDescriptor:descriptor error:&error];
        if (!pipeline) { NSLog(@"%@", error); return 4; }
        auto queue = [device newCommandQueue];
        Vertex vertices[] = { {{-1,-1,0,1},{0,0}}, {{-1,1,0,1},{0,1}},
                              {{1,-1,0,1},{1,0}}, {{1,1,0,1},{1,1}} };
        unsigned checks = 0;
        float worst = 0;
        for (int depth : {8,10}) for (bool high : {false,true})
        for (bool full : {false,true}) for (auto matrix : {PlankVTMatrix::IdentityGbr, PlankVTMatrix::Bt601, PlankVTMatrix::Bt709, PlankVTMatrix::Bt2020}) {
            if (depth == 8 && high) continue;
            if (matrix == PlankVTMatrix::IdentityGbr && !full) continue;
            const auto params = plankVTColorParams(matrix, full, depth, high);
            const int maximum = (1 << depth) - 1;
            for (int sample = 0; sample < 5; ++sample) {
                const float level = sample / 4.0f;
                // Neutral ramp for YCbCr; distinct RGB components for identity.
                int codes[3];
                if (matrix == PlankVTMatrix::IdentityGbr) {
                    codes[0] = std::lround(level * maximum);
                    codes[1] = maximum - codes[0];
                    codes[2] = maximum / 2;
                } else {
                    codes[0] = full ? std::lround(level * maximum) : 16 * (1 << (depth-8)) + std::lround(level * 219 * (1 << (depth-8)));
                    codes[1] = codes[2] = 128 * (1 << (depth-8));
                }
                auto makeTexture = [&](bool chroma) -> id<MTLTexture> {
                    const auto format = depth == 8 ? (chroma ? MTLPixelFormatRG8Unorm : MTLPixelFormatR8Unorm) :
                                                     (chroma ? MTLPixelFormatRG16Unorm : MTLPixelFormatR16Unorm);
                    auto desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:1 height:1 mipmapped:NO];
                    desc.storageMode = MTLStorageModeShared;
                    auto texture = [device newTextureWithDescriptor:desc];
                    uint16_t words[2] = {uint16_t(codes[chroma ? 1 : 0] << (depth == 10 && high ? 6 : 0)), uint16_t(codes[2] << (depth == 10 && high ? 6 : 0))};
                    uint8_t bytes[2] = {uint8_t(words[0]),uint8_t(words[1])};
                    [texture replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:depth == 8 ? (void*)bytes : (void*)words bytesPerRow:(chroma ? 2 : 1)*(depth == 8 ? 1 : 2)];
                    return texture;
                };
                auto outputDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float width:1 height:1 mipmapped:NO];
                outputDesc.storageMode = MTLStorageModeShared;
                outputDesc.usage = MTLTextureUsageRenderTarget;
                auto output = [device newTextureWithDescriptor:outputDesc];
                auto pass = [MTLRenderPassDescriptor renderPassDescriptor];
                pass.colorAttachments[0].texture = output;
                pass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
                pass.colorAttachments[0].storeAction = MTLStoreActionStore;
                auto command = [queue commandBuffer];
                auto encoder = [command renderCommandEncoderWithDescriptor:pass];
                [encoder setRenderPipelineState:pipeline];
                [encoder setVertexBytes:vertices length:sizeof(vertices) atIndex:0];
                [encoder setFragmentBytes:&params length:sizeof(params) atIndex:0];
                [encoder setFragmentTexture:makeTexture(false) atIndex:0];
                [encoder setFragmentTexture:makeTexture(true) atIndex:1];
                [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
                [encoder endEncoding]; [command commit]; [command waitUntilCompleted];
                if (command.status != MTLCommandBufferStatusCompleted) return 5;
                float actual[4];
                [output getBytes:actual bytesPerRow:sizeof(actual) fromRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0];
                for (int channel = 0; channel < 3; ++channel) {
                    float expected = level;
                    if (matrix == PlankVTMatrix::IdentityGbr) expected = float(codes[channel == 0 ? 2 : channel == 1 ? 0 : 1]) / maximum;
                    const float difference = std::fabs(actual[channel] - expected);
                    worst = std::fmax(worst,difference); ++checks;
                    if (difference > 1.1f / maximum) {
                        fprintf(stderr,"FAIL depth=%d high=%d full=%d matrix=%d sample=%d channel=%d actual=%f expected=%f\n",depth,high,full,int(matrix),sample,channel,actual[channel],expected);
                        return 6;
                    }
                }
            }
        }
        printf("metal_color_checks=%u worst_normalized_error=%.7f PASS\n", checks, worst);
    }
}
