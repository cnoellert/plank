// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import "preview-session.h"

// Dedicated macOS 27 capture backend. No display creation or remote input.
// Includes system audio, never microphone capture. Desktop system-audio consent
// is required for the tap; the OS may request it on first use.
@interface PLANKMacScreenCapture : NSObject <PLANKMacPreviewCapture>
- (instancetype)initWithDesktopAudioTap:(BOOL)desktopAudioTap;
@end
