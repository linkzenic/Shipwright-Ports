#import "SOHTVOSFileServer.h"
#import "SOHiCloudSync.h"

#import <Foundation/Foundation.h>
#import <Network/Network.h>

#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netdb.h>
#include <sys/socket.h>

#include <atomic>
#include <cstring>

namespace {

constexpr uint64_t kMaximumUploadBytes = 4ULL * 1024ULL * 1024ULL * 1024ULL;
constexpr size_t kMaximumHeaderBytes = 64 * 1024;

dispatch_queue_t ServerQueue() {
    static dispatch_queue_t queue =
        dispatch_queue_create("com.shipofharkinian.tvos-file-transfer", DISPATCH_QUEUE_SERIAL);
    return queue;
}

NSObject* gStatusLock = [[NSObject alloc] init];
NSString* gStatus = @"Apple TV file transfer is off.";
nw_listener_t gListener = nullptr;
std::atomic_bool gRunning(false);

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
        NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString* caches = paths.firstObject ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"];
    return [caches stringByAppendingPathComponent:@"Ship of Harkinian"];
}

NSString* TransferURL() {
    struct ifaddrs* interfaces = nullptr;
    if (getifaddrs(&interfaces) != 0) {
        return @"http://Apple-TV.local:8080";
    }

    NSString* result = nil;
    for (struct ifaddrs* current = interfaces; current != nullptr; current = current->ifa_next) {
        if (current->ifa_addr == nullptr || current->ifa_addr->sa_family != AF_INET ||
            (current->ifa_flags & IFF_UP) == 0 || (current->ifa_flags & IFF_LOOPBACK) != 0) {
            continue;
        }
        char host[NI_MAXHOST] = {};
        if (getnameinfo(current->ifa_addr, sizeof(struct sockaddr_in), host, sizeof(host),
                        nullptr, 0, NI_NUMERICHOST) == 0) {
            result = [NSString stringWithFormat:@"http://%s:8080", host];
            break;
        }
    }
    freeifaddrs(interfaces);
    return result ?: @"http://Apple-TV.local:8080";
}

bool IsAllowedGameDataExtension(NSString* filename) {
    static NSSet<NSString*>* allowed = [NSSet setWithArray:@[
        @"o2r", @"otr", @"z64", @"n64", @"v64"
    ]];
    return [allowed containsObject:filename.pathExtension.lowercaseString];
}

bool IsSupportedSaveFile(NSString* filename) {
    static NSSet<NSString*>* allowed = [NSSet setWithArray:@[
        @"global.sav", @"file1.sav", @"file2.sav", @"file3.sav"
    ]];
    return [allowed containsObject:filename.lowercaseString];
}

NSData* HTTPResponse(NSInteger status, NSString* reason, NSString* contentType, NSData* body) {
    NSString* header = [NSString
        stringWithFormat:@"HTTP/1.1 %ld %@\r\n"
                         "Content-Type: %@\r\n"
                         "Content-Length: %lu\r\n"
                         "Cache-Control: no-store\r\n"
                         "Connection: close\r\n\r\n",
                         (long)status, reason, contentType, (unsigned long)body.length];
    NSMutableData* response = [NSMutableData dataWithData:[header dataUsingEncoding:NSUTF8StringEncoding]];
    [response appendData:body];
    return response;
}

NSData* TextResponse(NSInteger status, NSString* reason, NSString* text) {
    return HTTPResponse(status, reason, @"text/plain; charset=utf-8",
                        [text dataUsingEncoding:NSUTF8StringEncoding]);
}

