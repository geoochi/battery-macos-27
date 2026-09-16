#pragma once
#import <Foundation/Foundation.h>
@protocol BATTNativeClient
- (NSArray *)availableChargeLimitsWithError:(NSError **)error;
- (unsigned char)getMCLLimitWithError:(NSError **)error;
- (NSUInteger)isMCLCurrentlyEnabled:(NSError **)error;
- (BOOL)setMCLLimit:(unsigned char)limit error:(NSError **)error;
@end
id<BATTNativeClient> nativeClient(NSError **error);
NSDictionary *nativeSnapshot(id<BATTNativeClient> client, NSError **error);
BOOL nativeSetLimit(id<BATTNativeClient> client, NSInteger limit, NSError **error);
