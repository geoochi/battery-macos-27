#pragma once
#import <Foundation/Foundation.h>
BOOL adapterConfigured(void);
NSDictionary *adapterAssessment(NSDictionary *battery);
NSDictionary *adapterAssessState(NSDictionary *config, id state, NSDictionary *battery, double now);
int adapterHold(NSInteger target);
int adapterStop(void);
int adapterDaemon(void);
int adapterGuard(void);
