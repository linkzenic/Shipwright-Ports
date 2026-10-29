#import "../../soh/ios/SOHTVOSFileServer.mm"
#include <cassert>
#include <string>
std::string SaveSyncTestRoot;
extern "C" void SOHiCloudSync_LocalSaveChanged(const char*) {}
int main() { @autoreleasepool {
    SaveSyncTestRoot=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString].UTF8String;
    [NSFileManager.defaultManager createDirectoryAtPath:SOHAppleSaveDirectory() withIntermediateDirectories:YES attributes:nil error:nil];
    NSData* save=[@"{\"version\":1}" dataUsingEncoding:NSUTF8StringEncoding];
    [save writeToFile:[SOHAppleSaveDirectory() stringByAppendingPathComponent:@"file1.sav"] atomically:YES];
    nw_listener_t listener=nw_listener_create(nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,NW_PARAMETERS_DEFAULT_CONFIGURATION));
    nw_listener_set_queue(listener,ServerQueue());
    nw_listener_set_new_connection_handler(listener,^(nw_connection_t connection) {
        SOHTVOSHTTPConnection* handler=[[SOHTVOSHTTPConnection alloc] initWithConnection:connection]; [handler start];
    });
    nw_listener_set_state_changed_handler(listener,^(nw_listener_state_t state,nw_error_t error) {
        assert(state!=nw_listener_state_failed);
        if (state!=nw_listener_state_ready) return;
        NSString* base=[NSString stringWithFormat:@"http://127.0.0.1:%u",nw_listener_get_port(listener)];
        dispatch_group_t group=dispatch_group_create();
        for (NSString* path in @[@"/download/file1.sav",@"/download/file2.sav",@"/download/shipofharkinian.json",@"/upload/json/shipofharkinian.json",@"/upload/json/broken.json",@"/upload/json/%2E%2E%2Fevil.json"]) {
            dispatch_group_enter(group);
            NSMutableURLRequest* request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:[base stringByAppendingString:path]]];
            BOOL upload=[path hasPrefix:@"/upload/"];
            if (upload) {
                request.HTTPMethod=@"PUT";
                request.HTTPBody=[[path hasSuffix:@"broken.json"] ? @"invalid" : @"{\"scale\":2}" dataUsingEncoding:NSUTF8StringEncoding];
            }
            [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData* data,NSURLResponse* response,NSError* error) {
                assert(!error);
                NSInteger expected=upload ? ([path hasSuffix:@"broken.json"] ? 422 : ([path containsString:@"evil"] ? 415 : 201)) : ([path hasSuffix:@"file1.sav"] ? 200 : 404);
                assert(((NSHTTPURLResponse*)response).statusCode==expected);
                if (expected==200) assert([data isEqual:save]);
                dispatch_group_leave(group);
            }] resume];
        }
        dispatch_group_notify(group,ServerQueue(),^{
            NSString* config=[SOHAppleDataDirectory() stringByAppendingPathComponent:@"shipofharkinian.json"];
            assert(![NSFileManager.defaultManager fileExistsAtPath:config]);
            [@"{\"scale\":1}" writeToFile:config atomically:YES encoding:NSUTF8StringEncoding error:nil];
            SOHTVOSFileServer_ApplyJSONAtLaunch();
            assert([[NSString stringWithContentsOfFile:config encoding:NSUTF8StringEncoding error:nil] isEqual:@"{\"scale\":2}"]);
            assert([NSFileManager.defaultManager contentsOfDirectoryAtPath:[SOHAppleSyncDirectory() stringByAppendingPathComponent:@"History"] error:nil].count==1);
            [NSFileManager.defaultManager removeItemAtPath:SOHAppleDataDirectory() error:nil];
            puts("tvOS downloads, JSON upload validation, restart application and history tests passed."); exit(0);
        });
    });
    nw_listener_start(listener);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),ServerQueue(),^{exit(1);});
    dispatch_main();
} }
