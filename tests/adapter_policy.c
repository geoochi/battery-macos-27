#include <assert.h>
#include <stdio.h>
#include "../Sources/adapter_policy.h"
int main(void) {
 AdapterPolicy p;adapterPolicyInit(&p,60);
 assert(adapterPolicyStep(&p,70,true,false,0));
 assert(adapterPolicyStep(&p,60,true,false,100));
 assert(adapterPolicyStep(&p,56,true,false,200));
 assert(!adapterPolicyStep(&p,55,true,false,300));
 assert(!adapterPolicyStep(&p,59,true,false,400));
 assert(adapterPolicyStep(&p,60,true,false,500));
 assert(!adapterPolicyStep(&p,55,true,false,600));
 assert(p.band==6); // short full cycle widens the internal band
 assert(!adapterPolicyStep(&p,54,false,false,700));
 assert(p.cycleStart<0); // sleep/unplug must not count toward adaptation
 adapterPolicyInit(&p,60);
 assert(adapterPolicyStep(&p,70,true,true,0));
 assert(!adapterPolicyStep(&p,60,true,true,1)); // native ceiling can hold exactly
 assert(!adapterPolicyStep(&p,59,true,true,2));
 for(int target=20;target<=99;target++) {
  adapterPolicyInit(&p,target);
  for(int n=0;n<40;n++){
   adapterPolicyStep(&p,target,true,false,n*10);
   adapterPolicyStep(&p,adapterLower(&p),true,false,n*10+1);
   assert(p.band>=5&&p.band<=10&&adapterLower(&p)>=10);
  }
  assert(p.band==10);
  adapterPolicyStep(&p,target,true,false,1000);
  adapterPolicyStep(&p,adapterLower(&p),true,false,20000);
  assert(p.band==9);
  assert(!adapterPolicyStep(&p,-1,true,false,20001));
  assert(!adapterPolicyStep(&p,101,true,false,20002));
  assert(!adapterPolicyStep(&p,100,false,false,20003));
 }
 puts("Adapter hysteresis, native handoff, adaptive band and pause cases passed");
}