NSData* TransferPage() {
    NSString* html =
        @"<!doctype html><html><head><meta name=viewport content='width=device-width,initial-scale=1'>"
         "<title>Ship of Harkinian Transfer</title><style>"
         "body{font-family:-apple-system,system-ui;background:#071526;color:#edf7ff;max-width:760px;"
         "margin:48px auto;padding:0 24px}h1{color:#55b9ff}section{background:#10283f;padding:24px;"
         "border-radius:16px}input,select,button{font:inherit;margin:8px 0;padding:12px;border-radius:8px;"
         "border:0}button{background:#168ce5;color:white;font-weight:700}progress{width:100%;height:22px}"
         "#status{white-space:pre-wrap;margin-top:14px;color:#a9d9ff}</style></head><body>"
         "<h1>Ship of Harkinian</h1><section><p>Upload game data, mods, or SOH save files to this Apple TV."
         " Save uploads synchronize through private iCloud when iCloud save sync is enabled.</p>"
         "<select id=folder><option value=root>Game data</option><option value=mods>Mod</option>"
         "<option value=saves>Save files</option></select><br>"
         "<input id=file type=file multiple accept='.o2r,.otr,.z64,.n64,.v64,.sav'><br>"
         "<button onclick=uploadFiles()>Upload</button><progress id=progress max=100 value=0></progress>"
         "<div id=status>Ready.</div></section><script>"
         "const fileInput=document.getElementById('file'),folderInput=document.getElementById('folder'),"
         "progressBar=document.getElementById('progress'),statusText=document.getElementById('status');"
         "async function uploadFiles(){const fs=[...fileInput.files];"
         "if(!fs.length){statusText.textContent='Choose a file first.';return;}"
         "for(let i=0;i<fs.length;i++){const f=fs[i];await new Promise((ok,fail)=>{"
         "const x=new XMLHttpRequest();x.open('PUT','/upload/'+folderInput.value+'/'+encodeURIComponent(f.name));"
         "x.upload.onprogress=e=>{if(e.lengthComputable)progressBar.value=e.loaded/e.total*100};"
         "x.onload=()=>{statusText.textContent=x.responseText||('Upload failed (HTTP '+x.status+').');"
         "x.status<300?ok():fail(new Error(statusText.textContent))};"
         "x.onerror=()=>{statusText.textContent='Network connection interrupted.';fail(new Error('network'))};"
         "statusText.textContent='Uploading '+f.name+'…';x.send(f)}).catch(()=>{"
         "throw new Error(statusText.textContent)})}"
         "statusText.textContent='Upload complete. Choose Rescan on the Apple TV.'}</script></body></html>";
    return HTTPResponse(200, @"OK", @"text/html; charset=utf-8",
                        [html dataUsingEncoding:NSUTF8StringEncoding]);
}

void SendAndClose(nw_connection_t connection, NSData* response) {
    void* bytes = malloc(response.length);
    if (bytes == nullptr) {
        nw_connection_cancel(connection);
        return;
    }
    memcpy(bytes, response.bytes, response.length);
    dispatch_data_t payload =
        dispatch_data_create(bytes, response.length, ServerQueue(), DISPATCH_DATA_DESTRUCTOR_FREE);
    nw_connection_send(connection, payload, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true,
                       ^(nw_error_t error) {
                           nw_connection_cancel(connection);
                       });
}

} // namespace

@interface SOHTVOSHTTPConnection : NSObject

@property(nonatomic, strong) nw_connection_t connection;
@property(nonatomic, strong) NSMutableData* pendingHeader;
@property(nonatomic, strong) NSFileHandle* output;
@property(nonatomic, copy) NSString* temporaryPath;
@property(nonatomic, copy) NSString* destinationPath;
@property(nonatomic, copy) NSString* displayName;
@property(nonatomic) BOOL uploadedSave;
@property(nonatomic) uint64_t contentLength;
@property(nonatomic) uint64_t receivedLength;
@property(nonatomic) BOOL headersComplete;
@property(nonatomic) BOOL finished;

- (instancetype)initWithConnection:(nw_connection_t)connection;
- (void)start;

@end

@implementation SOHTVOSHTTPConnection

- (instancetype)initWithConnection:(nw_connection_t)connection {
    self = [super init];
    if (self != nil) {
        self.connection = connection;
        self.pendingHeader = [NSMutableData data];
    }
    return self;
}

- (void)start {
    nw_connection_set_queue(self.connection, ServerQueue());
    nw_connection_start(self.connection);
    [self receiveNext];
}

