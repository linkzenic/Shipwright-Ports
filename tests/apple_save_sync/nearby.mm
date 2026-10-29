// Exercise production framing, authentication, staging and apply guards over
// loopback. Only the game data directory and engine reset are test doubles.
#define SOH_SAVE_SYNC_TEST 1
#define __TVOS__ 1
#include "../../soh/ios/SOHNearbySync.mm"
#include <cassert>
#include <string>
#include <unistd.h>
std::string SaveSyncTestRoot;
extern "C" bool SohResetToFileSelectWithoutSaving(void) { return true; }

static NSDictionary* Call(NSDictionary* request) {
    dispatch_semaphore_t done=dispatch_semaphore_create(0);
    __block NSDictionary* result;
    dispatch_async(Queue(), ^{ Request(request,^(NSDictionary* value) { result=value; dispatch_semaphore_signal(done); }); });
    assert(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC))==0);
    return result;
}
int main() { @autoreleasepool {
    NSString* root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    SaveSyncTestRoot=root.UTF8String;
    [NSFileManager.defaultManager createDirectoryAtPath:SOHAppleSaveDirectory() withIntermediateDirectories:YES attributes:nil error:nil];
    SOHNearbySync_Start();
    __block uint16_t port=0;
    for (int i=0;i<100 && !port;++i) {
        usleep(50000);
        dispatch_sync(Queue(), ^{ if (Listener) port=nw_listener_get_port(Listener); });
    }
    assert(port);
    __block NSString* code;
    dispatch_sync(Queue(), ^{ PeerHost=@"127.0.0.1"; PeerPort=[NSString stringWithFormat:@"%u",port]; code=Code; });
    assert(Call(@{@"op":@"manifest"})[@"error"]);
    NSString* callback=RandomToken();
    NSDictionary* pair=Call(@{@"op":@"pair",@"code":code,@"returnPort":@(port),@"returnToken":callback});
    NSString* token=pair[@"token"];
    assert(token.length>=32);
    assert([PeerToken isEqual:callback]);
    assert(Call(@{@"op":@"pair",@"code":code})[@"error"]); // one-use code
    assert(Call(@{@"op":@"get",@"name":@"../file1.sav",@"token":token})[@"error"]);
    assert(Call(@{@"op":@"manifest",@"token":@"wrong"})[@"error"]);
    NSData* payload=Encode(@{@"version":@1,@"sections":@{@"base":@{@"data":@{}}}});
    NSDictionary* put=@{@"op":@"put",@"name":@"file1.sav",@"expected":@"",@"data":[payload base64EncodedStringWithOptions:0],@"token":token};
    assert([Call(put)[@"ok"] boolValue]);
    assert(!Read(@"file1.sav")); // transfer cannot overwrite active slot
    SOHNearbySync_ApplyIncoming();
    SOHNearbySync_PrepareSaves();
    assert([Read(@"file1.sav") isEqual:payload]);
    assert(Call(put)[@"error"]); // stale compare-and-swap rejected
    assert(!SOHStageIncomingSave(@"file2.sav",[@"garbage" dataUsingEncoding:NSUTF8StringEncoding],@"",@"test",nil));
    NSData* changed=Encode(@{@"version":@2,@"sections":@{@"base":@{@"data":@{}}}});
    assert(SOHStageIncomingSave(@"file1.sav",changed,SOHSaveContentHash(payload),@"test",nil));
    NSData* newer=Encode(@{@"version":@3,@"sections":@{@"base":@{@"data":@{}}}});
    [newer writeToFile:[SOHAppleSaveDirectory() stringByAppendingPathComponent:@"file1.sav"] atomically:YES];
    SOHNearbySync_ApplyIncoming(); SOHNearbySync_PrepareSaves();
    assert([Read(@"file1.sav") isEqual:newer]); // newer local content wins guard
    assert(SOHStageIncomingSave(@"file2.sav",payload,@"",@"test",nil));
    SOHNearbySync_ChooseSlot(0,0); SOHNearbySync_PrepareSaves();
    assert(!Read(@"file2.sav")); // choosing file 1 cannot affect file 2
    SOHNearbySync_ChooseSlot(1,1); SOHNearbySync_PrepareSaves();
    assert([Read(@"file2.sav") isEqual:payload]);
    assert(SOHStageIncomingSave(@"file3.sav",payload,@"",@"Selected sync folder",nil,YES));
    SOHNearbySync_PrepareSaves();
    assert([Read(@"file3.sav") isEqual:payload]); // unambiguous download at safe boundary
    SOHNearbySync_Stop(); dispatch_sync(Queue(), ^{});
    [NSFileManager.defaultManager removeItemAtPath:root error:nil];
    puts("Nearby loopback, authentication, staging and apply tests passed.");
} }
