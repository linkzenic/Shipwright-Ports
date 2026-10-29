// Exercise the production response/teardown path without writing app data.
#import "../../soh/ios/SOHTVOSFileServer.mm"
#include <cassert>

extern "C" void SOHiCloudSync_LocalSaveChanged(const char*) {}

int main() {
    @autoreleasepool {
        NSMutableData* body = [NSMutableData dataWithLength:128 * 1024];
        memset(body.mutableBytes, 'x', body.length);
        nw_parameters_t parameters = nw_parameters_create_secure_tcp(
            NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
        nw_parameters_set_local_endpoint(parameters, nw_endpoint_create_host("127.0.0.1", "0"));
        nw_listener_t listener = nw_listener_create(parameters);
        assert(listener);
        nw_listener_set_queue(listener, ServerQueue());
        nw_listener_set_new_connection_handler(listener, ^(nw_connection_t connection) {
            nw_connection_set_queue(connection, ServerQueue());
            nw_connection_start(connection);
            nw_connection_receive(connection, 1, 4096,
                ^(dispatch_data_t content, nw_content_context_t context, bool complete, nw_error_t error) {
                    assert(!error);
                    SendAndClose(connection, HTTPResponse(200, @"OK", @"application/octet-stream", body));
                });
        });
        nw_listener_set_state_changed_handler(listener, ^(nw_listener_state_t state, nw_error_t error) {
            assert(state != nw_listener_state_failed);
            if (state != nw_listener_state_ready) return;
            NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%u/", nw_listener_get_port(listener)]];
            [[[NSURLSession sharedSession] dataTaskWithURL:url
                completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
                    assert(!error);
                    assert([(NSHTTPURLResponse*)response statusCode] == 200);
                    assert([data isEqualToData:body]);
                    puts("tvOS HTTP response delivery passed");
                    exit(0);
                }] resume];
        });
        nw_listener_start(listener);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), ServerQueue(), ^{ exit(1); });
        dispatch_main();
    }
}