- (void)receiveNext {
    if (self.finished) {
        return;
    }
    SOHTVOSHTTPConnection* retainedSelf = self;
    nw_connection_receive(self.connection, 1, 64 * 1024,
                          ^(dispatch_data_t content, nw_content_context_t context,
                            bool isComplete, nw_error_t error) {
                              SOHTVOSHTTPConnection* strongSelf = retainedSelf;
                              if (error != nullptr) {
                                  [strongSelf fail:@"Network transfer interrupted." status:500];
                                  return;
                              }
                              if (content != nullptr) {
                                  const void* bytes = nullptr;
                                  size_t length = 0;
                                  dispatch_data_t contiguous =
                                      dispatch_data_create_map(content, &bytes, &length);
                                  (void)contiguous;
                                  if (bytes != nullptr && length > 0) {
                                      [strongSelf consumeBytes:bytes length:length];
                                  }
                              }
                              if (!strongSelf.finished && isComplete) {
                                  if (strongSelf.headersComplete &&
                                      strongSelf.receivedLength == strongSelf.contentLength) {
                                      [strongSelf finishUpload];
                                  } else {
                                      [strongSelf fail:@"Upload ended before the complete file arrived." status:400];
                                  }
                                  return;
                              }
                              [strongSelf receiveNext];
                          });
}

- (void)consumeBytes:(const void*)bytes length:(size_t)length {
    if (!self.headersComplete) {
        [self.pendingHeader appendBytes:bytes length:length];
        if (self.pendingHeader.length > kMaximumHeaderBytes) {
            [self fail:@"Request headers are too large." status:431];
            return;
        }
        NSData* marker = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
        NSRange boundary = [self.pendingHeader rangeOfData:marker options:0
                                                    range:NSMakeRange(0, self.pendingHeader.length)];
        if (boundary.location == NSNotFound) {
            return;
        }

        NSUInteger bodyStart = NSMaxRange(boundary);
        NSData* body = bodyStart < self.pendingHeader.length
                           ? [self.pendingHeader subdataWithRange:
                                 NSMakeRange(bodyStart, self.pendingHeader.length - bodyStart)]
                           : [NSData data];
        NSData* headerData =
            [self.pendingHeader subdataWithRange:NSMakeRange(0, boundary.location)];
        self.pendingHeader = nil;
        if (![self parseHeaders:headerData]) {
            return;
        }
        if (body.length > 0) {
            [self consumeBody:body];
        }
        return;
    }

    [self consumeBody:[NSData dataWithBytes:bytes length:length]];
}

