#import <Foundation/Foundation.h>
#include <assert.h>
#include "../Sources/adapter.h"
int main(void){@autoreleasepool{
 NSDictionary *config=@{@"target":@60};
 NSDictionary *state=@{@"target":@60,@"lower_bound":@55,@"running":@YES,@"updated_at":@100,@"phase":@"cycling_discharge"};
 assert([adapterAssessState(config,state,@{},101)[@"policy_active"] boolValue]);
 assert(![adapterAssessState(config,state,@{},116)[@"policy_active"] boolValue]);
 assert(![adapterAssessState(config,state,@{},99)[@"policy_active"] boolValue]);
 assert(![adapterAssessState(@{@"target":@65},state,@{},101)[@"policy_active"] boolValue]);
 NSMutableDictionary *paused=[state mutableCopy];paused[@"phase"]=@"paused";
 assert([adapterAssessState(config,paused,@{},101)[@"controller_running"] boolValue]);
 assert(![adapterAssessState(config,paused,@{},101)[@"policy_active"] boolValue]);
 for(id invalid in @[NSNull.null,@[],@{},@{@"phase":@3},@{@"updated_at":NSNull.null}])assert(![adapterAssessState(config,invalid,@{},101)[@"policy_active"] boolValue]);
 assert(![adapterAssessState(@{@"target":NSNull.null},state,@{},101)[@"policy_active"] boolValue]);
 puts("Adapter status: heartbeat expiry, pending target, pause and malformed state passed");
}}
