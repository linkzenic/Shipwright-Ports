#import "SOHiCloudSync.h"
#import "SOHSharedSaveFiles.h"
#include "SaveSyncPolicy.h"

#import <CloudKit/CloudKit.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <libultraship/bridge/consolevariablebridge.h>

#include <algorithm>
#include <cstring>
#include <atomic>

#ifndef SOH_ICLOUD_CONTAINER_ID
#define SOH_ICLOUD_CONTAINER_ID "iCloud.com.shipofharkinian.shared"
#endif

namespace {

NSString* const kRecordType = @"SOHSaveFile";
NSString* const kRelativePathField = @"relativePath";
NSString* const kModifiedAtField = @"sourceModifiedAt";
NSString* const kContentsField = @"contents";

dispatch_queue_t SyncQueue() {
    static dispatch_queue_t queue =
        dispatch_queue_create("com.shipofharkinian.cloud-save-sync", DISPATCH_QUEUE_SERIAL);
    return queue;
}

NSString* gStatus = @"iCloud save sync is ready.";
NSObject* gStatusLock = [[NSObject alloc] init];
std::atomic_bool AccountVerified(false);

NSString* ReadStatus() {
    @synchronized(gStatusLock) {
        return [gStatus copy];
    }
}

void WriteStatus(NSString* status) {
    @synchronized(gStatusLock) {
        gStatus = [status copy];
    }
}

bool IsProvisionedForCloudKit() {
    NSNumber* provisioned =
        [NSBundle.mainBundle objectForInfoDictionaryKey:@"SOHCloudKitProvisionedBuild"];
    if (provisioned != nil && !provisioned.boolValue) {
        WriteStatus(@"iCloud save sync requires a cloud-enabled build signed with matching iCloud container entitlements. Local saves remain available.");
        return false;
    }
    return true;
}

NSArray<NSString*>* SaveRelativePaths() {
    return @[ @"Save/global.sav", @"Save/file1.sav", @"Save/file2.sav", @"Save/file3.sav" ];
}

NSString* DocumentsPath() {
#if TARGET_OS_TV
    NSArray<NSString*>* paths =
        NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString* caches = paths.firstObject ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"];
    return [caches stringByAppendingPathComponent:@"Ship of Harkinian"];
#else
    NSArray<NSString*>* paths =
        NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return paths.firstObject ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
#endif
}

NSString* AbsolutePath(NSString* relativePath) {
    return [DocumentsPath() stringByAppendingPathComponent:relativePath];
}

CKRecordID* RecordID(NSString* relativePath) {
    NSString* recordName = [@"save-" stringByAppendingString:
        [relativePath stringByReplacingOccurrencesOfString:@"/" withString:@"-"]];
    return [[CKRecordID alloc] initWithRecordName:recordName];
}

CKContainer* Container() {
    static CKContainer* container =
        [CKContainer containerWithIdentifier:@SOH_ICLOUD_CONTAINER_ID];
    return container;
}

CKDatabase* Database() {
    return [Container() privateCloudDatabase];
}

bool WaitForAccount() {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block CKAccountStatus accountStatus = CKAccountStatusCouldNotDetermine;
    __block NSError* accountError = nil;
    [Container() accountStatusWithCompletionHandler:^(CKAccountStatus status, NSError* error) {
        accountStatus = status;
        accountError = error;
        dispatch_semaphore_signal(semaphore);
    }];

    if (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) != 0) {
        WriteStatus(@"iCloud did not respond. Local saves remain available.");
        return false;
    }
    if (accountStatus != CKAccountStatusAvailable) {
        AccountVerified=false;
        NSString* reason = accountError.localizedDescription ?: @"Sign in to iCloud to synchronize saves.";
        WriteStatus([@"iCloud unavailable: " stringByAppendingString:reason]);
        return false;
    }
    dispatch_semaphore_t identityReady=dispatch_semaphore_create(0);
    __block CKRecordID* userID;
    [Container() fetchUserRecordIDWithCompletionHandler:^(CKRecordID* recordID,NSError* error) {
        userID=recordID; dispatch_semaphore_signal(identityReady);
    }];
    if (dispatch_semaphore_wait(identityReady,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))!=0 || !userID) {
        AccountVerified=false; WriteStatus(@"Could not verify the iCloud account. Local saves are unchanged."); return false;
    }
    NSString* identity=SOHSaveContentHash([userID.recordName dataUsingEncoding:NSUTF8StringEncoding]);
    if (![[NSUserDefaults.standardUserDefaults stringForKey:@"SOHCloudAccount"] isEqual:identity]) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"SOHCloudSaveBaselines"];
        [NSUserDefaults.standardUserDefaults setObject:identity forKey:@"SOHCloudAccount"];
    }
    AccountVerified=true;
    return true;
}

