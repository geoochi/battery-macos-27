#pragma once
#import <Foundation/Foundation.h>
// IORegistry can encode negative battery current as an unsigned 64-bit NSNumber.
static NSDictionary *telemetry(NSDictionary *battery,NSDictionary *root) {
 NSMutableDictionary *out=[NSMutableDictionary dictionary];
 NSNumber *c=battery[@"CurrentCapacity"],*m=battery[@"MaxCapacity"];
 out[@"percent"]=(c&&m.doubleValue>0)?@(100.0*c.doubleValue/m.doubleValue):(id)NSNull.null;
 NSNumber *current=battery[@"InstantAmperage"]?:battery[@"Amperage"];
 NSNumber *voltage=battery[@"Voltage"];
 out[@"current_mA"]=current?@(current.longLongValue):(id)NSNull.null;
 out[@"battery_watts"]=(current&&voltage)?@((double)current.longLongValue*voltage.doubleValue/1000000.0):(id)NSNull.null;
 out[@"charging"]=battery[@"IsCharging"]?:NSNull.null;
 out[@"adapter_present"]=battery[@"AppleRawExternalConnected"]?:battery[@"ExternalConnected"]?:NSNull.null;
 id lid=root[@"AppleClamshellState"];
 out[@"lid"]=lid?([lid boolValue]?@"closed":@"open"):@"unknown";
 out[@"flow"]=!current?@"unknown":current.longLongValue<0?@"discharging":current.longLongValue>0?@"charging":@"idle";
 out[@"time"]=[[NSISO8601DateFormatter new] stringFromDate:NSDate.date];
 return out;
}
