#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#include <assert.h>
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonCryptor.h>
#include <mach-o/dyld.h>
#include <dlfcn.h>

@implementation NSMutableURLRequest(Curl)

- (NSString *)description {
  
  __block NSMutableString *displayString = [NSMutableString stringWithFormat:@"curl -v -X %@", self.HTTPMethod];
  
  [displayString appendFormat:@" \'%@\'",  self.URL.absoluteString];
  
  [self.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(id key, id val, BOOL *stop) {
    [displayString appendFormat:@" -H \'%@: %@\'", key, val];
  }];
  
  if ([self.HTTPMethod isEqualToString:@"POST"] ||
      [self.HTTPMethod isEqualToString:@"PUT"] ||
      [self.HTTPMethod isEqualToString:@"PATCH"]) {
    
    [displayString appendFormat:@" -d \'%@\'",
     [[NSString alloc] initWithData:self.HTTPBody encoding:NSUTF8StringEncoding]];
  }
  
  return displayString;
}

@end

@implementation NSString (SHA256)

- (NSData *)SHA256
{
    const char *s = [self cStringUsingEncoding:NSUTF8StringEncoding];
    NSData *keyData = [NSData dataWithBytes:s length:strlen(s)];

    uint8_t digest[CC_SHA256_DIGEST_LENGTH] = {0};
    CC_SHA256(keyData.bytes, (CC_LONG)keyData.length, digest);
    NSData *out = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    return out;
}

@end

char LicEncContent[] = "\x03\x04\x02NSExtension";

%group ObjcHook
%hook SGNSARequestHelper 

// Hooking a class method
- (id)request:(NSMutableURLRequest *)req completeBlock:(void (^)(NSData *body, NSURLResponse *resp, NSError *err))completeBlock {
    __auto_type reqRawUrl = [req URL];
    __auto_type reqUrl = [[req URL] absoluteString];
    if (![reqUrl hasPrefix:@"https://www.surge-activation.com/ios/v3/"]) { return %orig; }
    if (!completeBlock) { return %orig; }
    
    __auto_type wrapper = ^(NSError *error, NSDictionary *data) {
        __auto_type resp = [[NSHTTPURLResponse alloc] initWithURL:reqRawUrl statusCode:200 HTTPVersion:@"1.1" headerFields:@{}];
        NSData *body = [NSJSONSerialization dataWithJSONObject:data options:0 error: &error];
        completeBlock(body, resp, error);
    };

    //NSLog(@"Surge License Request: %@ %@ %@", req, [req allHTTPHeaderFields], );
    NSLog(@"Surge License Request: %@", [req description]);
    if ([reqUrl hasSuffix:@"refresh"]) { // fake refresh req
        NSError *err = nil;
        NSDictionary *reqDict = [NSJSONSerialization JSONObjectWithData:req.HTTPBody
                                    options:kNilOptions
                                    error:&err];
        NSString *deviceID = reqDict[@"deviceID"];
        __auto_type keydata = [deviceID SHA256];
        const char *keybytes = [keydata bytes];
        char licEncOut[32] = { 0 };
        size_t encRet = 0;
        
        NSLog(@"key: %@ %x", keydata, *(uint32_t *)keybytes);

        CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, 
            keybytes, 0x20, keybytes + 16, 
            LicEncContent, sizeof(LicEncContent),
            licEncOut, 32, 
            &encRet);
        NSLog(@"encRet: %zu", encRet);

        __auto_type p = [[NSData dataWithBytes:(const void *)licEncOut length:16] base64EncodedStringWithOptions:0];
        NSLog(@"p: %@", p);
        
        [req setURL:[NSURL URLWithString:@"http://127.0.0.1:65536"]];
        void (^handler)(NSError *error, NSDictionary *data) = ^(NSError *error, NSDictionary *data){
            NSDictionary *licInfo = @{
                    @"deviceID": deviceID,
                    @"expirationDate": @4070880000, // 2099-01-01 00:00:00
                    @"fusDate": @4070880000,
                    @"type": @"licensed",
                    @"issueDate": [NSNumber numberWithInt:(long)[[NSDate date] timeIntervalSince1970]],
                    @"p": p,
                };
            NSLog(@"generated licInfo: %@", licInfo);
            NSData *licInfoData = [NSJSONSerialization dataWithJSONObject:licInfo options:0 error: &error];
            NSString *licInfoBase64 = [licInfoData base64EncodedStringWithOptions:0];
            wrapper(nil, @{
                @"license": @{
                    @"policy": licInfoBase64,
                    @"sign": @""
                }
            });
            
            //exit(0);
        };
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(nil, nil);
        });
    }
    
    if ([reqUrl hasSuffix:@"ac"]) { // disable refresh req
        [req setURL:[NSURL URLWithString:@"http://127.0.0.1:65536"]];
        void (^handler)(NSError *error, NSDictionary *data) = ^(NSError *error, NSDictionary *data){
            wrapper(nil, @{});
        };
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(nil, nil);
        });
    }
    
	return %orig;
}

%end
%end

void *pEVP_DigestVerifyFinal = NULL;

%group CHook
%hookf(uint64_t, pEVP_DigestVerifyFinal, void *ctx, uint64_t a2, uint64_t a3) {
    %orig;
    NSLog(@"Bypassed surge lic sign check!");
    return 1;
}
%end

static void doInitCHook(void) {
    %init(CHook);
}

%ctor {
    %init(ObjcHook);
    NSComparisonResult comparisonResult = [[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] compare:@"4.14.0" options:NSNumericSearch];
    if (comparisonResult == NSOrderedAscending) {
        unsigned char needle[] = "\x08\x01\x40\xF9\xA8\x83\x1C\xF8\xFF\x07\x00\xB9\x00\x10\x40\xF9\x08\x00\x40\xF9\x18\x45\x40\xF9\xA8\x46\x40\x39\x08\x02\x08\x37";
        intptr_t imgBase = (intptr_t)_dyld_get_image_vmaddr_slide(0) + 0x100000000LL;
        intptr_t imgBase2 = (intptr_t)_dyld_get_image_header(0);
        NSLog(@"Surge image base at %p %p", (void *)imgBase, (void *)imgBase2);
        //NSLog(@"Surge hdr %x %x %x %x %x", *(uint32_t *)(imgBase + 0x236730), *(uint32_t *)(imgBase + 0x236734), *(uint32_t *)(imgBase + 0x236738), *(uint32_t *)(imgBase + 0x23673c), *(uint32_t *)(imgBase + 0x236740));
        char *pNeedle = (char *)memmem((void *)imgBase, 0x400000, needle, sizeof(needle) - 1);
        NSLog(@"found pNeedle at %p", pNeedle);
        if (pNeedle == NULL) {
            exit(0);
        }
        pEVP_DigestVerifyFinal = pNeedle - 0x2c;
        doInitCHook();
    }
    else {
        if ([NSProcessInfo.processInfo.processName isEqualToString:@"Surge-iOS"]) {
            const char *imagename = [NSString stringWithFormat:@"%@/Frameworks/OpenSSL.framework/OpenSSL", NSBundle.mainBundle.bundlePath].UTF8String;
            dlopen(imagename, 1);
            pEVP_DigestVerifyFinal = MSFindSymbol(MSGetImageByName(imagename), "_EVP_DigestVerifyFinal");
            doInitCHook();
        }
    }
}