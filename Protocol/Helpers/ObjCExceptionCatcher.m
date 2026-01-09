//
//  ObjCExceptionCatcher.m
//  Protocol
//
//  Objective-C helper to catch NSExceptions that Swift cannot catch.
//

#import "ObjCExceptionCatcher.h"

BOOL ObjCTryCatch(void (^tryBlock)(void),
                  NSError *_Nullable *_Nullable errorPtr) {
  @try {
    tryBlock();
    return YES;
  } @catch (NSException *exception) {
    if (errorPtr) {
      NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey : exception.reason
            ?: @"Unknown Objective-C exception",
        @"ExceptionName" : exception.name ?: @"Unknown",
        @"ExceptionCallStack" :
                [exception.callStackSymbols componentsJoinedByString:@"\n"]
            ?: @""
      };
      *errorPtr = [NSError errorWithDomain:@"ObjCExceptionDomain"
                                      code:1
                                  userInfo:userInfo];
    }
    return NO;
  }
}
