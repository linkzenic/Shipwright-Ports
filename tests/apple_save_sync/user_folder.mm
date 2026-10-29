#define SOH_FOLDER_TEST 1
#include "../../soh/ios/SOHUserFolderSync.mm"
#include <cassert>
#include <string>
std::string SaveSyncTestRoot;
static NSURL* Cloud;
void SOHWithSyncFolder(void (^work)(NSURL*,NSError*)) { work(Cloud,nil); }
BOOL SOHHasNativeSyncFolder(void) { return YES; }
void SOHChooseSyncFolder(void (^completion)(NSError*)) { completion(nil); }
static void Write(NSURL* root,NSString* path,NSString* content) {
    NSURL* url=[root URLByAppendingPathComponent:path];
    [NSFileManager.defaultManager createDirectoryAtURL:url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    assert([[content dataUsingEncoding:NSUTF8StringEncoding] writeToURL:url options:NSDataWritingAtomic error:nil]);
}
static NSString* ReadText(NSURL* root,NSString* path) {
    return [NSString stringWithContentsOfURL:[root URLByAppendingPathComponent:path] encoding:NSUTF8StringEncoding error:nil];
}
int main() { @autoreleasepool {
    NSURL* root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    NSURL* local=[root URLByAppendingPathComponent:@"local"];
    Cloud=[root URLByAppendingPathComponent:@"cloud"];
    [NSFileManager.defaultManager createDirectoryAtURL:Cloud withIntermediateDirectories:YES attributes:nil error:nil];
    SaveSyncTestRoot=local.path.UTF8String;
    Write(local,@"shipofharkinian.json",@"{\"scale\":1}");
    Write(local,@"mods/example.o2r",@"original mod");
    Write(local,@"oot.o2r",@"game archive");
    Write(local,@"Ship of Harkinian.log",@"runtime only");
    Write(local,@"Save/file1.sav",@"{\"version\":1,\"sections\":{\"base\":{\"data\":{}}}}");
    SOHUserFolderSync_Changed();
    assert([ReadText(Cloud,@"shipofharkinian.json") isEqual:@"{\"scale\":1}"]);
    assert([ReadText(Cloud,@"oot.o2r") isEqual:@"game archive"]);
    assert([ReadText(Cloud,@"mods/example.o2r") isEqual:@"original mod"]);
    assert(!ReadText(Cloud,@"Ship of Harkinian.log"));
    assert(![NSFileManager.defaultManager fileExistsAtPath:[Cloud.path stringByAppendingPathComponent:@"SaveSync"]]);
    Write(Cloud,@"shipofharkinian.json",@"{\"scale\":2}");
    SOHUserFolderSync_Changed();
    assert([ReadText(local,@"shipofharkinian.json") isEqual:@"{\"scale\":1}"]);
    SOHUserFolderSync_ApplyAtLaunch();
    assert([ReadText(local,@"shipofharkinian.json") isEqual:@"{\"scale\":2}"]);
    SOHUserFolderSync_Changed();
    Write(local,@"mods/example.o2r",@"local edit");
    Write(Cloud,@"mods/example.o2r",@"cloud edit");
    SOHUserFolderSync_Changed(); SOHUserFolderSync_ApplyAtLaunch();
    assert([ReadText(local,@"mods/example.o2r") isEqual:@"local edit"]);
    assert([ReadText(Cloud,@"mods/example.o2r") isEqual:@"cloud edit"]);
    assert([NSFileManager.defaultManager contentsOfDirectoryAtPath:[Cloud.path stringByAppendingPathComponent:@"Conflicts"] error:nil].count==1);
    Write(Cloud,@"shipofharkinian.json",@"broken json");
    SOHUserFolderSync_Changed(); SOHUserFolderSync_ApplyAtLaunch();
    assert([ReadText(local,@"shipofharkinian.json") isEqual:@"{\"scale\":2}"]);
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];
    puts("Whole-folder upload, staging, conflicts and invalid JSON tests passed.");
} }
