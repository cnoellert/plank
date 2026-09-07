// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import "preview-session.h"

// Dedicated macOS 27 preview backend. No display creation, consent prompts,
// audio or remote input. Existing capture consent must already be granted.
@interface PLANKMacScreenCapture : NSObject <PLANKMacPreviewCapture>
@end