- (BOOL)parseHeaders:(NSData*)data {
    NSString* headers = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSArray<NSString*>* lines = [headers componentsSeparatedByString:@"\r\n"];
    NSArray<NSString*>* request =
        [lines.firstObject componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (request.count < 2) {
        [self fail:@"Malformed HTTP request." status:400];
        return NO;
    }

    NSString* method = request[0].uppercaseString;
    NSString* target = request[1];
    if ([method isEqualToString:@"GET"] && [target isEqualToString:@"/"]) {
        self.finished = YES;
        SendAndClose(self.connection, TransferPage());
        return NO;
    }
    if (![method isEqualToString:@"PUT"] || ![target hasPrefix:@"/upload/"]) {
        [self fail:@"Open the root page and use its Upload button." status:404];
        return NO;
    }

    uint64_t contentLength = 0;
    for (NSString* line in lines) {
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound) {
            continue;
        }
        NSString* key =
            [[line substringToIndex:colon.location] stringByTrimmingCharactersInSet:
                NSCharacterSet.whitespaceCharacterSet].lowercaseString;
        if ([key isEqualToString:@"content-length"]) {
            contentLength = [[[line substringFromIndex:colon.location + 1]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] longLongValue];
        }
    }
    if (contentLength == 0 || contentLength > kMaximumUploadBytes) {
        [self fail:@"The upload is empty or exceeds the 4 GB transfer limit." status:413];
        return NO;
    }

    NSArray<NSString*>* components = [target componentsSeparatedByString:@"/"];
    if (components.count != 4) {
        [self fail:@"Invalid upload destination." status:400];
        return NO;
    }
    NSString* category = components[2];
    NSString* decoded = [components[3] stringByRemovingPercentEncoding];
    NSString* filename = decoded.lastPathComponent;
    if (filename.length == 0 || ![filename isEqualToString:decoded]) {
        [self fail:@"Invalid upload filename." status:415];
        return NO;
    }

    NSString* directory = DocumentsPath();
    if ([category isEqualToString:@"mods"]) {
        if (!IsAllowedGameDataExtension(filename)) {
            [self fail:@"Mods must be .o2r or .otr files." status:415];
            return NO;
        }
        directory = [directory stringByAppendingPathComponent:@"mods"];
    } else if ([category isEqualToString:@"saves"]) {
        if (!IsSupportedSaveFile(filename)) {
            [self fail:@"Supported saves: global.sav, file1.sav, file2.sav, and file3.sav." status:415];
            return NO;
        }
        directory = [directory stringByAppendingPathComponent:@"Save"];
        self.uploadedSave = YES;
    } else if ([category isEqualToString:@"root"]) {
        if (!IsAllowedGameDataExtension(filename)) {
            [self fail:@"Game data must be .o2r, .otr, .z64, .n64, or .v64 files." status:415];
            return NO;
        }
    } else {
        [self fail:@"Invalid upload category." status:400];
        return NO;
    }

    NSError* directoryError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
                                   withIntermediateDirectories:YES attributes:nil
                                                        error:&directoryError]) {
        NSString* detail = directoryError.localizedDescription ?: @"unknown filesystem error";
        [self fail:[@"Apple TV storage could not be prepared: " stringByAppendingString:detail]
             status:500];
        return NO;
    }

    self.contentLength = contentLength;
    self.destinationPath = [directory stringByAppendingPathComponent:filename];
    self.displayName = filename;
    self.temporaryPath = [directory stringByAppendingPathComponent:
        [NSString stringWithFormat:@".upload-%@", NSUUID.UUID.UUIDString]];
    if (![[NSFileManager defaultManager] createFileAtPath:self.temporaryPath contents:nil attributes:nil]) {
        [self fail:@"The temporary upload file could not be created." status:500];
        return NO;
    }
    self.output = [NSFileHandle fileHandleForWritingAtPath:self.temporaryPath];
    if (self.output == nil) {
        [self fail:@"The uploaded file could not be opened for writing." status:500];
        return NO;
    }
    self.headersComplete = YES;
    WriteStatus([NSString stringWithFormat:@"Receiving %@ — 0%%", filename]);
    return YES;
}

- (void)consumeBody:(NSData*)data {
    if (self.finished || data.length == 0) {
        return;
    }
    uint64_t remaining = self.contentLength - self.receivedLength;
    NSUInteger accepted = (NSUInteger)MIN((uint64_t)data.length, remaining);
    @try {
        [self.output writeData:
            accepted == data.length ? data : [data subdataWithRange:NSMakeRange(0, accepted)]];
    } @catch (NSException* exception) {
        [self fail:@"Apple TV storage ran out of space or became unavailable." status:507];
        return;
    }
    self.receivedLength += accepted;
    NSInteger percent = (NSInteger)((self.receivedLength * 100) / self.contentLength);
    WriteStatus([NSString stringWithFormat:@"Receiving %@ — %ld%%", self.displayName, (long)percent]);
    if (self.receivedLength == self.contentLength) {
        [self finishUpload];
    }
}

