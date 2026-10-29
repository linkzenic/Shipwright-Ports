#import "SOHNearbySync.h"
#import "SOHSharedSaveFiles.h"
#import "SOHiCloudSync.h"
#include "SaveSyncPolicy.h"
#include "soh/Enhancements/ResetHotKey.h"
#import <Foundation/Foundation.h>
#import <Network/Network.h>
#if !defined(SOH_SAVE_SYNC_TEST)
#import <UIKit/UIKit.h>
#endif
#if !defined(__TVOS__)
#import "SOHSyncFolder.h"
#endif
#include <cstring>
#include <atomic>
#if !defined(SOH_SAVE_SYNC_TEST)
#include <libultraship/bridge/consolevariablebridge.h>
#endif

namespace {
constexpr NSUInteger MaxPacket = 12 * 1024 * 1024;
NSString* const ServiceType = @"_soh-saves._tcp.";
dispatch_queue_t Queue() {
    static dispatch_queue_t queue = dispatch_queue_create("com.shipofharkinian.nearby-saves", DISPATCH_QUEUE_SERIAL);
    return queue;
}
NSObject* Lock = [NSObject new];
NSString* Status = @"Nearby save sync is off.";
nw_listener_t Listener;
NSString* Code;
NSString* Token;
NSString* PeerHost;
NSString* PeerPort;
NSString* PeerToken;
NSString* LocalServiceName = [@"SOH-" stringByAppendingString:NSUUID.UUID.UUIDString];
NSUInteger Attempts = 0;
NSUInteger Connections = 0;
NSUInteger Generation = 0;
bool Busy = false;
std::atomic_bool ApplyRequested(false);
std::atomic_bool KeepRequested(false);
std::atomic_uint ApplySlots(0), KeepSlots(0);
void SetStatus(NSString* value) { @synchronized(Lock) { Status = [value copy]; } }
bool Ready() {
#if !defined(SOH_SAVE_SYNC_TEST)
    if (CVarGetInteger("gSettings.iCloudSync.Saves",0)) {
        SetStatus(@"Turn off the legacy Sync Saves with iCloud option before using Nearby or folder sync. Do not run two save-sync systems together.");
        return false;
    }
#endif
    return true;
}
NSArray* Names() { return @[@"file1.sav", @"file2.sav", @"file3.sav", @"global.sav"]; }
NSData* Read(NSString* name) {
    return [NSData dataWithContentsOfFile:[SOHAppleSaveDirectory() stringByAppendingPathComponent:name]];
}
NSDictionary* Failure(NSString* message) { return @{@"error":message}; }
NSData* Encode(NSDictionary* object) { return [NSJSONSerialization dataWithJSONObject:object options:0 error:nil]; }
NSString* RandomToken() { return [NSUUID.UUID.UUIDString stringByAppendingString:NSUUID.UUID.UUIDString]; }
void Send(nw_connection_t connection, NSDictionary* object, void (^done)(void)) {
    NSData* json = Encode(object);
    uint32_t count = htonl((uint32_t)json.length);
    NSMutableData* wire = [NSMutableData dataWithBytes:&count length:4];
    [wire appendData:json];
    void* bytes = malloc(wire.length);
    if (!bytes) { nw_connection_cancel(connection); if (done) done(); return; }
    memcpy(bytes, wire.bytes, wire.length);
    dispatch_data_t data = dispatch_data_create(bytes, wire.length, Queue(), DISPATCH_DATA_DESTRUCTOR_FREE);
    nw_connection_send(connection, data, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t error) {
        if (error) nw_connection_cancel(connection);
        if (done) done();
    });
}
}

// A bounded one-request connection; no filesystem path comes from the peer.
@interface SOHSavePacket : NSObject
@property(nonatomic) nw_connection_t connection;
@property(nonatomic) NSMutableData* bytes;
@property(nonatomic, copy) void (^completion)(NSDictionary* packet);
@property(nonatomic) BOOL finished;
- (void)start;
- (void)receive;
@end
@implementation SOHSavePacket
- (void)finish:(NSDictionary*)packet {
    if (_finished) return;
    _finished = YES;
    auto completion = _completion;
    _completion = nil;
    if (completion) completion(packet);
}
- (void)start {
    _bytes = [NSMutableData data];
    [self receive];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), Queue(), ^{
        if (!self.finished) { [self finish:Failure(@"Transfer timed out.")]; nw_connection_cancel(self.connection); }
    });
}
- (void)receive {
    nw_connection_receive(_connection, 1, 64 * 1024, ^(dispatch_data_t data, nw_content_context_t context, bool complete, nw_error_t error) {
        if (self.finished) return;
        if (data) dispatch_data_apply(data, ^bool(dispatch_data_t region, size_t offset, const void* bytes, size_t count) {
            [self.bytes appendBytes:bytes length:count]; return true;
        });
        if (self.bytes.length > MaxPacket + 4) { [self finish:Failure(@"Transfer exceeds the save size limit.")]; return; }
        if (self.bytes.length >= 4) {
            uint32_t count; memcpy(&count, self.bytes.bytes, 4); count = ntohl(count);
            if (count == 0 || count > MaxPacket) { [self finish:Failure(@"Invalid transfer size.")]; return; }
            if (self.bytes.length >= count + 4) {
                NSData* json = [self.bytes subdataWithRange:NSMakeRange(4, count)];
                id object = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
                [self finish:[object isKindOfClass:NSDictionary.class] ? object : Failure(@"Invalid transfer data.")]; return;
            }
        }
        if (error || complete) { [self finish:Failure(@"Transfer interrupted.")]; return; }
        [self receive];
    });
}
@end

