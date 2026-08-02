#import "SOHSaveBridgeSync.h"

#import <Foundation/Foundation.h>

#include <cstring>
#include "soh/Enhancements/ResetHotKey.h"

namespace {

NSString* const kServiceType = @"_linkzenic-savebridge._tcp.";
NSString* const kTokenKey = @"SOHSaveBridgeToken";
NSString* const kHostKey = @"SOHSaveBridgeHost";
NSString* const kPortKey = @"SOHSaveBridgePort";

dispatch_queue_t SyncQueue() {
    static dispatch_queue_t queue =
        dispatch_queue_create("com.shipofharkinian.save-bridge-sync", DISPATCH_QUEUE_SERIAL);
    return queue;
}

NSString* gStatus = @"Save Bridge is not paired.";
NSObject* gStatusLock = [[NSObject alloc] init];
bool gDownloadedSaveIsReady = false;

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

NSString* DocumentsPath() {
    NSArray<NSString*>* paths =
        NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return paths.firstObject ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
}

NSArray<NSString*>* SaveNames() {
    return @[ @"global.sav", @"file1.sav", @"file2.sav", @"file3.sav" ];
}

NSString* LocalPath(NSString* name) {
    return [[DocumentsPath() stringByAppendingPathComponent:@"Save"] stringByAppendingPathComponent:name];
}

double LocalModifiedAt(NSString* path) {
    NSDate* date = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil][NSFileModificationDate];
    return date != nil ? date.timeIntervalSince1970 : 0;
}

NSURL* BridgeURL(NSString* path) {
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    NSString* host = [defaults stringForKey:kHostKey];
    NSInteger port = [defaults integerForKey:kPortKey];
    if (host.length == 0 || port <= 0) {
        return nil;
    }
    NSString* formattedHost = [host containsString:@":"] ?
        [NSString stringWithFormat:@"[%@]", host] : host;
    return [NSURL URLWithString:[NSString stringWithFormat:@"http://%@:%ld%@", formattedHost, (long)port, path]];
}

void StoreEndpoint(NSString* host, NSInteger port) {
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:host forKey:kHostKey];
    [defaults setInteger:port forKey:kPortKey];
}

} // namespace

typedef void (^EndpointCompletion)(NSString* host, NSInteger port, NSString* error);

@interface SaveBridgeDiscovery : NSObject <NSNetServiceBrowserDelegate, NSNetServiceDelegate>
@property(nonatomic) NSNetServiceBrowser* browser;
@property(nonatomic) NSNetService* service;
@property(nonatomic, copy) EndpointCompletion completion;
@property(nonatomic) BOOL finished;
@end

@implementation SaveBridgeDiscovery

- (void)finishWithHost:(NSString*)host port:(NSInteger)port error:(NSString*)error {
    if (_finished) return;
    _finished = YES;
    [_browser stop];
    [_service stop];
    EndpointCompletion completion = _completion;
    _completion = nil;
    if (completion != nil) completion(host, port, error);
}

- (void)netServiceBrowser:(NSNetServiceBrowser*)browser didFindService:(NSNetService*)service moreComing:(BOOL)moreComing {
    if (_service != nil) return;
    _service = service;
    _service.delegate = self;
    [_service resolveWithTimeout:5];
}

- (void)netServiceDidResolveAddress:(NSNetService*)sender {
    NSString* host = [sender.hostName stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"."]];
    if (host.length == 0 || sender.port <= 0) {
        [self finishWithHost:nil port:0 error:@"Save Bridge did not provide a usable address."];
        return;
    }
    [self finishWithHost:host port:sender.port error:nil];
}

- (void)netService:(NSNetService*)sender didNotResolve:(NSDictionary<NSString*, NSNumber*>*)errorDict {
    [self finishWithHost:nil port:0 error:@"Could not resolve Save Bridge on this network."];
}

@end