NSDictionary* LocalFileInfo(NSString* path) {
    return [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
}

NSDate* LocalModificationDate(NSString* path) {
    return LocalFileInfo(path)[NSFileModificationDate];
}

void UploadPath(NSString* relativePath, CKRecord* existingRecord) {
    NSString* localPath = AbsolutePath(relativePath);
    NSDate* modifiedAt = LocalModificationDate(localPath);
    if (modifiedAt == nil) {
        return;
    }

    NSString* stagingPath =
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"soh-cloud-%@.sav", NSUUID.UUID.UUIDString]];
    NSError* copyError = nil;
    if (![[NSFileManager defaultManager] copyItemAtPath:localPath toPath:stagingPath error:&copyError]) {
        WriteStatus([@"Could not stage save for iCloud: " stringByAppendingString:copyError.localizedDescription]);
        return;
    }

    CKRecord* record = existingRecord ?: [[CKRecord alloc] initWithRecordType:kRecordType
                                                                     recordID:RecordID(relativePath)];
    record[kRelativePathField] = relativePath;
    record[kModifiedAtField] = modifiedAt;
    record[kContentsField] = [[CKAsset alloc] initWithFileURL:[NSURL fileURLWithPath:stagingPath]];

    CKModifyRecordsOperation* operation = [[CKModifyRecordsOperation alloc] initWithRecordsToSave:@[ record ]
                                                                                recordIDsToDelete:nil];
    operation.savePolicy = CKRecordSaveIfServerRecordUnchanged;
    NSString* uploadedHash=SOHSaveContentHash([NSData dataWithContentsOfFile:stagingPath]);
    NSString* account=[NSUserDefaults.standardUserDefaults stringForKey:@"SOHCloudAccount"];
    operation.modifyRecordsCompletionBlock =
        ^(NSArray<CKRecord*>* savedRecords, NSArray<CKRecordID*>* deletedRecordIDs, NSError* error) {
            [[NSFileManager defaultManager] removeItemAtPath:stagingPath error:nil];
            if (error != nil) {
                WriteStatus([@"iCloud upload failed: " stringByAppendingString:error.localizedDescription]);
            } else if ([[NSUserDefaults.standardUserDefaults stringForKey:@"SOHCloudAccount"] isEqual:account]) {
                @synchronized(gStatusLock) {
                    NSMutableDictionary* bases=[[NSUserDefaults.standardUserDefaults dictionaryForKey:@"SOHCloudSaveBaselines"] mutableCopy] ?: [NSMutableDictionary dictionary];
                    bases[relativePath.lastPathComponent]=uploadedHash;
                    [NSUserDefaults.standardUserDefaults setObject:bases forKey:@"SOHCloudSaveBaselines"];
                }
                WriteStatus(@"Saves are up to date in iCloud.");
            }
        };
    [Database() addOperation:operation];
}


void ReconcilePaths(NSArray<NSString*>* relativePaths, bool applyCloudDownloads) {
    if (!WaitForAccount()) {
        return;
    }

    WriteStatus(@"Checking iCloud saves…");
    dispatch_group_t group = dispatch_group_create();
    NSMutableDictionary<NSString*, CKRecord*>* records = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString*, NSData*>* contentsByPath = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString*, NSError*>* errors = [NSMutableDictionary dictionary];

    for (NSString* relativePath in relativePaths) {
        dispatch_group_enter(group);
        [Database() fetchRecordWithID:RecordID(relativePath)
                    completionHandler:^(CKRecord* record, NSError* error) {
                        @synchronized(records) {
                            if (record != nil) {
                                records[relativePath] = record;
                                CKAsset* asset = record[kContentsField];
                                NSData* contents = asset.fileURL != nil ? [NSData dataWithContentsOfURL:asset.fileURL]
                                                                       : nil;
                                if (contents != nil) {
                                    contentsByPath[relativePath] = contents;
                                }
                            }
                            if (error != nil) {
                                errors[relativePath] = error;
                            }
                        }
                        dispatch_group_leave(group);
                    }];
    }

    if (dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC)) != 0) {
        WriteStatus(@"iCloud save check timed out. Local saves were not changed.");
        return;
    }

    bool deferredDownload = false;
    for (NSString* relativePath in relativePaths) {
        CKRecord* cloudRecord = records[relativePath];
        NSError* fetchError = errors[relativePath];
        NSString* localPath = AbsolutePath(relativePath);
        NSDate* localDate = LocalModificationDate(localPath);

        if (cloudRecord == nil) {
            if (fetchError == nil || fetchError.code == CKErrorUnknownItem) {
                if (localDate != nil) {
                    UploadPath(relativePath, nil);
                }
                continue;
            }
            WriteStatus([@"iCloud save check failed: " stringByAppendingString:fetchError.localizedDescription]);
            continue;
        }

        NSData* cloudContents = contentsByPath[relativePath];
        if (cloudContents == nil) continue;
        NSData* localContents=[NSData dataWithContentsOfFile:localPath];
        NSString* lh=SOHSaveContentHash(localContents), *rh=SOHSaveContentHash(cloudContents);
        NSString* base=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"SOHCloudSaveBaselines"][relativePath.lastPathComponent] ?: @"";
        switch (SaveSync::Plan(lh.UTF8String,rh.UTF8String,base.UTF8String)) {
            case SaveSync::Action::None: {
                @synchronized(gStatusLock) {
                    NSMutableDictionary* bases=[[NSUserDefaults.standardUserDefaults dictionaryForKey:@"SOHCloudSaveBaselines"] mutableCopy] ?: [NSMutableDictionary dictionary];
                    bases[relativePath.lastPathComponent]=lh;
                    [NSUserDefaults.standardUserDefaults setObject:bases forKey:@"SOHCloudSaveBaselines"];
                }
                break;
            }
            case SaveSync::Action::Upload: UploadPath(relativePath,cloudRecord); break;
            case SaveSync::Action::Download:
            case SaveSync::Action::Conflict:
                if (SOHStageIncomingSave(relativePath.lastPathComponent,cloudContents,lh,@"iCloud",nil,
                                        SaveSync::Plan(lh.UTF8String,rh.UTF8String,base.UTF8String)==SaveSync::Action::Download)) deferredDownload=true;
                else WriteStatus(@"Could not stage the iCloud save. Local progress is unchanged.");
                break;
        }
    }

    if (deferredDownload) {
        WriteStatus(@"Incoming iCloud saves are staged. Unambiguous changes apply at file select; conflicting slots need review.");
    } else if ([ReadStatus() hasPrefix:@"Checking"]) {
        WriteStatus(@"Saves are up to date in iCloud.");
    }
}

} // namespace

