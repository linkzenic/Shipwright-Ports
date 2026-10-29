#pragma once
#import <Foundation/Foundation.h>

// iOS only. Completion is called on the main queue. The saved bookmark remains
// private to the app; callers must never log its contents or the user's path.
void SOHChooseSyncFolder(void (^completion)(NSError* error));
// Work runs on a serial background queue while security-scoped access is held.
// Coordinate individual file operations with NSFileCoordinator inside work.
void SOHWithSyncFolder(void (^work)(NSURL* folder, NSError* error));
void SOHForgetSyncFolder(void);
BOOL SOHHasNativeSyncFolder(void);
