#import <Foundation/Foundation.h>

%hook NSFileManager
- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path error:(id)err {
    if ([path isEqualToString:@"/Library"]) {
        return %orig(@"/BypassJailbreakDetection", err);
    }
    return %orig;
}

%end