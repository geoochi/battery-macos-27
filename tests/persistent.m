#import "../Sources/persistent.h"
#include <assert.h>
static NSDictionary *row(NSString *v,NSString *terminated){return @{@"chargeSocLimitReason":@"manualChargeLimit",@"chargeSocLimitSoc":v,@"Terminated":terminated};}
int main(void){@autoreleasepool{
 NSError *e=nil;
 NSArray *parsed=parseBatteryLimits(@"Battery level limits:\n( {Terminated=0; chargeSocLimitReason=manualChargeLimit; chargeSocLimitSoc=50;}, {Terminated=0; chargeSocLimitReason=manualChargeLimit; chargeSocLimitSoc=50;} )",&e);
 assert(parsed.count==2&&!e);
 NSDictionary *native=@{@"selected_limit":@50,@"enabled_state":@1};
 NSDictionary *battery=@{@"percent":@77,@"adapter_present":@YES,@"flow":@"discharging"};
 NSDictionary *d=limitAssessment(native,parsed,battery,50);
 assert([d[@"policy_active"] boolValue]&&[d[@"phase"] isEqual:@"discharging_to_target"]);
 // A saved/native selection alone is insufficient; all active manual entries must agree.
 assert(![limitAssessment(native,@[],battery,50)[@"policy_active"] boolValue]);
 // New OS builds use capability checks, with unchanged hardware scope. Pending
 // target 50 must not reject a coherent currently active 80% policy.
 NSMutableDictionary *live=[@{@"native":@{@"selected_limit":@80,@"enabled_state":@1,@"available_limits":@[@80,@85,@90,@95,@100]},
  @"effective_limits":@[row(@"80",@"0")],@"errors":@[],@"target":@50,@"policy_active":@NO} mutableCopy];
 e=nil;assert(validateStagingCompatibility(@"MacBookPro18,1",live,&e)&&!e);
 e=nil;assert(!validateStagingCompatibility(@"OtherModel",live,&e)&&e);
 live[@"errors"]=@[@"pmset unavailable"];e=nil;assert(!validateStagingCompatibility(@"MacBookPro18,1",live,&e)&&e);
 live[@"errors"]=@[];live[@"effective_limits"]=@[];e=nil;assert(!validateStagingCompatibility(@"MacBookPro18,1",live,&e)&&e);
 live[@"effective_limits"]=@[row(@"50",@"0")];e=nil;assert(!validateStagingCompatibility(@"MacBookPro18,1",live,&e)&&e);
 live[@"effective_limits"]=@[row(@"80",@"oops")];e=nil;assert(!validateStagingCompatibility(@"MacBookPro18,1",live,&e)&&e);
 live[@"effective_limits"]=@[row(@"80",@"0")];
 live[@"native"]=@{@"selected_limit":@80,@"enabled_state":@2,@"available_limits":@[@80]};
 e=nil;assert(!validateStagingCompatibility(@"MacBookPro18,1",live,&e)&&e);
 live[@"native"]=@{@"selected_limit":@80,@"enabled_state":@1,@"available_limits":@[]};
 e=nil;assert(!validateStagingCompatibility(@"MacBookPro18,1",live,&e)&&e);
 live[@"native"]=@{@"selected_limit":@50,@"enabled_state":@1,@"available_limits":@[@80,@85,@90,@95,@100]};
 live[@"effective_limits"]=@[row(@"50",@"0")];
 e=nil;assert(validateStagingCompatibility(@"MacBookPro18,1",live,&e)&&!e);
 assert(![limitAssessment(native,@[row(@"80",@"0")],battery,50)[@"policy_active"] boolValue]);
 assert(![limitAssessment(native,@[row(@"50",@"0"),row(@"80",@"0")],battery,50)[@"policy_active"] boolValue]);
 assert([limitAssessment(native,@[row(@"50",@"0"),row(@"80",@"1")],battery,50)[@"policy_active"] boolValue]);
 assert(![limitAssessment(native,@[row(@"50oops",@"0")],battery,50)[@"policy_active"] boolValue]);
 assert(![limitAssessment(native,@[row(@"50",@"oops")],battery,50)[@"policy_active"] boolValue]);
 assert(![limitAssessment(@{@"selected_limit":@80,@"enabled_state":@1},parsed,battery,50)[@"policy_active"] boolValue]);
 assert(![limitAssessment(@{@"selected_limit":@50,@"enabled_state":@2},parsed,battery,50)[@"policy_active"] boolValue]);
 assert(![limitAssessment(nil,parsed,battery,50)[@"policy_active"] boolValue]);
 assert([limitAssessment(native,parsed,@{@"percent":@50,@"adapter_present":@YES},50)[@"phase"] isEqual:@"near_target"]);
 assert([limitAssessment(native,parsed,@{@"percent":@47,@"adapter_present":@YES},50)[@"phase"] isEqual:@"below_target"]);
 assert([limitAssessment(native,parsed,@{@"percent":@50,@"adapter_present":@NO},50)[@"phase"] isEqual:@"power_disconnected"]);
 assert([limitAssessment(native,parsed,@{},50)[@"phase"] isEqual:@"telemetry_unknown"]);
 e=nil;assert(!parseBatteryLimits(@"Not supported",&e)&&e);
 e=nil;assert(!parseBatteryLimits(@"(50)",&e)&&e);
 e=nil;assert(!parseBatteryLimits(@"( { bad ",&e)&&e);
 e=nil;assert(parseBatteryLimits(@"()",&e).count==0&&!e);
 e=nil;assert(parseBatteryLimits(@"No battery level limits set\n",&e).count==0&&!e);
 assert(![limitAssessment(native,@[],battery,50)[@"policy_active"] boolValue]);
 puts("Persistent policy: real pmset format, stale/conflicting/malformed entries, overrides, telemetry, and phase semantics passed");
}}