namespace {
NSDictionary* HandleRequest(NSDictionary* request, NSString* remoteHost) {
    NSString* operation = request[@"op"];
    if (![operation isKindOfClass:NSString.class]) return Failure(@"Invalid request.");
    if ([operation isEqual:@"pair"]) {
        if (++Attempts > 5 || !Code || ![request[@"code"] isEqual:Code]) return Failure(@"Pairing code rejected. Restart sharing for a new code.");
        NSNumber* port=request[@"returnPort"];
        NSString* callbackToken=request[@"returnToken"];
        if (![port isKindOfClass:NSNumber.class] || port.integerValue<1 || port.integerValue>65535 ||
            ![callbackToken isKindOfClass:NSString.class] || callbackToken.length<32 || callbackToken.length>128 || !remoteHost.length)
            return Failure(@"Update both previews before pairing.");
        Code = nil;
        Token = RandomToken();
        PeerHost=remoteHost; PeerPort=port.stringValue; PeerToken=callbackToken;
        SetStatus(@"Connected! Either device can now Send Saves or Receive Saves. Keep both apps open.");
        return @{@"token":Token};
    }
    if (!Token || ![request[@"token"] isEqual:Token]) return Failure(@"Pair again before syncing.");
    if ([operation isEqual:@"manifest"]) {
        NSMutableDictionary* hashes = [NSMutableDictionary dictionary];
        for (NSString* name in Names()) hashes[name] = SOHSaveContentHash(Read(name));
        return @{@"hashes":hashes};
    }
    if ([operation isEqual:@"complete"]) {
        SetStatus(@"Transfer completed. Any incoming saves are ready for review below. Your active save was not overwritten.");
        return @{@"ok":@YES};
    }
    NSString* name = request[@"name"];
    if (![name isKindOfClass:NSString.class] || !SaveSync::IsSaveName(name.UTF8String)) return Failure(@"Invalid save slot.");
    NSData* local = Read(name);
    NSString* hash = SOHSaveContentHash(local);
    if ([operation isEqual:@"get"]) {
        SetStatus([NSString stringWithFormat:@"Sending %@ to the paired device…",name]);
        return @{@"data":local ? [local base64EncodedStringWithOptions:0] : @"", @"hash":hash};
    }
    if ([operation isEqual:@"put"]) {
        if (![request[@"expected"] isEqual:hash]) return Failure(@"The receiving save changed. Sync again.");
        NSString* encoded = request[@"data"];
        if (![encoded isKindOfClass:NSString.class]) return Failure(@"Invalid save data.");
        NSData* incoming = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
        NSError* error = nil;
        if (!SOHStageIncomingSave(name, incoming, hash, @"Nearby device", &error)) return Failure(@"Could not stage incoming save.");
        SetStatus(@"Incoming saves are staged. Choose Use Incoming Saves or Keep Local Saves before returning to file select.");
        return @{@"ok":@YES};
    }
    return Failure(@"Unsupported request.");
}
void Request(NSDictionary* request, void (^completion)(NSDictionary*)) {
    if (!PeerHost || !PeerPort) { completion(Failure(@"Pair with the other device first.")); return; }
    nw_parameters_t parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
    nw_connection_t connection = nw_connection_create(nw_endpoint_create_host(PeerHost.UTF8String, PeerPort.UTF8String), parameters);
    nw_connection_set_queue(connection, Queue());
    __block bool started = false;
    __block bool finished = false;
    void (^finish)(NSDictionary*) = ^(NSDictionary* result) {
        if (finished) return;
        finished = true;
        completion(result);
        nw_connection_set_state_changed_handler(connection, nil);
        nw_connection_cancel(connection);
    };
    nw_connection_set_state_changed_handler(connection, ^(nw_connection_state_t state, nw_error_t error) {
        if (state == nw_connection_state_ready && !started) {
            started = true;
            SOHSavePacket* reader = [SOHSavePacket new];
            reader.connection = connection;
            reader.completion = finish;
            [reader start];
            Send(connection, request, nil);
        } else if (state == nw_connection_state_failed) finish(Failure(@"Nearby device is unavailable."));
    });
    nw_connection_start(connection);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 25 * NSEC_PER_SEC), Queue(), ^{ finish(Failure(@"Nearby device timed out.")); });
}
void SyncSlot(NSArray* names, NSUInteger index, NSDictionary* hashes, NSUInteger staged, NSUInteger sent, bool sending = false) {
    if (index == names.count) {
        Busy = false;
        NSString* time = [NSDateFormatter localizedStringFromDate:NSDate.date dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterShortStyle];
        SetStatus([NSString stringWithFormat:@"Transfer checked at %@. %lu incoming, %lu sent. Different slots require an explicit choice on the receiving device.", time, (unsigned long)staged, (unsigned long)sent]);
        Request(@{@"op":@"complete",@"token":PeerToken ?: @""}, ^(NSDictionary* result) {});
        return;
    }
    NSString* name = names[index];
    SetStatus([NSString stringWithFormat:@"%@ save %lu of %lu: %@…",sending ? @"Sending" : @"Receiving",(unsigned long)index+1,(unsigned long)names.count,name]);
    NSData* local = Read(name);
    NSString* localHash = SOHSaveContentHash(local);
    NSString* remoteHash = hashes[name];
    if (![remoteHash isKindOfClass:NSString.class]) { Busy = false; SetStatus(@"Invalid save manifest."); return; }
    if ([localHash isEqual:remoteHash] || (sending && !local) || (!sending && !remoteHash.length)) { SyncSlot(names,index+1,hashes,staged,sent,sending); return; }
    // First-pair differences are not assigned a winner: stage the remote copy
    // locally. Missing remote slots can safely receive the existing local copy.
    BOOL download = !sending && remoteHash.length > 0;
    NSMutableDictionary* request = [@{@"op":download ? @"get" : @"put", @"name":name, @"token":PeerToken ?: @""} mutableCopy];
    if (!download) { request[@"expected"] = remoteHash; request[@"data"] = [local base64EncodedStringWithOptions:0]; }
    Request(request, ^(NSDictionary* result) {
        if (result[@"error"]) { Busy = false; SetStatus(result[@"error"]); return; }
        if (download) {
            NSString* encoded = result[@"data"];
            NSData* data = [encoded isKindOfClass:NSString.class] ? [[NSData alloc] initWithBase64EncodedString:encoded options:0] : nil;
            if (![SOHSaveContentHash(data) isEqual:remoteHash] || !SOHStageIncomingSave(name,data,localHash,@"Nearby device",nil)) {
                Busy = false; SetStatus(@"Save changed during transfer or could not be staged. Sync again."); return;
            }
        }
        SyncSlot(names,index+1,hashes,staged+(download?1:0),sent+(download?0:1),sending);
    });
}
}