extern "C" void SOHiCloudSync_PrepareSaves(void) {
    if (!IsProvisionedForCloudKit()) {
        return;
    }
    dispatch_async(SyncQueue(), ^{
        ReconcilePaths(SaveRelativePaths(), true);
    });
}
extern "C" void SOHiCloudSync_Start(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        static id foregroundObserver, accountObserver;
        static NSTimer* timer;
        void (^check)(void)=^{ if (CVarGetInteger("gSettings.iCloudSync.Saves",0)) SOHiCloudSync_SyncNow(); };
        if (!foregroundObserver) foregroundObserver=[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(NSNotification* note) { check(); }];
        if (!accountObserver) accountObserver=[NSNotificationCenter.defaultCenter addObserverForName:CKAccountChangedNotification object:nil queue:nil usingBlock:^(NSNotification* note) {
            AccountVerified=false;
            [NSUserDefaults.standardUserDefaults removeObjectForKey:@"SOHCloudSaveBaselines"];
            WriteStatus(@"iCloud account changed. Existing local saves are preserved; different cloud saves require review.");
            check();
        }];
        if (!timer) timer=[NSTimer scheduledTimerWithTimeInterval:60 repeats:YES block:^(NSTimer* timer) {
            if (UIApplication.sharedApplication.applicationState==UIApplicationStateActive) check();
        }];
        check();
    });
}
extern "C" int SOHiCloudSync_AccountVerified(void) { return AccountVerified; }

extern "C" void SOHiCloudSync_SyncNow(void) {
    if (!IsProvisionedForCloudKit()) {
        return;
    }
    dispatch_async(SyncQueue(), ^{
        ReconcilePaths(SaveRelativePaths(), false);
    });
}

extern "C" void SOHiCloudSync_LocalSaveChanged(const char* path) {
    if (path == nullptr) {
        return;
    }
    if (!IsProvisionedForCloudKit()) {
        return;
    }
    NSString* absolutePath = [NSString stringWithUTF8String:path];
    NSString* documents = DocumentsPath();
    if (![absolutePath hasPrefix:documents]) {
        return;
    }
    NSString* relativePath = [absolutePath substringFromIndex:documents.length + 1];
    dispatch_async(SyncQueue(), ^{
        ReconcilePaths(@[ relativePath ], false);
    });
}

extern "C" void SOHiCloudSync_LocalSaveDeleted(const char* path) {
    if (path == nullptr) {
        return;
    }
    if (!IsProvisionedForCloudKit()) {
        return;
    }
    NSString* absolutePath = [NSString stringWithUTF8String:path];
    NSString* documents = DocumentsPath();
    if (![absolutePath hasPrefix:documents]) {
        return;
    }
    NSString* relativePath = [absolutePath substringFromIndex:documents.length + 1];
    dispatch_async(SyncQueue(), ^{
        if (WaitForAccount()) {
            ReconcilePaths(@[relativePath],false); // Missing files never delete remote progress automatically.
        }
    });
}

extern "C" void SOHiCloudSync_GetStatus(char* buffer, size_t bufferSize) {
    if (buffer == nullptr || bufferSize == 0) {
        return;
    }
    const char* status = ReadStatus().UTF8String ?: "iCloud save sync is ready.";
    std::strncpy(buffer, status, bufferSize - 1);
    buffer[bufferSize - 1] = '\0';
}
