#import <Foundation/Foundation.h>
#include "smc.h"
int main(void){ smcDiagnostics=true; if(smcOpen()){puts("SMC open denied; run with sudo");return 1;}const char *keys[]={"bfF0","bfD0","bfE0","CHIE","CH0I","CH0J","CHTE","CH0B","CH0C"};int sizes[]={1,4,4,1,1,1,4,1,1};for(int i=0;i<9;i++){uint8_t b[32];printf("%s: ",keys[i]);if(smcRead(keys[i],b,sizes[i]))puts("unavailable");else{for(int j=0;j<sizes[i];j++)printf("%02x ",b[j]);puts("");}}return 0;}
