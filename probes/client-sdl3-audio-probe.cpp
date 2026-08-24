#include <SDL3/SDL.h>

#include <cstdio>
#include <vector>

int main()
{
    SDL_SetHint(SDL_HINT_AUDIO_DRIVER, "pipewire");

    if (!SDL_Init(SDL_INIT_AUDIO)) {
        std::fprintf(stderr, "SDL audio initialization failed: %s\n", SDL_GetError());
        return 1;
    }

    const char* driver = SDL_GetCurrentAudioDriver();
    if (driver == nullptr || SDL_strcmp(driver, "pipewire") != 0) {
        std::fprintf(stderr,
                     "Expected the native PipeWire driver, got: %s\n",
                     driver != nullptr ? driver : "<none>");
        SDL_Quit();
        return 2;
    }

    SDL_AudioSpec sourceSpec = {};
    sourceSpec.format = SDL_AUDIO_S16;
    sourceSpec.channels = 2;
    sourceSpec.freq = 48000;

    SDL_AudioStream* stream = SDL_OpenAudioDeviceStream(
        SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &sourceSpec, nullptr, nullptr);
    if (stream == nullptr) {
        std::fprintf(stderr, "Opening the PipeWire output stream failed: %s\n", SDL_GetError());
        SDL_Quit();
        return 3;
    }

    const SDL_AudioDeviceID device = SDL_GetAudioStreamDevice(stream);
    const char* deviceName = SDL_GetAudioDeviceName(device);
    std::vector<Sint16> silence(480 * sourceSpec.channels, 0);

    if (!SDL_PutAudioStreamData(stream,
                                silence.data(),
                                static_cast<int>(silence.size() * sizeof(silence[0]))) ||
        !SDL_ResumeAudioStreamDevice(stream)) {
        std::fprintf(stderr, "Starting the PipeWire output stream failed: %s\n", SDL_GetError());
        SDL_DestroyAudioStream(stream);
        SDL_Quit();
        return 4;
    }

    SDL_Delay(50);
    std::printf("audio_driver=%s\naudio_device=%s\n",
                driver,
                deviceName != nullptr ? deviceName : "<unknown>");

    SDL_DestroyAudioStream(stream);
    SDL_Quit();
    return 0;
}
