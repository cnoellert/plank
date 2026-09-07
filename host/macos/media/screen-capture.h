// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import "preview-session.h"

// Dedicated macOS 27 preview backend. No display creation, consent prompts,
// or remote input. Includes system audio, never microphone capture.
// Existing capture consent must already be granted.
@interface PLANKMacScreenCapture : NSObject <PLANKMacPreviewCapture>
@end