namespace {

void DiscoverBridge(EndpointCompletion completion) {
    dispatch_async(dispatch_get_main_queue(), ^{
        SaveBridgeDiscovery* discovery = [[SaveBridgeDiscovery alloc] init];
        discovery.completion = completion;
        discovery.browser = [[NSNetServiceBrowser alloc] init];
        discovery.browser.delegate = discovery;
        [discovery.browser searchForServicesOfType:kServiceType inDomain:@""];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [discovery finishWithHost:nil port:0 error:@"Save Bridge was not found. Keep the Mac app open and use the same Wi-Fi network."];
        });
    });
}

void Request(NSString* method, NSString* path, NSData* body,
             void (^completion)(NSData* data, NSHTTPURLResponse* response, NSError* error)) {
    NSURL* url = BridgeURL(path);
    if (url == nil) {
        completion(nil, nil, [NSError errorWithDomain:@"SaveBridge" code:1 userInfo:nil]);
        return;
    }
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method;
    request.HTTPBody = body;
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    NSString* token = [NSUserDefaults.standardUserDefaults stringForKey:kTokenKey];
    if (token.length > 0) [request setValue:token forHTTPHeaderField:@"X-SaveBridge-Token"];
    if (body != nil) [request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:
        ^(NSData* data, NSURLResponse* response, NSError* error) {
            completion(data, [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse*)response : nil, error);
        }] resume];
}

void ReplaceLocalSave(NSString* name, NSData* data, double modifiedAt) {
    NSString* destination = LocalPath(name);
    NSFileManager* files = NSFileManager.defaultManager;
    [files createDirectoryAtPath:destination.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSData* local = [NSData dataWithContentsOfFile:destination];
    if (local != nil && ![local isEqualToData:data]) {
        NSString* backup = [destination stringByAppendingFormat:@".save-bridge-conflict-%.0f", NSDate.date.timeIntervalSince1970];
        [files copyItemAtPath:destination toPath:backup error:nil];
    }
    [data writeToFile:destination options:NSDataWritingAtomic error:nil];
    if (modifiedAt > 0) [files setAttributes:@{ NSFileModificationDate: [NSDate dateWithTimeIntervalSince1970:modifiedAt] } ofItemAtPath:destination error:nil];
}

void SyncWithManifest(NSDictionary* manifest) {
    NSArray* remoteFiles = [manifest[@"files"] isKindOfClass:NSArray.class] ? manifest[@"files"] : @[];
    NSMutableDictionary<NSString*, NSDictionary*>* remoteByName = [NSMutableDictionary dictionary];
    for (NSDictionary* file in remoteFiles) {
        if ([file[@"path"] isKindOfClass:NSString.class]) remoteByName[file[@"path"]] = file;
    }
    dispatch_group_t group = dispatch_group_create();
    __block NSInteger transfers = 0;
    __block NSInteger downloads = 0;
    for (NSString* name in SaveNames()) {
        NSDictionary* remote = remoteByName[name];
        double remoteModified = [remote[@"modifiedAt"] doubleValue];
        NSString* localPath = LocalPath(name);
        double localModified = LocalModifiedAt(localPath);
        if (remote != nil && (localModified == 0 || remoteModified > localModified)) {
            dispatch_group_enter(group);
            Request(@"GET", [@"/v1/games/soh/files/" stringByAppendingString:name], nil,
                    ^(NSData* data, NSHTTPURLResponse* response, NSError* error) {
                if (error == nil && response.statusCode == 200 && data != nil) {
                    ReplaceLocalSave(name, data, remoteModified);
                    transfers++;
                    downloads++;
                }
                dispatch_group_leave(group);
            });
        } else if (localModified > remoteModified) {
            NSData* local = [NSData dataWithContentsOfFile:localPath];
            if (local == nil) continue;
            dispatch_group_enter(group);
            Request(@"PUT", [@"/v1/games/soh/files/" stringByAppendingString:name], local,
                    ^(NSData* data, NSHTTPURLResponse* response, NSError* error) {
                if (error == nil && response.statusCode == 200) transfers++;
                dispatch_group_leave(group);
            });
        }
    }
    dispatch_group_notify(group, SyncQueue(), ^{
        gDownloadedSaveIsReady = downloads > 0;
        WriteStatus(transfers == 0 ? @"SOH saves are already up to date." :
                    downloads > 0 ? [NSString stringWithFormat:@"Downloaded %ld newer save file%@. Use Reload Downloaded Saves to return safely to file select.", (long)downloads, downloads == 1 ? @"" : @"s"] :
                    [NSString stringWithFormat:@"Uploaded %ld newer save file%@.", (long)transfers, transfers == 1 ? @"" : @"s"]);
    });
}

} // namespace

