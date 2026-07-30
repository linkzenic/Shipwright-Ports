#import "SOHiCloudSync.h"

#import <CloudKit/CloudKit.h>
#import <Foundation/Foundation.h>

#include <algorithm>
#include <cstring>

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
        NSString* reason = accountError.localizedDescription ?: @"Sign in to iCloud to synchronize saves.";
        WriteStatus([@"iCloud unavailable: " stringByAppendingString:reason]);
        return false;
    }
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
    operation.savePolicy = CKRecordSaveAllKeys;
    operation.modifyRecordsCompletionBlock =
        ^(NSArray<CKRecord*>* savedRecords, NSArray<CKRecordID*>* deletedRecordIDs, NSError* error) {
            [[NSFileManager defaultManager] removeItemAtPath:stagingPath error:nil];
            if (error != nil) {
                WriteStatus([@"iCloud upload failed: " stringByAppendingString:error.localizedDescription]);
            } else {
                WriteStatus(@"Saves are up to date in iCloud.");
            }
        };
    [Database() addOperation:operation];
}

void DeleteCloudPath(NSString* relativePath) {
    CKModifyRecordsOperation* operation =
        [[CKModifyRecordsOperation alloc] initWithRecordsToSave:nil recordIDsToDelete:@[ RecordID(relativePath) ]];
    operation.modifyRecordsCompletionBlock =
        ^(NSArray<CKRecord*>* savedRecords, NSArray<CKRecordID*>* deletedRecordIDs, NSError* error) {
            if (error != nil && error.code != CKErrorUnknownItem) {
                WriteStatus([@"iCloud delete failed: " stringByAppendingString:error.localizedDescription]);
            } else {
                WriteStatus(@"The deleted save was removed from iCloud.");
            }
        };
    [Database() addOperation:operation];
}

void ApplyCloudData(NSString* relativePath, NSData* contents, NSDate* modifiedAt) {
    NSString* destination = AbsolutePath(relativePath);
    NSFileManager* files = [NSFileManager defaultManager];
    [files createDirectoryAtPath:destination.stringByDeletingLastPathComponent
     withIntermediateDirectories:YES attributes:nil error:nil];

    NSData* localContents = [NSData dataWithContentsOfFile:destination];
    if (localContents != nil && ![localContents isEqualToData:contents]) {
        NSString* backup = [destination stringByAppendingFormat:@".icloud-conflict-%.0f",
                                                               NSDate.date.timeIntervalSince1970];
        [files copyItemAtPath:destination toPath:backup error:nil];
    }

    NSString* temporary = [destination stringByAppendingString:@".icloud-download"];
    [files removeItemAtPath:temporary error:nil];
    if (![contents writeToFile:temporary options:NSDataWritingAtomic error:nil]) {
        WriteStatus(@"A cloud save downloaded but could not be written locally.");
        return;
    }
    NSError* replaceError = nil;
    bool replaced = false;
    if ([files fileExistsAtPath:destination]) {
        replaced = [files replaceItemAtURL:[NSURL fileURLWithPath:destination]
                             withItemAtURL:[NSURL fileURLWithPath:temporary]
                            backupItemName:nil
                                   options:0
                          resultingItemURL:nil
                                     error:&replaceError];
    } else {
        replaced = [files moveItemAtPath:temporary toPath:destination error:&replaceError];
    }
    if (!replaced) {
        WriteStatus(@"A cloud save downloaded but could not replace the local copy.");
        return;
    }
    if (modifiedAt != nil) {
        [files setAttributes:@{ NSFileModificationDate: modifiedAt } ofItemAtPath:destination error:nil];
    }
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
        NSDate* cloudDate = cloudRecord[kModifiedAtField] ?: cloudRecord.modificationDate;
        if (cloudContents == nil || cloudDate == nil) {
            continue;
        }

        if (localDate == nil || [cloudDate compare:localDate] == NSOrderedDescending) {
            if (applyCloudDownloads) {
                ApplyCloudData(relativePath, cloudContents, cloudDate);
            } else {
                deferredDownload = true;
            }
        } else if ([localDate compare:cloudDate] == NSOrderedDescending) {
            UploadPath(relativePath, cloudRecord);
        }
    }

    if (deferredDownload) {
        WriteStatus(@"A newer iCloud save is available. Restart the app to load it safely.");
    } else if ([ReadStatus() hasPrefix:@"Checking"]) {
        WriteStatus(@"Saves are up to date in iCloud.");
    }
}

} // namespace

extern "C" void SOHiCloudSync_PrepareSaves(void) {
    dispatch_sync(SyncQueue(), ^{
        ReconcilePaths(SaveRelativePaths(), true);
    });
}

extern "C" void SOHiCloudSync_SyncNow(void) {
    dispatch_async(SyncQueue(), ^{
        ReconcilePaths(SaveRelativePaths(), false);
    });
}

extern "C" void SOHiCloudSync_LocalSaveChanged(const char* path) {
    if (path == nullptr) {
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
    NSString* absolutePath = [NSString stringWithUTF8String:path];
    NSString* documents = DocumentsPath();
    if (![absolutePath hasPrefix:documents]) {
        return;
    }
    NSString* relativePath = [absolutePath substringFromIndex:documents.length + 1];
    dispatch_async(SyncQueue(), ^{
        if (WaitForAccount()) {
            DeleteCloudPath(relativePath);
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
