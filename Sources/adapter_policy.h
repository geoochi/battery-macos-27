#pragma once
#include <stdbool.h>
// Adapter control cannot inhibit charging: it cycles below the requested ceiling.
// Adapt only after complete cycles, never in response to individual noisy samples.
typedef struct {
 int target, band;
 bool off;
 double cycleStart;
} AdapterPolicy;
static inline void adapterPolicyInit(AdapterPolicy *p, int target) {
 *p=(AdapterPolicy){.target=target,.band=5,.cycleStart=-1};
}
static inline int adapterLower(const AdapterPolicy *p) { return p->target-p->band; }
static inline bool adapterPolicyStep(AdapterPolicy *p, double percent, bool ready,
                                    bool nativeExact, double now) {
 if(!ready||percent<0||percent>100) { p->off=false;p->cycleStart=-1;return false; }
 if(nativeExact) {p->off=percent>p->target;p->cycleStart=-1;return p->off;}
 if(p->off&&percent<=adapterLower(p)) {
  p->off=false;
  if(p->cycleStart>=0) {
   double elapsed=now-p->cycleStart;
   if(elapsed>0&&elapsed<3600&&p->band<10)p->band++;
   else if(elapsed>10800&&p->band>5)p->band--;
  }
  p->cycleStart=now;
 } else if(!p->off&&percent>=p->target) p->off=true;
 return p->off;
}
