#import "SOHSyncFolder.h"
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <atomic>
static std::atomic_bool NativeFolder(false);
BOOL SOHHasNativeSyncFolder(void) { return NativeFolder.load(); }

static NSString* const BookmarkKey = @"SOHSyncFolderBookmark";
static NSString* const ChildKey = @"SOHSyncFolderChild";
static NSError* FolderError(NSString* message) {
    return [NSError errorWithDomain:@"SOHSyncFolder" code:1
                           userInfo:@{NSLocalizedDescriptionKey:message}];
}

@interface SOHFolderPicker : NSObject <UIDocumentPickerDelegate>
@property(nonatomic, copy) void (^completion)(NSError* error);
@end
static SOHFolderPicker* ActivePicker;

@implementation SOHFolderPicker
- (void)finish:(NSError*)error {
    void (^callback)(NSError*) = self.completion;
    self.completion = nil;
    ActivePicker = nil;
    if (callback) callback(error);
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController*)controller {
    [self finish:FolderError(@"Folder selection cancelled. Existing sync folder is unchanged.")];
}
- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls {
    NSURL* folder = urls.firstObject;
    if (!folder || ![folder startAccessingSecurityScopedResource]) {
        [self finish:FolderError(@"Cannot access this folder. Please choose it again.")];
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        NSString* child=[folder.lastPathComponent caseInsensitiveCompare:@"SOH"]==NSOrderedSame ? @"" : @"SOH";
        NSURL* destination=child.length ? [folder URLByAppendingPathComponent:child isDirectory:YES] : folder;
        __block NSError* creationError=nil;
        NSError* coordinationError=nil;
        NSFileCoordinator* coordinator=[[NSFileCoordinator alloc] initWithFilePresenter:nil];
        [coordinator coordinateWritingItemAtURL:destination options:0 error:&coordinationError byAccessor:^(NSURL* url) {
            for (NSString* name in @[@"Save",@"mods"]) {
                if (![NSFileManager.defaultManager createDirectoryAtURL:[url URLByAppendingPathComponent:name isDirectory:YES]
                    withIntermediateDirectories:YES attributes:nil error:&creationError]) break;
            }
        }];
        NSError* error=coordinationError ?: creationError;
        NSData* bookmark=error ? nil : [folder bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:&error];
        [folder stopAccessingSecurityScopedResource];
        if (bookmark) {
            [NSUserDefaults.standardUserDefaults setObject:child forKey:ChildKey];
            [NSUserDefaults.standardUserDefaults setObject:bookmark forKey:BookmarkKey];
            [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"SOHAutomaticFolderSync"];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ [self finish:error ?: (bookmark ? nil : FolderError(@"Could not remember this folder."))]; });
    });
}
@end

void SOHChooseSyncFolder(void (^completion)(NSError* error)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (ActivePicker) { if (completion) completion(FolderError(@"Folder chooser is already open.")); return; }
        UIViewController* presenter = nil;
        for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive ||
                ![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow* window in ((UIWindowScene*)scene).windows) {
                if (window.isKeyWindow) presenter = window.rootViewController;
            }
        }
        while (presenter.presentedViewController) presenter = presenter.presentedViewController;
        if (!presenter) { if (completion) completion(FolderError(@"Open the app before choosing a folder.")); return; }
        ActivePicker = [SOHFolderPicker new];
        ActivePicker.completion = completion;
        UIDocumentPickerViewController* picker = [[UIDocumentPickerViewController alloc]
            initForOpeningContentTypes:@[UTTypeFolder] asCopy:NO];
        picker.allowsMultipleSelection = NO;
        picker.delegate = ActivePicker;
        [presenter presentViewController:picker animated:YES completion:nil];
    });
}

void SOHWithSyncFolder(void (^work)(NSURL* folder, NSError* error)) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.shipofharkinian.folder-sync", DISPATCH_QUEUE_SERIAL); });
    dispatch_async(queue, ^{
        // An entitled app owns this container; no document-picker permission is
        // needed. Re-evaluate each time to handle iCloud sign-out/account changes.
        NSDictionary* containers=[NSBundle.mainBundle objectForInfoDictionaryKey:@"NSUbiquitousContainers"];
        NSString* identifier=containers.count==1 ? containers.allKeys.firstObject : nil;
        NSURL* container=identifier ? [NSFileManager.defaultManager URLForUbiquityContainerIdentifier:identifier] : nil;
        NativeFolder=container != nil;
        if (container) {
            NSURL* documents=[container URLByAppendingPathComponent:@"Documents" isDirectory:YES];
            NSError* error=nil;
            for (NSString* name in @[@"Save",@"mods"]) {
                if (![NSFileManager.defaultManager createDirectoryAtURL:[documents URLByAppendingPathComponent:name isDirectory:YES] withIntermediateDirectories:YES attributes:nil error:&error]) break;
            }
            if (work) work(error ? nil : documents,error);
            return;
        }
        NSData* bookmark = [NSUserDefaults.standardUserDefaults dataForKey:BookmarkKey];
        if (!bookmark) { if (work) work(nil, FolderError(@"Automatic iCloud Drive access is unavailable. Check iCloud sign-in and signing entitlements, or choose a fallback folder.")); return; }
        BOOL stale = NO;
        NSError* error = nil;
        NSURL* folder = [NSURL URLByResolvingBookmarkData:bookmark options:NSURLBookmarkResolutionWithoutUI
                                          relativeToURL:nil bookmarkDataIsStale:&stale error:&error];
        if (!folder || ![folder startAccessingSecurityScopedResource]) {
            if (work) work(nil, FolderError(@"Sync folder is unavailable. Reconnect iCloud Drive or choose the folder again."));
            return;
        }
        @try {
            if (stale) {
                NSData* refreshed = [folder bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil
                                                    relativeToURL:nil error:&error];
                if (!refreshed) { if (work) work(nil, error); return; }
                [NSUserDefaults.standardUserDefaults setObject:refreshed forKey:BookmarkKey];
            }
            NSString* child=[NSUserDefaults.standardUserDefaults stringForKey:ChildKey];
            if (work) work(child.length ? [folder URLByAppendingPathComponent:child isDirectory:YES] : folder, nil);
        } @finally {
            [folder stopAccessingSecurityScopedResource];
        }
    });
}

void SOHForgetSyncFolder(void) {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:BookmarkKey];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:ChildKey];
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"SOHAutomaticFolderSync"];
}