@interface SOHSaveDiscovery : NSObject <NSNetServiceBrowserDelegate, NSNetServiceDelegate>
@property(nonatomic) NSNetServiceBrowser* browser;
@property(nonatomic) NSMutableArray<NSNetService*>* services;
@property(nonatomic, copy) NSString* code;
@property(nonatomic) BOOL finished;
@end
@implementation SOHSaveDiscovery
- (void)netServiceBrowser:(NSNetServiceBrowser*)browser didFindService:(NSNetService*)service moreComing:(BOOL)more {
    if (_finished) return;
    if ([service.name isEqual:LocalServiceName]) return;
    [_services addObject:service];
    service.delegate = self;
    [service resolveWithTimeout:5];
}
- (void)netServiceDidResolveAddress:(NSNetService*)service {
    if (_finished) return;
    if (_services.count != 1) { SetStatus(@"More than one sharing device found. Stop sharing on the others, then retry."); return; }
    _finished = YES;
    [_browser stop];
    NSString* code = _code;
    dispatch_async(Queue(), ^{
        PeerHost = service.hostName;
        PeerPort = [NSString stringWithFormat:@"%ld",(long)service.port];
        uint16_t port=Listener ? nw_listener_get_port(Listener) : 0;
        if (!port) { SetStatus(@"Local sharing is not ready. Wait a moment and pair again."); return; }
        Token=RandomToken(); Code=nil;
        SetStatus(@"Pairing with nearby device…");
        Request(@{@"op":@"pair", @"code":code, @"returnPort":@(port), @"returnToken":Token}, ^(NSDictionary* result) {
            NSString* token = result[@"token"];
            if (![token isKindOfClass:NSString.class] || token.length < 32) { SetStatus(@"Pairing failed. Check the code and restart sharing if needed."); return; }
            PeerToken = token;
            SetStatus(@"Connected! Either device can now Send Saves or Receive Saves. Keep both apps open.");
        });
    });
}
@end

extern "C" void SOHNearbySync_Start(void) {
    if (!Ready()) return;
    dispatch_async(Queue(), ^{
        if (Listener) { SetStatus(@"Sharing is already running. Stop it before starting a new session."); return; }
        Attempts = 0; Token = nil;
        Code = [NSString stringWithFormat:@"%06u",arc4random_uniform(1000000)];
        NSUInteger generation = ++Generation;
        Listener = nw_listener_create(nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,NW_PARAMETERS_DEFAULT_CONFIGURATION));
        if (!Listener) { SetStatus(@"Could not create nearby listener."); return; }
        nw_listener_set_queue(Listener, Queue());
        nw_listener_set_advertise_descriptor(Listener,nw_advertise_descriptor_create_bonjour_service(LocalServiceName.UTF8String,"_soh-saves._tcp",nullptr));
        nw_listener_set_state_changed_handler(Listener, ^(nw_listener_state_t state, nw_error_t error) {
            if (generation != Generation) return;
            if (state == nw_listener_state_ready) SetStatus([NSString stringWithFormat:@"Pairing code: %@. Enter on the other device. Expires in 10 minutes. Trusted LAN only; transfers are not encrypted.",Code]);
            if (state == nw_listener_state_failed) { SetStatus(@"Could not start nearby sharing."); SOHNearbySync_Stop(); }
        });
        nw_listener_set_new_connection_handler(Listener, ^(nw_connection_t connection) {
            if (Connections >= 4) { nw_connection_cancel(connection); return; }
            ++Connections;
            nw_connection_set_queue(connection,Queue());
            nw_connection_start(connection);
            SOHSavePacket* reader = [SOHSavePacket new]; reader.connection = connection;
            reader.completion = ^(NSDictionary* request) {
                nw_endpoint_t remote=nw_connection_copy_endpoint(connection);
                const char* host=nw_endpoint_get_hostname(remote);
                NSDictionary* response = generation == Generation ? HandleRequest(request,host ? [NSString stringWithUTF8String:host] : nil) : Failure(@"Session expired.");
                Send(connection,response, ^{
                    --Connections;
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),Queue(), ^{ nw_connection_cancel(connection); });
                });
            };
            [reader start];
        });
        nw_listener_start(Listener);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,600*NSEC_PER_SEC),Queue(), ^{ if (generation==Generation) SOHNearbySync_Stop(); });