- (void)finishUpload {
    if (self.finished) {
        return;
    }
    self.finished = YES;
    [self.output closeFile];
    self.output = nil;

    NSFileManager* files = [NSFileManager defaultManager];
    NSError* error = nil;
    BOOL installed = NO;
    if ([files fileExistsAtPath:self.destinationPath]) {
        installed = [files replaceItemAtURL:[NSURL fileURLWithPath:self.destinationPath]
                              withItemAtURL:[NSURL fileURLWithPath:self.temporaryPath]
                             backupItemName:nil options:0 resultingItemURL:nil error:&error];
    } else {
        installed = [files moveItemAtPath:self.temporaryPath toPath:self.destinationPath error:&error];
    }
    if (!installed) {
        [files removeItemAtPath:self.temporaryPath error:nil];
        WriteStatus([@"Upload could not be installed: "
            stringByAppendingString:error.localizedDescription ?: @"unknown storage error"]);
        SendAndClose(self.connection, TextResponse(500, @"Internal Server Error",
                                                   @"The file arrived but could not be installed."));
        return;
    }

    if (self.uploadedSave) {
        SOHiCloudSync_LocalSaveChanged(self.destinationPath.UTF8String);
    }
    WriteStatus([NSString stringWithFormat:self.uploadedSave
        ? @"%@ uploaded and queued for iCloud sync."
        : @"%@ uploaded. Choose Rescan in the app.", self.displayName]);
    SendAndClose(self.connection, TextResponse(201, @"Created",
        self.uploadedSave ? @"Save uploaded and queued for iCloud sync."
                          : @"Upload complete. Choose Rescan on the Apple TV."));
}

- (void)fail:(NSString*)message status:(NSInteger)status {
    if (self.finished) {
        return;
    }
    self.finished = YES;
    [self.output closeFile];
    self.output = nil;
    if (self.temporaryPath != nil) {
        [[NSFileManager defaultManager] removeItemAtPath:self.temporaryPath error:nil];
    }
    WriteStatus(message);
    SendAndClose(self.connection, TextResponse(status, @"Upload Error", message));
}

@end

extern "C" void SOHTVOSFileServer_Start(void) {
    WriteStatus([NSString stringWithFormat:@"Starting Apple TV file transfer… Open %@",
                                           TransferURL()]);
    dispatch_async(ServerQueue(), ^{
        if (gListener != nullptr) {
            return;
        }
        nw_parameters_t parameters =
            nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,
                                            NW_PARAMETERS_DEFAULT_CONFIGURATION);
        gListener = nw_listener_create_with_port("8080", parameters);
        if (gListener == nullptr) {
            WriteStatus(@"Could not start Apple TV file transfer.");
            return;
        }
        nw_advertise_descriptor_t descriptor =
            nw_advertise_descriptor_create_bonjour_service("Ship of Harkinian",
                                                            "_soh-transfer._tcp", nullptr);
        nw_listener_set_advertise_descriptor(gListener, descriptor);
        nw_listener_set_queue(gListener, ServerQueue());
        nw_listener_set_state_changed_handler(gListener, ^(nw_listener_state_t state, nw_error_t error) {
            if (state == nw_listener_state_ready) {
                gRunning.store(true);
                WriteStatus([NSString stringWithFormat:
                    @"On a phone or computer on this network, open %@",
                    TransferURL()]);
            } else if (state == nw_listener_state_failed) {
                gRunning.store(false);
                WriteStatus(@"Apple TV file transfer failed to start.");
                nw_listener_cancel(gListener);
                gListener = nullptr;
            } else if (state == nw_listener_state_cancelled) {
                gRunning.store(false);
                gListener = nullptr;
            }
        });
        nw_listener_set_new_connection_handler(gListener, ^(nw_connection_t connection) {
            SOHTVOSHTTPConnection* handler =
                [[SOHTVOSHTTPConnection alloc] initWithConnection:connection];
            [handler start];
        });
        nw_listener_start(gListener);
    });
}

extern "C" void SOHTVOSFileServer_Stop(void) {
    dispatch_async(ServerQueue(), ^{
        if (gListener != nullptr) {
            nw_listener_cancel(gListener);
        }
        gRunning.store(false);
        WriteStatus(@"Apple TV file transfer is off.");
    });
}

extern "C" int SOHTVOSFileServer_IsRunning(void) {
    return gRunning.load() ? 1 : 0;
}

extern "C" void SOHTVOSFileServer_GetStatus(char* buffer, size_t bufferSize) {
    if (buffer == nullptr || bufferSize == 0) {
        return;
    }
    const char* status = ReadStatus().UTF8String ?: "Apple TV file transfer is unavailable.";
    std::strncpy(buffer, status, bufferSize - 1);
    buffer[bufferSize - 1] = '\0';
}
