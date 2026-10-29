#import "SOHUserFolderSync.h"
#import "SOHSyncFolder.h"
#import "SOHSharedSaveFiles.h"
#include "SaveSyncPolicy.h"
#include "UserFolderPolicy.h"
#import <CommonCrypto/CommonDigest.h>
#if !defined(SOH_FOLDER_TEST)
#import <UIKit/UIKit.h>
#endif
#include <atomic>
#include <cstring>

namespace {
NSObject* Lock=[NSObject new];
NSString* Status=@"Checking iCloud Drive access…";
std::atomic_bool Running(false), Again(false);
NSMutableDictionary* HashCache=[NSMutableDictionary dictionary];
void SetStatus(NSString* value) { @synchronized(Lock) { Status=[value copy]; } }
NSString* Hash(NSURL* url,BOOL force=NO) {
    NSDictionary* attributes=[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];
    NSString* signature=[NSString stringWithFormat:@"%@:%.9f:%@",attributes[NSFileSize],[attributes[NSFileModificationDate] timeIntervalSince1970],attributes[NSFileSystemFileNumber]];
    NSDictionary* cached=HashCache[url.path];
    if (!force && attributes && [cached[@"signature"] isEqual:signature]) return cached[@"hash"];
    NSInputStream* stream=[NSInputStream inputStreamWithURL:url];
    [stream open];
    CC_SHA256_CTX context; CC_SHA256_Init(&context);
    uint8_t buffer[65536]; NSInteger count;
    while ((count=[stream read:buffer maxLength:sizeof(buffer)])>0) CC_SHA256_Update(&context,buffer,(CC_LONG)count);
    [stream close];
    if (count<0) return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256_Final(digest,&context);
    NSMutableString* result=[NSMutableString string];
    for (unsigned char byte:digest) [result appendFormat:@"%02x",byte];
    if (attributes) HashCache[url.path]=@{@"signature":signature,@"hash":result};
    return result;
}
NSURL* SafeURL(NSURL* root,NSString* path) {
    if (!UserFolder::Include(path.UTF8String)) return nil;
    NSURL* url=root;
    for (NSString* part in path.pathComponents) {
        url=[url URLByAppendingPathComponent:part];
        NSNumber* link=nil;
        [url getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:nil];
        if (link.boolValue) return nil;
    }
    return url;
}
NSSet* Files(NSURL* root,BOOL* complete) {
    root=root.URLByResolvingSymlinksInPath;
    NSMutableSet* result=[NSMutableSet set];
    __block BOOL success=YES;
    NSDirectoryEnumerator* enumerator=[NSFileManager.defaultManager enumeratorAtURL:root
        includingPropertiesForKeys:@[NSURLIsRegularFileKey,NSURLIsSymbolicLinkKey,NSURLIsDirectoryKey]
        options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:^BOOL(NSURL* url,NSError* error) { success=NO; return NO; }];
    for (NSURL* url in enumerator) {
        NSDictionary* values=[url resourceValuesForKeys:@[NSURLIsRegularFileKey,NSURLIsSymbolicLinkKey,NSURLIsDirectoryKey] error:nil];
        if ([values[NSURLIsSymbolicLinkKey] boolValue]) { [enumerator skipDescendants]; continue; }
        NSString* parent=[root.path stringByResolvingSymlinksInPath];
        NSString* child=[url.path stringByResolvingSymlinksInPath];
        NSString* prefix=[parent stringByAppendingString:@"/"];
        if (![child hasPrefix:prefix]) { success=NO; continue; }
        NSString* path=[child substringFromIndex:prefix.length];
        if (!UserFolder::Include(path.UTF8String)) { if ([values[NSURLIsDirectoryKey] boolValue]) [enumerator skipDescendants]; continue; }
        if ([values[NSURLIsRegularFileKey] boolValue]) [result addObject:path];
    }
    *complete=success && enumerator!=nil;
    return result;
}
BOOL CopyAtomic(NSURL* source,NSURL* destination,NSString* expected=nil) {
    NSFileManager* files=NSFileManager.defaultManager;
    if (![files createDirectoryAtURL:destination.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil]) return NO;
    NSURL* temporary=[destination.URLByDeletingLastPathComponent URLByAppendingPathComponent:[@".soh-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    if (![files copyItemAtURL:source toURL:temporary error:nil]) return NO;
    if (expected && ![Hash(temporary,YES) isEqual:expected]) { [files removeItemAtURL:temporary error:nil]; return NO; }
    BOOL success=[files fileExistsAtPath:destination.path] ?
        [files replaceItemAtURL:destination withItemAtURL:temporary backupItemName:nil options:0 resultingItemURL:nil error:nil] :
        [files moveItemAtURL:temporary toURL:destination error:nil];
    if (!success) [files removeItemAtURL:temporary error:nil];
    return success;
}
NSString* AccountFingerprint() {
    id token=NSFileManager.defaultManager.ubiquityIdentityToken;
    if (token) {
        NSData* data=[NSKeyedArchiver archivedDataWithRootObject:token requiringSecureCoding:NO error:nil];
        if (data) return SOHSaveContentHash(data);
    }
    return @"";
}
NSString* StatePath(NSURL* folder) {
    NSMutableData* identity=[[folder.absoluteString dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [identity appendData:[AccountFingerprint() dataUsingEncoding:NSUTF8StringEncoding]];
    return [SOHAppleSyncDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"folder-%@.json",SOHSaveContentHash(identity)]];
}
void Sync(NSURL* folder) {
    NSURL* local=[NSURL fileURLWithPath:SOHAppleDataDirectory() isDirectory:YES];
    BOOL localOK=NO,remoteOK=NO;
    NSSet* localFiles=Files(local,&localOK), *remoteFiles=Files(folder,&remoteOK);
    if (!localOK || !remoteOK) { SetStatus(@"Folder listing is unavailable. Local files are unchanged; retry when iCloud Drive is available."); return; }
    NSString* statePath=StatePath(folder);
    static NSString* lastStatePath;
    if (![lastStatePath isEqual:statePath]) { [HashCache removeAllObjects]; lastStatePath=statePath; }
    NSData* stateData=[NSData dataWithContentsOfFile:statePath];
    id stateObject=stateData ? [NSJSONSerialization JSONObjectWithData:stateData options:NSJSONReadingMutableContainers error:nil] : nil;
    NSMutableDictionary* state=[stateObject isKindOfClass:NSMutableDictionary.class] ? stateObject : [NSMutableDictionary dictionary];
    NSMutableSet* paths=[localFiles mutableCopy]; [paths unionSet:remoteFiles];
    __block NSUInteger uploaded=0,downloaded=0,conflicts=0,failed=0;
    for (NSString* path in [[paths allObjects] sortedArrayUsingSelector:@selector(compare:)]) {
        NSURL* source=SafeURL(local,path), *remote=SafeURL(folder,path);
        if (!source || !remote) { ++failed; continue; }
        SetStatus([NSString stringWithFormat:@"Syncing user folder: %@",path]);
        NSError* coordinationError=nil;
        NSFileCoordinator* coordinator=[[NSFileCoordinator alloc] initWithFilePresenter:nil];
        [coordinator coordinateWritingItemAtURL:remote options:0 error:&coordinationError byAccessor:^(NSURL* url) {
            NSString* lh=[localFiles containsObject:path] ? Hash(source) : @"";
            NSString* rh=[remoteFiles containsObject:path] ? Hash(url) : @"";
            if (!lh || !rh) { ++failed; return; }
            NSDictionary* entry=[state[path] isKindOfClass:NSDictionary.class] ? state[path] : @{};
            NSString* base=[entry[@"base"] isKindOfClass:NSString.class] ? entry[@"base"] : @"";
            SaveSync::Action action=SaveSync::Plan(lh.UTF8String,rh.UTF8String,base.UTF8String);
            if (action==SaveSync::Action::None) { state[path]=@{@"base":lh}; return; }
            if (action==SaveSync::Action::Upload) {
                if (CopyAtomic(source,url,lh)) {
                    NSString* written=Hash(url,YES);
                    if (written) { state[path]=@{@"base":written}; ++uploaded; } else ++failed;
                } else ++failed;
                return;
            }
            NSString* pending=[NSString stringWithFormat:@"%@:%@",lh,rh];
            if ([entry[@"pending"] isEqual:pending]) return;
            BOOL conflict=action==SaveSync::Action::Conflict;
            if ([path hasPrefix:@"Save/"] && SaveSync::IsSaveName(path.lastPathComponent.UTF8String)) {
                NSData* save=[NSData dataWithContentsOfURL:url];
                if (!SOHStageIncomingSave(path.lastPathComponent,save,lh,@"iCloud Drive",nil,!conflict)) { ++failed; return; }
            } else {
                NSString* candidate=[[SOHAppleSyncDirectory() stringByAppendingPathComponent:conflict ? @"UserConflicts" : @"UserIncoming"] stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
                NSFileManager* files=NSFileManager.defaultManager;
                if (![files createDirectoryAtPath:candidate withIntermediateDirectories:YES attributes:nil error:nil] ||
                    ![files copyItemAtURL:url toURL:[NSURL fileURLWithPath:[candidate stringByAppendingPathComponent:@"contents"]] error:nil]) { ++failed; return; }
                if (![Hash([NSURL fileURLWithPath:[candidate stringByAppendingPathComponent:@"contents"]],YES) isEqual:rh]) { ++failed; return; }
                if (conflict && lh.length && ![files copyItemAtURL:source toURL:[NSURL fileURLWithPath:[candidate stringByAppendingPathComponent:@"local"]] error:nil]) { ++failed; return; }
                NSData* meta=[NSJSONSerialization dataWithJSONObject:@{@"path":path,@"expected":lh,@"hash":rh,@"account":AccountFingerprint()} options:0 error:nil];
                if (![meta writeToFile:[candidate stringByAppendingPathComponent:@"metadata.json"] options:NSDataWritingAtomic error:nil]) { ++failed; return; }
                if (conflict) {
                    // Expose both versions for editing, never silently choose one.
                    NSURL* visible=[folder URLByAppendingPathComponent:[@"Conflicts/" stringByAppendingString:candidate.lastPathComponent] isDirectory:YES];
                    [files createDirectoryAtURL:visible withIntermediateDirectories:YES attributes:nil error:nil];
                    CopyAtomic(source,[visible URLByAppendingPathComponent:[@"local-" stringByAppendingString:path.lastPathComponent]]);
                    CopyAtomic(url,[visible URLByAppendingPathComponent:[@"cloud-" stringByAppendingString:path.lastPathComponent]]);
                }
            }
            state[path]=@{@"base":base,@"pending":pending};
            if (conflict) ++conflicts; else ++downloaded;
        }];
        if (coordinationError) {
            ++failed;
        }
    }
    [NSFileManager.defaultManager createDirectoryAtPath:SOHAppleSyncDirectory() withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSJSONSerialization dataWithJSONObject:state options:0 error:nil] writeToFile:statePath options:NSDataWritingAtomic error:nil];
    BOOL listingOK=NO;
    NSSet* stored=Files(folder,&listingOK);
    NSUInteger confirmed=0,pending=0,untracked=0;
    NSMutableArray* errors=[NSMutableArray array];
    for (NSString* path in stored) {
        NSURL* url=SafeURL(folder,path);
        NSDictionary* values=[url resourceValuesForKeys:@[NSURLIsUbiquitousItemKey,NSURLUbiquitousItemIsUploadedKey,NSURLUbiquitousItemUploadingErrorKey] error:nil];
        if (![values[NSURLIsUbiquitousItemKey] boolValue]) ++untracked;
        else if ([values[NSURLUbiquitousItemIsUploadedKey] boolValue]) ++confirmed;
        else ++pending;
        NSError* error=values[NSURLUbiquitousItemUploadingErrorKey];
        if ([error isKindOfClass:NSError.class]) [errors addObject:[NSString stringWithFormat:@"%@ (%ld)",error.domain,(long)error.code]];
    }
    NSString* status=[NSString stringWithFormat:@"SOH folder: %lu files; %lu confirmed in iCloud, %lu pending, %lu not tracked by iCloud. Last pass: %lu copied, %lu staged, %lu conflicts, %lu unavailable.%@",(unsigned long)stored.count,(unsigned long)confirmed,(unsigned long)pending,(unsigned long)untracked,(unsigned long)uploaded,(unsigned long)downloaded,(unsigned long)conflicts,(unsigned long)(failed+!listingOK),errors.count ? [@" Upload errors: " stringByAppendingString:[errors componentsJoinedByString:@", "]] : @""];
    SetStatus(status);
    NSDictionary* diagnostic=@{@"container":folder.URLByDeletingLastPathComponent.lastPathComponent ?: @"",@"files":@(stored.count),@"confirmed":@(confirmed),@"pending":@(pending),@"untracked":@(untracked),@"errors":errors};
    [[NSJSONSerialization dataWithJSONObject:diagnostic options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[SOHAppleSyncDirectory() stringByAppendingPathComponent:@"drive-status.json"] options:NSDataWritingAtomic error:nil];
}
}

extern "C" void SOHUserFolderSync_Changed(void) {
    if (Running.exchange(true)) { Again=true; return; }
    SOHWithSyncFolder(^(NSURL* folder,NSError* error) {
        if (error) SetStatus(error.localizedDescription); else Sync(folder);
        Running=false;
        if (Again.exchange(false)) SOHUserFolderSync_Changed();
    });
}
extern "C" void SOHUserFolderSync_Start(void) {
#if !defined(SOH_FOLDER_TEST)
    dispatch_async(dispatch_get_main_queue(), ^{
        static id observer;
        static NSTimer* timer;
        if (!observer) observer=[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(NSNotification* note) { SOHUserFolderSync_Changed(); }];
        if (!timer) timer=[NSTimer scheduledTimerWithTimeInterval:60 repeats:YES block:^(NSTimer* timer) {
            if (UIApplication.sharedApplication.applicationState==UIApplicationStateActive) SOHUserFolderSync_Changed();
        }];
        SOHUserFolderSync_Changed();
    });
#endif
}
extern "C" void SOHUserFolderSync_ApplyAtLaunch(void) {
    NSString* root=[SOHAppleSyncDirectory() stringByAppendingPathComponent:@"UserIncoming"];
    NSFileManager* files=NSFileManager.defaultManager;
    for (NSString* candidate in [files contentsOfDirectoryAtPath:root error:nil]) {
        NSString* directory=[root stringByAppendingPathComponent:candidate];
        NSData* json=[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:@"metadata.json"]];
        id info=json ? [NSJSONSerialization JSONObjectWithData:json options:0 error:nil] : nil;
        if (![info isKindOfClass:NSDictionary.class] || ![info[@"path"] isKindOfClass:NSString.class]) continue;
        if (![info[@"account"] isEqual:AccountFingerprint()]) continue;
        NSURL* destination=SafeURL([NSURL fileURLWithPath:SOHAppleDataDirectory()],info[@"path"]);
        NSURL* source=[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"contents"]];
        if (!destination) continue;
        NSString* current=[files fileExistsAtPath:destination.path] ? Hash(destination,YES) : @"";
        if (![current isEqual:info[@"expected"]] || ![Hash(source,YES) isEqual:info[@"hash"]]) continue;
        if ([destination.pathExtension.lowercaseString isEqual:@"json"] &&
            ![NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:source] options:NSJSONReadingFragmentsAllowed error:nil]) continue;
        if (current.length && ![files copyItemAtURL:destination toURL:[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"previous"]] error:nil]) continue;
        if (!CopyAtomic(source,destination,info[@"hash"])) continue;
        NSString* history=[SOHAppleSyncDirectory() stringByAppendingPathComponent:@"History"];
        [files createDirectoryAtPath:history withIntermediateDirectories:YES attributes:nil error:nil];
        [files moveItemAtPath:directory toPath:[history stringByAppendingPathComponent:candidate] error:nil];
    }
}
extern "C" void SOHUserFolderSync_ChooseFallback(void) {
    SOHChooseSyncFolder(^(NSError* error) { if (error) SetStatus(error.localizedDescription); else SOHUserFolderSync_Changed(); });
}
extern "C" int SOHUserFolderSync_HasNativeFolder(void) { return SOHHasNativeSyncFolder(); }
extern "C" void SOHUserFolderSync_GetStatus(char* buffer,size_t size) {
    if (!buffer || !size) return;
    @synchronized(Lock) { std::strncpy(buffer,Status.UTF8String,size-1); buffer[size-1]=0; }
}