#if !defined(SOH_SAVE_SYNC_TEST)
        static id observer;
        if (!observer) observer = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil usingBlock:^(NSNotification* note) { SOHNearbySync_Stop(); }];
#endif
    });
}
extern "C" void SOHNearbySync_Stop(void) {
    dispatch_async(Queue(), ^{ ++Generation; if (Listener) nw_listener_cancel(Listener); Listener = nil; Code=nil; Token=nil; PeerToken=nil; SetStatus(@"Disconnected. Show a new pairing code to reconnect."); });
}
extern "C" void SOHNearbySync_Pair(const char* code) {
    if (!Ready()) return;
    NSString* value = code ? [NSString stringWithUTF8String:code] : @"";
    if (value.length != 6 || [value rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound) { SetStatus(@"Enter the six-digit code from the other device."); return; }
    SOHNearbySync_Start();
    dispatch_async(dispatch_get_main_queue(), ^{
        SOHSaveDiscovery* discovery = [SOHSaveDiscovery new]; discovery.code=value; discovery.services=[NSMutableArray array];
        discovery.browser=[NSNetServiceBrowser new]; discovery.browser.delegate=discovery;
        [discovery.browser searchForServicesOfType:ServiceType inDomain:@"local."];
        SetStatus(@"Looking for the sharing device…");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(), ^{
            [discovery.browser stop]; for (NSNetService* service in discovery.services) [service stop];
            if (!discovery.finished) { discovery.finished=YES; SetStatus(@"No single sharing device found. Keep both apps open on the same LAN and allow Local Network access."); }
        });
    });
}
extern "C" void SOHNearbySync_Sync(void) {
    if (!Ready()) return;
    dispatch_async(Queue(), ^{
        if (Busy) return;
        if (!PeerToken) { SetStatus(@"Pair with the other device first."); return; }
        Busy=true; SetStatus(@"Checking nearby saves…");
        Request(@{@"op":@"manifest",@"token":PeerToken}, ^(NSDictionary* result) {
            if (![result[@"hashes"] isKindOfClass:NSDictionary.class]) { Busy=false; SetStatus(@"Could not read saves. Restart sharing and pair again."); return; }
            SyncSlot(Names(),0,result[@"hashes"],0,0);
        });
    });
}
extern "C" void SOHNearbySync_GetStatus(char* buffer,size_t size) {
    if (!buffer || !size) return;
    @synchronized(Lock) { std::strncpy(buffer,Status.UTF8String,size-1); buffer[size-1]=0; }
}
extern "C" void SOHNearbySync_GetIncoming(char* buffer,size_t size) {
    if (!buffer || !size) return;
    NSMutableSet* names=[NSMutableSet set];
    NSString* root=[SOHAppleSyncDirectory() stringByAppendingPathComponent:@"Incoming"];
    for (NSString* candidate in [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil]) {
        NSData* json=[NSData dataWithContentsOfFile:[[root stringByAppendingPathComponent:candidate] stringByAppendingPathComponent:@"metadata.json"]];
        id info=json ? [NSJSONSerialization JSONObjectWithData:json options:0 error:nil] : nil;
        if (![info isKindOfClass:NSDictionary.class]) continue;
        NSString* name=info[@"name"];
        if ([name isKindOfClass:NSString.class] && SaveSync::IsSaveName(name.UTF8String)) [names addObject:name];
    }
    NSString* text=names.count ? [@"Incoming copies: " stringByAppendingString:[[[names allObjects] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "]] : @"No incoming saves are waiting.";
    std::strncpy(buffer,text.UTF8String,size-1); buffer[size-1]=0;
}
extern "C" void SOHNearbySync_Send(void) {
    if (!Ready()) return;
    dispatch_async(Queue(), ^{
        if (Busy) return;
        if (!PeerToken) { SetStatus(@"Pair with the other device first."); return; }
        Busy=true; SetStatus(@"Sending local saves for review on the other device…");
        Request(@{@"op":@"manifest",@"token":PeerToken}, ^(NSDictionary* result) {
            if (![result[@"hashes"] isKindOfClass:NSDictionary.class]) { Busy=false; SetStatus(@"Could not read saves. Restart sharing and pair again."); return; }
            SyncSlot(Names(),0,result[@"hashes"],0,0,true);
        });
    });
}
extern "C" void SOHNearbySync_ApplyIncoming(void) {
    if (!Ready()) return;
    ApplyRequested=true;
    if (!SohResetToFileSelectWithoutSaving()) SetStatus(@"Incoming saves will be checked at file select.");
}
extern "C" int SOHNearbySync_GetSlot(int slot,char* buffer,size_t size) {
    if (slot<0 || slot>3 || !buffer || !size) return 0;
    NSString* name=Names()[slot];
    NSMutableArray* descriptions=[NSMutableArray array];
    NSString* root=[SOHAppleSyncDirectory() stringByAppendingPathComponent:@"Incoming"];
    auto describe = ^NSString*(NSData* data) {
        id object=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![object isKindOfClass:NSDictionary.class]) return @"No save";
        if ([name isEqual:@"global.sav"]) return @"Global game settings";
        id sections=object[@"sections"];
        id base=[sections isKindOfClass:NSDictionary.class] ? sections[@"base"] : nil;
        id progress=[base isKindOfClass:NSDictionary.class] ? base[@"data"] : nil;
        if (![progress isKindOfClass:NSDictionary.class]) return @"Progress unavailable";
        NSNumber* health=progress[@"healthCapacity"], *rupees=progress[@"rupees"];
        if (![health isKindOfClass:NSNumber.class] || ![rupees isKindOfClass:NSNumber.class]) return @"Progress unavailable";
        return [NSString stringWithFormat:@"%ld hearts, %ld rupees",(long)health.integerValue/16,(long)rupees.integerValue];
    };
    NSMutableSet* hashes=[NSMutableSet set];
    for (NSString* candidate in [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil]) {
        NSString* directory=[root stringByAppendingPathComponent:candidate];
        NSData* json=[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:@"metadata.json"]];
        id info=json ? [NSJSONSerialization JSONObjectWithData:json options:0 error:nil] : nil;
        if (![info isKindOfClass:NSDictionary.class] || ![info[@"name"] isEqual:name] || ![info[@"sha256"] isKindOfClass:NSString.class] || [hashes containsObject:info[@"sha256"]]) continue;
        [hashes addObject:info[@"sha256"]];
        [descriptions addObject:[NSString stringWithFormat:@"Incoming (%@): %@",info[@"source"] ?: @"Nearby device",describe([NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:name]])]];
    }
    NSString* text=[NSString stringWithFormat:@"%@ — Local: %@\n%@",name,describe(Read(name)),[descriptions componentsJoinedByString:@"\n"]];
    std::strncpy(buffer,text.UTF8String,size-1); buffer[size-1]=0;
    return (int)hashes.count;
}
extern "C" void SOHNearbySync_ChooseSlot(int slot,int incoming) {
    if (slot<0 || slot>3) return;
    if (incoming) ApplySlots.fetch_or(1u<<slot); else KeepSlots.fetch_or(1u<<slot);
    SetStatus(@"Choice recorded for this slot. Returning to file select without saving current gameplay.");
    SohResetToFileSelectWithoutSaving();
}
extern "C" void SOHNearbySync_KeepLocal(void) {
    KeepRequested=true;
    SetStatus(@"Local saves retained. Incoming candidates will be archived at file select.");
    SohResetToFileSelectWithoutSaving();
}
extern "C" void SOHNearbySync_PrepareSaves(void) {
    bool apply=ApplyRequested.exchange(false), keep=KeepRequested.exchange(false);
    unsigned applyMask=ApplySlots.exchange(0), keepMask=KeepSlots.exchange(0);
    if (apply) applyMask=15;
    if (keep) keepMask=15;
    // SaveManager has joined its worker here. Serialize with all transports.
    dispatch_sync(Queue(), ^{
        NSFileManager* files=NSFileManager.defaultManager;
        NSString* root=[SOHAppleSyncDirectory() stringByAppendingPathComponent:@"Incoming"];
        NSUInteger applied=0, conflicts=0;
        NSMutableDictionary<NSString*,NSMutableSet*>* choices=[NSMutableDictionary dictionary];
        for (NSString* candidate in [files contentsOfDirectoryAtPath:root error:nil]) {
            NSData* json=[NSData dataWithContentsOfFile:[[root stringByAppendingPathComponent:candidate] stringByAppendingPathComponent:@"metadata.json"]];
            id info=json ? [NSJSONSerialization JSONObjectWithData:json options:0 error:nil] : nil;
            if (![info isKindOfClass:NSDictionary.class] || ![info[@"name"] isKindOfClass:NSString.class] || ![info[@"sha256"] isKindOfClass:NSString.class]) continue;
            if (!choices[info[@"name"]]) choices[info[@"name"]]=[NSMutableSet set];
            [choices[info[@"name"]] addObject:info[@"sha256"]];
        }
        for (NSString* candidate in [files contentsOfDirectoryAtPath:root error:nil]) {
            NSString* directory=[root stringByAppendingPathComponent:candidate];
            NSData* metadata=[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:@"metadata.json"]];
            id info=metadata ? [NSJSONSerialization JSONObjectWithData:metadata options:0 error:nil] : nil;
            if (![info isKindOfClass:NSDictionary.class]) continue;
#if !defined(SOH_SAVE_SYNC_TEST)
            if ([info[@"source"] isEqual:@"iCloud"] && (!SOHiCloudSync_AccountVerified() ||
                ![info[@"cloudAccount"] isEqual:[NSUserDefaults.standardUserDefaults stringForKey:@"SOHCloudAccount"]])) continue;
#endif
            NSString* name=info[@"name"];
            if (![name isKindOfClass:NSString.class] || !SaveSync::IsSaveName(name.UTF8String)) continue;
            NSUInteger slot=[Names() indexOfObject:name];
            unsigned bit=1u<<slot;
            if (!((applyMask|keepMask)&bit) && ![info[@"automatic"] boolValue]) continue;
            NSData* data=[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:name]];
            if (!(keepMask&bit)) {
                if (choices[name].count>1) { ++conflicts; continue; }
                if ([SOHSaveContentHash(Read(name)) isEqual:info[@"sha256"]]) {
                    // An identical repeated transfer needs no second replacement.
                    [files removeItemAtPath:directory error:nil];
                    continue;
                }
                if (![SOHSaveContentHash(data) isEqual:info[@"sha256"]] || ![SOHSaveContentHash(Read(name)) isEqual:info[@"expectedLocalHash"]]) { ++conflicts; continue; }
                [files createDirectoryAtPath:SOHAppleSaveDirectory() withIntermediateDirectories:YES attributes:nil error:nil];
                // Keep the replaced local save alongside the incoming candidate.
                NSData* old=Read(name);
                if (old && ![old writeToFile:[directory stringByAppendingPathComponent:@"previous.sav"] options:NSDataWritingAtomic error:nil]) { ++conflicts; continue; }
                if (![data writeToFile:[SOHAppleSaveDirectory() stringByAppendingPathComponent:name] options:NSDataWritingAtomic error:nil]) { ++conflicts; continue; }
                ++applied;
            }
            NSString* archive=[SOHAppleSyncDirectory() stringByAppendingPathComponent:@"History"];
            if ([info[@"source"] isEqual:@"iCloud"]) {
                NSMutableDictionary* bases=[[NSUserDefaults.standardUserDefaults dictionaryForKey:@"SOHCloudSaveBaselines"] mutableCopy] ?: [NSMutableDictionary dictionary];
                bases[name]=info[@"sha256"];
                [NSUserDefaults.standardUserDefaults setObject:bases forKey:@"SOHCloudSaveBaselines"];
            }
            if ([info[@"source"] isEqual:@"iCloud Drive"]) {
                NSString* key=[@"Save/" stringByAppendingString:name];
                for (NSString* stateName in [files contentsOfDirectoryAtPath:SOHAppleSyncDirectory() error:nil]) {
                    if (![stateName hasPrefix:@"folder-"] || ![stateName hasSuffix:@".json"]) continue;
                    NSString* statePath=[SOHAppleSyncDirectory() stringByAppendingPathComponent:stateName];
                    NSData* json=[NSData dataWithContentsOfFile:statePath];
                    id state=json ? [NSJSONSerialization JSONObjectWithData:json options:NSJSONReadingMutableContainers error:nil] : nil;
                    if (![state isKindOfClass:NSMutableDictionary.class] || ![state[key] isKindOfClass:NSDictionary.class]) continue;
                    NSString* pending=state[key][@"pending"];
                    if (![pending isKindOfClass:NSString.class] || ![pending hasSuffix:[@":" stringByAppendingString:info[@"sha256"]]]) continue;
                    state[key]=@{@"base":info[@"sha256"]};
                    [[NSJSONSerialization dataWithJSONObject:state options:0 error:nil] writeToFile:statePath options:NSDataWritingAtomic error:nil];
                }
            }
            if ([info[@"source"] isEqual:@"Selected sync folder"]) {
                NSMutableDictionary* baselines=[[NSUserDefaults.standardUserDefaults dictionaryForKey:@"SOHFolderSaveBaselines"] mutableCopy] ?: [NSMutableDictionary dictionary];
                baselines[name]=info[@"sha256"];
                [NSUserDefaults.standardUserDefaults setObject:baselines forKey:@"SOHFolderSaveBaselines"];
            }
            [files createDirectoryAtPath:archive withIntermediateDirectories:YES attributes:nil error:nil];
            [files moveItemAtPath:directory toPath:[archive stringByAppendingPathComponent:candidate] error:nil];
        }
        if (applied || conflicts || applyMask || keepMask) SetStatus([NSString stringWithFormat:@"%lu saves applied; %lu changed or ambiguous copies preserved. For multiple incoming versions, Keep Local then receive from the desired source again. Previous copies remain in SaveSync/History.",(unsigned long)applied,(unsigned long)conflicts]);
    });
}

