#import "native.h"
#include <dlfcn.h>
@interface NSObject (BATTNativeInit)
- (id)initWithClientName:(NSString *)name;
@end
static NSError *nativeError(NSInteger code, NSString *message) {
 return [NSError errorWithDomain:@"battctl.native" code:code userInfo:@{NSLocalizedDescriptionKey:message}];
}
id<BATTNativeClient> nativeClient(NSError **error) {
 static void *handle;
 if(!handle)handle=dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI",RTLD_NOW|RTLD_LOCAL);
 Class cls=NSClassFromString(@"PowerUISmartChargeClient");
 if(!handle||!cls||![cls instancesRespondToSelector:@selector(initWithClientName:)]){
  if(error)*error=nativeError(1,@"PowerUI manual charge-limit API is unavailable.");return nil;
 }
 id c=[[cls alloc]initWithClientName:@"com.geoochi.battctl"];
 SEL selectors[]={@selector(availableChargeLimitsWithError:),@selector(getMCLLimitWithError:),@selector(isMCLCurrentlyEnabled:),@selector(setMCLLimit:error:)};
 for(unsigned i=0;i<sizeof(selectors)/sizeof(selectors[0]);i++)if(![c respondsToSelector:selectors[i]]){
  if(error)*error=nativeError(1,@"PowerUI API changed; refusing to write.");return nil;
 }
 return c;
}
NSDictionary *nativeSnapshot(id<BATTNativeClient> c,NSError **error) {
 if(!c){if(error)*error=nativeError(1,@"No native client.");return nil;}
 NSError *e=nil;NSArray *limits=[c availableChargeLimitsWithError:&e];
 if(e||![limits isKindOfClass:NSArray.class]){if(error)*error=e?:nativeError(2,@"Cannot read supported charge limits.");return nil;}
 NSMutableArray *validated=[NSMutableArray array];
 for(id n in limits){if(![n isKindOfClass:NSNumber.class]||[n integerValue]<20||[n integerValue]>100||[n doubleValue]!=[n integerValue]){
  if(error)*error=nativeError(2,@"Invalid supported-limit response; refusing to write.");return nil;}[validated addObject:n];}
 unsigned value=[c getMCLLimitWithError:&e];if(e){if(error)*error=e;return nil;}
 NSUInteger state=[c isMCLCurrentlyEnabled:&e];if(e){if(error)*error=e;return nil;}
 if(value<20||value>100){if(error)*error=nativeError(2,@"Invalid current-limit response; refusing to write.");return nil;}
 return @{@"backend":@"PowerUI",@"available_limits":validated,@"selected_limit":@(value),@"enabled_state":@(state)};
}
BOOL nativeSetLimit(id<BATTNativeClient> c,NSInteger limit,NSError **error) {
 NSDictionary *before=nativeSnapshot(c,error);if(!before)return NO;
 if(limit<20||limit>100||![before[@"available_limits"] containsObject:@(limit)]){
  if(error)*error=nativeError(3,[NSString stringWithFormat:@"macOS does not accept %ld%% through this interface. Available: %@. No setting was changed.",(long)limit,before[@"available_limits"]]);return NO;
 }
 // Don't silently undo temporary charging overrides or enable a disabled feature.
 if(limit==100&&[before[@"selected_limit"] integerValue]==100&&[before[@"enabled_state"] unsignedIntegerValue]==0)return YES;
 if([before[@"enabled_state"] unsignedIntegerValue]!=1){if(error)*error=nativeError(4,@"Enable Charge Limit in System Settings first, and finish temporary charging overrides.");return NO;}
 if([before[@"selected_limit"] integerValue]==limit)return YES;
 NSError *writeError=nil;BOOL ok=[c setMCLLimit:(unsigned char)limit error:&writeError];
 NSError *readError=nil;NSDictionary *after=nativeSnapshot(c,&readError);
 if(ok&&!writeError&&after&&[after[@"selected_limit"] integerValue]==limit&&(limit==100?[after[@"enabled_state"] unsignedIntegerValue]<=1:[after[@"enabled_state"] unsignedIntegerValue]==1))return YES;
 // A rejected write may leave an experimental 50% policy intact. Do not try
 // the unsupported setter to "restore" an already unchanged value.
 if(after&&[after[@"selected_limit"] isEqual:before[@"selected_limit"]]&&[after[@"enabled_state"] isEqual:before[@"enabled_state"]]){
  if(error)*error=nativeError(5,[NSString stringWithFormat:@"Native write failed: %@. Previous limit remains unchanged.",writeError.localizedDescription?:@"setter failure"]);return NO;
 }
 if(![before[@"available_limits"] containsObject:before[@"selected_limit"]]){
  if(error)*error=nativeError(5,[NSString stringWithFormat:@"Write was not verified; this API cannot restore the previous experimental limit. Run sudo battctl hold %@ and restart normally, or sudo battctl restore to recover the original supported limit.",before[@"selected_limit"]]);return NO;
 }
 // Roll back even if the setter failed: it might have partially applied the request.
 NSError *restoreError=nil;BOOL restored=[c setMCLLimit:[before[@"selected_limit"] unsignedCharValue] error:&restoreError];
 NSError *verifyError=nil;NSDictionary *restoredState=nativeSnapshot(c,&verifyError);
 restored=restored&&!restoreError&&restoredState&&[restoredState[@"selected_limit"] isEqual:before[@"selected_limit"]]&&[restoredState[@"enabled_state"] isEqual:before[@"enabled_state"]];
 if(error)*error=nativeError(5,[NSString stringWithFormat:@"Native limit was not verified: %@. %@",writeError.localizedDescription?:readError.localizedDescription?:@"readback mismatch",restored?@"Previous limit restored.":@"Restoration was not verified; check System Settings immediately."]);
 return NO;
}
