#import "SOHSharedSaveFiles.h"
#include "SaveSyncPolicy.h"
#include "ship/Context.h"
#import <CommonCrypto/CommonDigest.h>

NSString* SOHAppleDataDirectory(void) {
    return [NSString stringWithUTF8String:Ship::Context::GetAppDirectoryPath().c_str()];
}
NSString* SOHAppleSaveDirectory(void) {
    return [SOHAppleDataDirectory() stringByAppendingPathComponent:@"Save"];
}
NSString* SOHAppleSyncDirectory(void) {
    return [SOHAppleDataDirectory() stringByAppendingPathComponent:@"SaveSync"];
}
NSString* SOHSaveContentHash(NSData* data) {
    if (!data) return @"";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString* result = [NSMutableString stringWithCapacity:64];
    for (unsigned char byte : digest) [result appendFormat:@"%02x", byte];
    return result;
}
BOOL SOHStageIncomingSave(NSString* name, NSData* data, NSString* expectedLocalHash,
                         NSString* source, NSError** error, BOOL automatic) {
    if (!name || !SaveSync::IsSaveName(name.UTF8String) || !data || data.length == 0 ||
        data.length > 8 * 1024 * 1024) {
        if (error) *error = [NSError errorWithDomain:@"SOHSaveSync" code:1
            userInfo:@{NSLocalizedDescriptionKey:@"Invalid save name or size."}];
        return NO;
    }
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![object isKindOfClass:NSDictionary.class] || ![object[@"version"] isKindOfClass:NSNumber.class] ||
        (![name isEqualToString:@"global.sav"] &&
         (![object[@"sections"] isKindOfClass:NSDictionary.class] ||
          ![object[@"sections"][@"base"] isKindOfClass:NSDictionary.class] ||
          ![object[@"sections"][@"base"][@"data"] isKindOfClass:NSDictionary.class]))) {
        if (error) *error = [NSError errorWithDomain:@"SOHSaveSync" code:2
            userInfo:@{NSLocalizedDescriptionKey:@"Incoming file is not a recognized SOH save."}];
        return NO;
    }
    // Repeated background checks must not accumulate identical candidates.
    NSString* incomingRoot=[SOHAppleSyncDirectory() stringByAppendingPathComponent:@"Incoming"];
    NSString* hash=SOHSaveContentHash(data);
    for (NSString* existing in [NSFileManager.defaultManager contentsOfDirectoryAtPath:incomingRoot error:nil]) {
        NSData* metadata=[NSData dataWithContentsOfFile:[[incomingRoot stringByAppendingPathComponent:existing] stringByAppendingPathComponent:@"metadata.json"]];
        id info=metadata ? [NSJSONSerialization JSONObjectWithData:metadata options:0 error:nil] : nil;
        if ([info isKindOfClass:NSDictionary.class] && [info[@"name"] isEqual:name] &&
            [info[@"sha256"] isEqual:hash] && [info[@"expectedLocalHash"] isEqual:expectedLocalHash ?: @""] &&
            [info[@"source"] isEqual:source ?: @"Nearby device"]) return YES;
    }
    // Unique immutable candidates preserve simultaneous transfers and conflicts.
    NSString* directory = [[SOHAppleSyncDirectory() stringByAppendingPathComponent:@"Incoming"]
                           stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSFileManager* files = NSFileManager.defaultManager;
    if (![files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    if (![data writeToFile:[directory stringByAppendingPathComponent:name] options:NSDataWritingAtomic error:error]) return NO;
    NSDictionary* metadata = @{ @"name":name, @"sha256":SOHSaveContentHash(data),
        @"expectedLocalHash":expectedLocalHash ?: @"", @"source":source ?: @"Nearby device",
        @"receivedAt":@(NSDate.date.timeIntervalSince1970), @"schema":@1, @"automatic":@(automatic),
        @"cloudAccount":[NSUserDefaults.standardUserDefaults stringForKey:@"SOHCloudAccount"] ?: @"" };
    NSData* json = [NSJSONSerialization dataWithJSONObject:metadata options:0 error:error];
    // metadata.json is the commit marker: incomplete candidates are never applied.
    return json && [json writeToFile:[directory stringByAppendingPathComponent:@"metadata.json"]
                            options:NSDataWritingAtomic error:error];
}
