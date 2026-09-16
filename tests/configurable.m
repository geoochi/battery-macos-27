#import "../Sources/persistent.h"
#include <assert.h>
@interface MemoryStore : NSObject
@property NSInteger preference;
@property NSDictionary *configuration;
@property NSInteger preferenceWrites;
@property NSInteger configurationWrites;
@property BOOL failPreferenceOnce;
@property BOOL failConfigurationOnce;
@property BOOL failRollback;
@end
@implementation MemoryStore
- (BOOL)writePreference:(NSInteger)value error:(NSError **)error {
 self.preferenceWrites++;
 if(self.failRollback&&self.preferenceWrites>1){
  *error=[NSError errorWithDomain:@"test" code:3 userInfo:@{NSLocalizedDescriptionKey:@"rollback failed"}];return NO;
 }
 self.preference=value; // A failed writer can still have partially applied its change.
 if(self.failPreferenceOnce){self.failPreferenceOnce=NO;*error=[NSError errorWithDomain:@"test" code:1 userInfo:nil];return NO;}
 return YES;
}
- (BOOL)writeConfiguration:(NSDictionary *)value error:(NSError **)error {
 self.configurationWrites++;self.configuration=value;
 if(self.failConfigurationOnce){self.failConfigurationOnce=NO;*error=[NSError errorWithDomain:@"test" code:2 userInfo:nil];return NO;}
 return YES;
}
@end
static BOOL transition(MemoryStore *store,NSInteger target,NSError **error){
 return persistTargetTransition(target,store.preference,store.configuration,
  ^BOOL(NSInteger value,NSError **e){return [store writePreference:value error:e];},
  ^BOOL(NSDictionary *value,NSError **e){return [store writeConfiguration:value error:e];},error);
}
static MemoryStore *memory(NSInteger preference,NSDictionary *configuration){
 MemoryStore *store=[MemoryStore new];store.preference=preference;store.configuration=configuration;return store;
}
int main(void){@autoreleasepool{
 NSInteger target=0;
 for(NSInteger n=20;n<=99;n++){assert(parseHoldTarget([@(n) description].UTF8String,&target));assert(target==n);}
 const char *invalid[]={"","0","19","100","101","-70","+70","70.5","70oops"," 70","70 ","9999999999999999999999999999999999"};
 for(unsigned i=0;i<sizeof(invalid)/sizeof(invalid[0]);i++)assert(!parseHoldTarget(invalid[i],&target));
 NSError *e=nil;assert(targetFromConfiguration(nil,&e)==50&&!e);
 assert(targetFromConfiguration(@{@"target":@70},&e)==70);
 for(id value in @[@"70",@19,@100,@70.5,NSNull.null]){
  e=nil;assert(targetFromConfiguration(@{@"target":value},&e)==0&&e);
 }
 e=nil;assert(targetFromConfiguration(@{},&e)==0&&e);
 NSDictionary *active50=@{@"target":@50,@"policy_active":@YES};
 assert(targetAlreadyApplied(50,50,nil,active50));
 // Interrupted staging saved 70 but left old intent and active selection at 50.
 // A request to keep/cancel back to 50 must repair the saved preference, not no-op.
 assert(!targetAlreadyApplied(50,70,nil,active50));
 assert(!targetAlreadyApplied(50,50,@{@"target":@70},active50));
 assert(!targetAlreadyApplied(70,70,@{@"target":@70},active50));
 MemoryStore *s=memory(50,nil);e=nil;
 assert(transition(s,70,&e));assert(s.preference==70&&[s.configuration[@"target"] integerValue]==70);
 // A second request replaces the saved pending target even before a reboot.
 assert(transition(s,60,&e));assert(s.preference==60&&[s.configuration[@"target"] integerValue]==60);
 // Cancel a pending 70% request by restoring the desired 50% target.
 s=memory(70,@{@"target":@70});e=nil;assert(transition(s,50,&e));assert(s.preference==50&&[s.configuration[@"target"] integerValue]==50);
 // Failed preference write rolls back to 50, not the original supported 80.
 s=memory(50,@{@"target":@50});s.failPreferenceOnce=YES;e=nil;
 assert(!transition(s,70,&e));assert(s.preference==50&&[s.configuration[@"target"] integerValue]==50&&s.configurationWrites==0);
 // Failed metadata write restores both values, including absence on legacy installs.
 s=memory(50,nil);s.failConfigurationOnce=YES;e=nil;
 assert(!transition(s,70,&e));assert(s.preference==50&&s.configuration==nil);
 s=memory(70,@{@"target":@70});s.failConfigurationOnce=YES;e=nil;
 assert(!transition(s,60,&e));assert(s.preference==70&&[s.configuration[@"target"] integerValue]==70);
 s=memory(50,nil);s.failConfigurationOnce=YES;s.failRollback=YES;e=nil;
 assert(!transition(s,70,&e));assert([e.localizedDescription containsString:@"rollback failed"]);
 s=memory(50,nil);e=nil;assert(!transition(s,100,&e));assert(s.preferenceWrites==0&&s.configurationWrites==0);
 NSArray *limits=@[@{@"Terminated":@"0",@"chargeSocLimitReason":@"manualChargeLimit",@"chargeSocLimitSoc":@"70"}];
 NSDictionary *native=@{@"selected_limit":@70,@"enabled_state":@1};
 NSDictionary *battery=@{@"percent":@70,@"adapter_present":@YES,@"flow":@"idle"};
 NSDictionary *d=limitAssessment(native,limits,battery,70);
 assert([d[@"policy_active"] boolValue]&&[d[@"phase"] isEqual:@"near_target"]);
 assert(![limitAssessment(native,limits,battery,50)[@"policy_active"] boolValue]);
 assert(![limitAssessment(@{@"selected_limit":@50,@"enabled_state":@1},limits,battery,70)[@"policy_active"] boolValue]);
 d=limitAssessment(native,limits,@{@"percent":@50,@"adapter_present":@YES},70);
 assert([d[@"phase"] isEqual:@"below_target"]);
 puts("Configurable targets: range, saved intent, pending-target replacement, cancellation, partial writes, rollback and 70% assessment passed");
}}
