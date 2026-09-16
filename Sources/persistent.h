#pragma once
#import <Foundation/Foundation.h>
NSArray *parseBatteryLimits(NSString *text, NSError **error);
NSDictionary *limitAssessment(NSDictionary *native, NSArray *limits, NSDictionary *battery, NSInteger target);
NSDictionary *effectiveLimitSnapshot(NSDictionary *battery, NSInteger target);
int persistentHold50(void);
int persistentRestore(void);