#if !defined(__TVOS__)
static std::atomic_bool FolderBusy(false);
extern "C" int SOHNearbySync_AutomaticFolderEnabled(void) {
    return [NSUserDefaults.standardUserDefaults boolForKey:@"SOHAutomaticFolderSync"];
}
extern "C" void SOHNearbySync_SetAutomaticFolder(int enabled) {
    [NSUserDefaults.standardUserDefaults setBool:enabled != 0 forKey:@"SOHAutomaticFolderSync"];
    SetStatus(enabled ? @"Automatic folder sync enabled." : @"Automatic folder sync paused. Local saves and mods are unchanged.");
    if (enabled) SOHNearbySync_AutoFolderSync(1);
}
extern "C" void SOHNearbySync_AutoFolderSync(int includeMods) {
    static NSUInteger revision=0;
    static bool refreshMods=false;
    dispatch_async(Queue(), ^{
        static id observer;
        if (!observer) observer=[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(NSNotification* notification) { SOHNearbySync_AutoFolderSync(1); }];
        if (!SOHNearbySync_AutomaticFolderEnabled()) return;
        refreshMods=refreshMods || includeMods;
        NSUInteger current=++revision;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),Queue(), ^{
            if (current!=revision || !SOHNearbySync_AutomaticFolderEnabled()) return;
            if (FolderBusy) { SOHNearbySync_AutoFolderSync(refreshMods); return; }
            SOHNearbySync_SyncFolder();
            if (refreshMods) { refreshMods=false; SOHNearbySync_ImportMods(); }
        });
    });
}
extern "C" void SOHNearbySync_ChooseFolder(void) {
    SetStatus(@"Choose iCloud Drive or another location. SOH will create its Saves and Mods folders automatically.");
    SOHChooseSyncFolder(^(NSError* error) {
        if (!error) {
            [NSUserDefaults.standardUserDefaults removeObjectForKey:@"SOHFolderSaveBaselines"];
            [NSUserDefaults.standardUserDefaults removeObjectForKey:@"SOHFolderModVersions"];
        }
        SetStatus(error ? error.localizedDescription : @"SOH/Saves and SOH/Mods are ready. Automatic folder sync is enabled; local copies remain available offline.");
        if (!error) SOHNearbySync_AutoFolderSync(1);
    });
}
extern "C" void SOHNearbySync_SyncFolder(void) {
    if (!Ready()) return;
    if (FolderBusy.exchange(true)) return;
    SetStatus(@"Checking the selected folder…");
    SOHWithSyncFolder(^(NSURL* folder,NSError* accessError) {
        if (accessError) { FolderBusy=false; SetStatus(accessError.localizedDescription); return; }
        NSFileManager* files=NSFileManager.defaultManager;
        NSURL* saves=[folder URLByAppendingPathComponent:@"Saves" isDirectory:YES];
        NSError* error=nil;
        if (![files createDirectoryAtURL:saves withIntermediateDirectories:YES attributes:nil error:&error]) { FolderBusy=false; SetStatus(@"Cannot create Saves in the selected folder. Check provider availability and write access."); return; }
        NSMutableDictionary* baselines=[[NSUserDefaults.standardUserDefaults dictionaryForKey:@"SOHFolderSaveBaselines"] mutableCopy] ?: [NSMutableDictionary dictionary];
        __block NSUInteger staged=0,uploaded=0,failed=0;
        for (NSString* name in Names()) {
            NSURL* destination=[saves URLByAppendingPathComponent:name];
            NSFileCoordinator* coordinator=[[NSFileCoordinator alloc] initWithFilePresenter:nil];
            NSError* coordinationError=nil;
            [coordinator coordinateWritingItemAtURL:destination options:0 error:&coordinationError byAccessor:^(NSURL* url) {
                NSNumber* exists=nil;
                NSError* existenceError=nil;
                BOOL present=[url getResourceValue:&exists forKey:NSURLIsRegularFileKey error:&existenceError];
                if (!present && existenceError &&
                    !([existenceError.domain isEqual:NSCocoaErrorDomain] &&
                      (existenceError.code==NSFileReadNoSuchFileError || existenceError.code==NSFileNoSuchFileError))) { ++failed; return; }
                NSData* remote=present ? [NSData dataWithContentsOfURL:url options:0 error:nil] : nil;
                if (present && (!exists.boolValue || !remote || remote.length>8*1024*1024)) { ++failed; return; }
                NSData* local=Read(name);
                NSString* lh=SOHSaveContentHash(local), *rh=SOHSaveContentHash(remote);
                NSString* base=baselines[name] ?: @"";
                switch (SaveSync::Plan(lh.UTF8String,rh.UTF8String,base.UTF8String)) {
                    case SaveSync::Action::None: baselines[name]=lh; break;
                    case SaveSync::Action::Upload:
                        if ([local writeToURL:url options:NSDataWritingAtomic error:nil]) { baselines[name]=lh; ++uploaded; } else ++failed;
                        break;
                    case SaveSync::Action::Download:
                        if (SOHStageIncomingSave(name,remote,lh,@"Selected sync folder",nil,YES)) ++staged; else ++failed;
                        break;
                    case SaveSync::Action::Conflict:
                        if (SOHStageIncomingSave(name,remote,lh,@"Selected sync folder",nil)) ++staged; else ++failed;
                        break;
                }
            }];
            if (coordinationError) ++failed;
        }
        [NSUserDefaults.standardUserDefaults setObject:baselines forKey:@"SOHFolderSaveBaselines"];
        FolderBusy=false;
        SetStatus([NSString stringWithFormat:@"Folder check: %lu uploaded, %lu incoming staged, %lu unavailable. Review incoming saves before applying. iCloud upload timing is managed by iOS.",(unsigned long)uploaded,(unsigned long)staged,(unsigned long)failed]);
    });
}
extern "C" void SOHNearbySync_ImportMods(void) {
    SetStatus(@"Importing Mods from the selected folder. Keep the app open…");
    SOHWithSyncFolder(^(NSURL* folder,NSError* accessError) {
        if (accessError) { SetStatus(accessError.localizedDescription); return; }
        NSURL* source=[folder URLByAppendingPathComponent:@"Mods" isDirectory:YES];
        NSFileManager* files=NSFileManager.defaultManager;
        NSError* error=nil;
        NSArray<NSURL*>* entries=[files contentsOfDirectoryAtURL:source includingPropertiesForKeys:@[NSURLIsRegularFileKey,NSURLIsSymbolicLinkKey,NSURLFileSizeKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:&error];
        if (!entries) { SetStatus(@"Create a Mods folder inside the selected sync folder and add .otr or .o2r packs. The provider must be online for undownloaded files."); return; }
        NSString* staging=[SOHAppleSyncDirectory() stringByAppendingPathComponent:@"Mods"];
        [files createDirectoryAtPath:staging withIntermediateDirectories:YES attributes:nil error:nil];
        __block NSUInteger imported=0,failed=0;
        NSMutableDictionary* versions=[[NSUserDefaults.standardUserDefaults dictionaryForKey:@"SOHFolderModVersions"] mutableCopy] ?: [NSMutableDictionary dictionary];
        for (NSURL* entry in entries) {
            NSString* extension=entry.pathExtension.lowercaseString;
            if (![@[@"otr",@"o2r"] containsObject:extension]) continue;
            NSFileCoordinator* coordinator=[[NSFileCoordinator alloc] initWithFilePresenter:nil];
            NSError* coordinationError=nil;
            [coordinator coordinateReadingItemAtURL:entry options:0 error:&coordinationError byAccessor:^(NSURL* url) {
                NSDictionary* values=[url resourceValuesForKeys:@[NSURLIsRegularFileKey,NSURLIsSymbolicLinkKey,NSURLFileSizeKey,NSURLContentModificationDateKey] error:nil];
                if (![values[NSURLIsRegularFileKey] boolValue] || [values[NSURLIsSymbolicLinkKey] boolValue] ||
                    [values[NSURLFileSizeKey] unsignedLongLongValue]==0 || [values[NSURLFileSizeKey] unsignedLongLongValue]>4ULL*1024*1024*1024) { ++failed; return; }
                NSString* name=url.lastPathComponent;
                NSDate* date=values[NSURLContentModificationDateKey];
                NSString* fingerprint=[NSString stringWithFormat:@"%@-%.6f",values[NSURLFileSizeKey],date.timeIntervalSince1970];
                if (date && [versions[name] isEqual:fingerprint]) return;
                NSString* candidate=[staging stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
                if (![files createDirectoryAtPath:candidate withIntermediateDirectories:YES attributes:nil error:nil]) { ++failed; return; }
                if (![files copyItemAtURL:url toURL:[NSURL fileURLWithPath:[candidate stringByAppendingPathComponent:name]] error:nil]) { ++failed; return; }
                NSData* metadata=Encode(@{@"name":name,@"receivedAt":@(NSDate.date.timeIntervalSince1970)});
                if ([metadata writeToFile:[candidate stringByAppendingPathComponent:@"metadata.json"] options:NSDataWritingAtomic error:nil]) { ++imported; if (date) versions[name]=fingerprint; } else ++failed;
            }];
            if (coordinationError) ++failed;
        }
        [NSUserDefaults.standardUserDefaults setObject:versions forKey:@"SOHFolderModVersions"];
        if (imported || failed) SetStatus([NSString stringWithFormat:@"%lu mods staged, %lu unavailable. Fully close and reopen SOH to activate. Existing mods are not deleted by folder sync.",(unsigned long)imported,(unsigned long)failed]);
    });
}
extern "C" void SOHNearbySync_ActivateMods(void) {
    // Startup only, before ResourceManager opens any mod archives.
    NSFileManager* files=NSFileManager.defaultManager;
    NSString* root=[SOHAppleSyncDirectory() stringByAppendingPathComponent:@"Mods"];
    NSString* mods=[SOHAppleDataDirectory() stringByAppendingPathComponent:@"mods"];
    [files createDirectoryAtPath:mods withIntermediateDirectories:YES attributes:nil error:nil];
    NSArray* candidates=[[files contentsOfDirectoryAtPath:root error:nil] sortedArrayUsingComparator:^NSComparisonResult(NSString* a,NSString* b) {
        NSDictionary* aa=[files attributesOfItemAtPath:[[root stringByAppendingPathComponent:a] stringByAppendingPathComponent:@"metadata.json"] error:nil];
        NSDictionary* bb=[files attributesOfItemAtPath:[[root stringByAppendingPathComponent:b] stringByAppendingPathComponent:@"metadata.json"] error:nil];
        return [aa[NSFileModificationDate] compare:bb[NSFileModificationDate]];
    }];
    for (NSString* candidate in candidates) {
        NSString* directory=[root stringByAppendingPathComponent:candidate];
        NSData* metadata=[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:@"metadata.json"]];
        id info=metadata ? [NSJSONSerialization JSONObjectWithData:metadata options:0 error:nil] : nil;
        if (![info isKindOfClass:NSDictionary.class]) continue;
        NSString* name=info[@"name"];
        if (![name isKindOfClass:NSString.class] || ![name isEqual:name.lastPathComponent] ||
            ![@[@"otr",@"o2r"] containsObject:name.pathExtension.lowercaseString]) continue;
        NSString* source=[directory stringByAppendingPathComponent:name];
        NSString* destination=[mods stringByAppendingPathComponent:name];
        if (![files fileExistsAtPath:source]) continue;
        BOOL success=NO;
        if ([files fileExistsAtPath:destination]) {
            success=[files replaceItemAtURL:[NSURL fileURLWithPath:destination] withItemAtURL:[NSURL fileURLWithPath:source]
                backupItemName:[NSString stringWithFormat:@"%@.%@.previous",name,NSUUID.UUID.UUIDString] options:0 resultingItemURL:nil error:nil];
        } else success=[files moveItemAtPath:source toPath:destination error:nil];
        if (success) [files removeItemAtPath:directory error:nil];
    }
}
#endif
