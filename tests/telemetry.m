#import <Foundation/Foundation.h>
#include <assert.h>
#include "../Sources/telemetry.h"
int main(void){@autoreleasepool{
 NSDictionary *sample=@{@"CurrentCapacity":@82,@"MaxCapacity":@100,@"InstantAmperage":@(UINT64_MAX-603),@"Voltage":@12200,@"IsCharging":@NO,@"ExternalConnected":@YES};
 NSDictionary*d=telemetry(sample,@{@"AppleClamshellState":@NO});
 assert([d[@"flow"] isEqual:@"discharging"]);assert([d[@"current_mA"] longLongValue]==-604);assert([d[@"battery_watts"] doubleValue]<-7.3);assert([d[@"lid"] isEqual:@"open"]);
 assert([NSJSONSerialization isValidJSONObject:d]);
 d=telemetry(@{@"CurrentCapacity":@5,@"MaxCapacity":@0},nil);
 assert(d[@"percent"]==NSNull.null);assert([d[@"flow"] isEqual:@"unknown"]);assert([d[@"lid"] isEqual:@"unknown"]);
 d=telemetry(@{@"Amperage":@0},@{@"AppleClamshellState":@YES});assert([d[@"flow"] isEqual:@"idle"]);assert([d[@"lid"] isEqual:@"closed"]);
 d=telemetry(@{@"Amperage":@200},nil);assert([d[@"flow"] isEqual:@"charging"]);
 puts("Telemetry: unsigned negative current, missing fields, zero capacity, lid and flow passed");return 0;
}}
