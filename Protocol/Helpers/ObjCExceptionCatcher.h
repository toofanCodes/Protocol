//
//  ObjCExceptionCatcher.h
//  Protocol
//
//  Objective-C helper to catch NSExceptions that Swift cannot catch.
//  Used to sandbox Google Drive API calls that may throw ObjC exceptions.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Executes a block and catches any Objective-C exceptions.
/// Swift cannot catch Objective-C exceptions, so this helper bridges that gap.
/// @param tryBlock The block to execute
/// @param errorPtr Pointer to store any caught exception as NSError
/// @return YES if the block executed successfully, NO if an exception was caught
BOOL ObjCTryCatch(void (^tryBlock)(void), NSError * _Nullable * _Nullable errorPtr);

NS_ASSUME_NONNULL_END
