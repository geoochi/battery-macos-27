#pragma once
#import <Foundation/Foundation.h>
BOOL parseHoldTarget(const char *text, NSInteger *target);
BOOL targetAlreadyApplied(NSInteger target, NSInteger savedPreference, NSDictionary *configuration, NSDictionary *live);
NSInteger targetFromConfiguration(NSDictionary *configuration, NSError **error);
BOOL persistTargetTransition(NSInteger target, NSInteger previous, NSDictionary *configuration,
    BOOL (^writePreference)(NSInteger, NSError **),
    BOOL (^writeConfiguration)(NSDictionary *, NSError **), NSError **error);
NSArray *parseBatteryLimits(NSString *text, NSError **error);
NSDictionary *limitAssessment(NSDictionary *native, NSArray *limits, NSDictionary *battery, NSInteger target);
// target=0 follows the saved requested target; older installations default to 50.
NSDictionary *effectiveLimitSnapshot(NSDictionary *battery, NSInteger target);
int persistentHold(NSInteger target);
int persistentRestore(void);
