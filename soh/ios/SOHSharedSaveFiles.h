#pragma once
#import <Foundation/Foundation.h>

// All Apple sync transports must use the engine's actual data directory.
NSString* SOHAppleDataDirectory(void);
NSString* SOHAppleSaveDirectory(void);
NSString* SOHAppleSyncDirectory(void);
NSString* SOHSaveContentHash(NSData* data);
BOOL SOHStageIncomingSave(NSString* name, NSData* data, NSString* expectedLocalHash,
                         NSString* source, NSError** error, BOOL automatic = NO);