extern "C" void SOHSaveBridgeSync_Pair(const char* code) {
    NSString* pairingCode = code != nullptr ? [NSString stringWithUTF8String:code] : @"";
    if (pairingCode.length != 6) {
        WriteStatus(@"Enter the six-digit code shown in Save Bridge.");
        return;
    }
    WriteStatus(@"Looking for Save Bridge…");
    DiscoverBridge(^(NSString* host, NSInteger port, NSString* error) {
        if (error != nil) { WriteStatus(error); return; }
        StoreEndpoint(host, port);
        NSData* body = [NSJSONSerialization dataWithJSONObject:@{ @"code": pairingCode, @"device": @"Ship of Harkinian iOS" } options:0 error:nil];
        Request(@"POST", @"/v1/pair", body, ^(NSData* data, NSHTTPURLResponse* response, NSError* requestError) {
            NSDictionary* result = data != nil ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            NSString* token = [result[@"token"] isKindOfClass:NSString.class] ? result[@"token"] : nil;
            if (requestError != nil || response.statusCode != 200 || token.length == 0) {
                WriteStatus(@"Save Bridge pairing failed. Check the code and try again.");
                return;
            }
            [NSUserDefaults.standardUserDefaults setObject:token forKey:kTokenKey];
            WriteStatus(@"Paired with Save Bridge. You can now sync saves.");
        });
    });
}

extern "C" void SOHSaveBridgeSync_SyncNow(void) {
    if ([NSUserDefaults.standardUserDefaults stringForKey:kTokenKey].length == 0) {
        WriteStatus(@"Pair with Save Bridge first.");
        return;
    }
    WriteStatus(@"Checking Save Bridge saves…");
    gDownloadedSaveIsReady = false;
    Request(@"GET", @"/v1/games/soh/manifest", nil, ^(NSData* data, NSHTTPURLResponse* response, NSError* error) {
        NSDictionary* manifest = data != nil ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (error != nil || response.statusCode != 200 || ![manifest isKindOfClass:NSDictionary.class]) {
            WriteStatus(@"Could not contact Save Bridge. Keep the Mac app open and use the same Wi-Fi network.");
            return;
        }
        SyncWithManifest(manifest);
    });
}

extern "C" void SOHSaveBridgeSync_ReloadDownloadedSaves(void) {
    if (!gDownloadedSaveIsReady) {
        WriteStatus(@"Sync must download a newer save before it can be reloaded.");
        return;
    }
    if (SohResetToFileSelectWithoutSaving()) {
        gDownloadedSaveIsReady = false;
        WriteStatus(@"Returned to file select without autosaving. Load the synced save there.");
    } else {
        WriteStatus(@"Reload is only available while SOH is running.");
    }
}

extern "C" void SOHSaveBridgeSync_GetStatus(char* buffer, size_t bufferSize) {
    if (buffer == nullptr || bufferSize == 0) return;
    const char* status = ReadStatus().UTF8String ?: "Save Bridge is ready.";
    std::strncpy(buffer, status, bufferSize - 1);
    buffer[bufferSize - 1] = '\0';
}
