#include <assert.h>
#include <stdio.h>
#include "../Sources/policy.h"
int main(void){
 for(int p=0;p<=100;p++)for(int lid=0;lid<2;lid++)for(int ac=0;ac<2;ac++)for(int sleep=0;sleep<2;sleep++)for(int pending=0;pending<2;pending++){
 bool d=shouldDischarge(pending,p,50,lid,ac,sleep);
 if(p<=50||!lid||!ac||sleep||!pending)assert(!d);
 else assert(d);
 }
 puts("1616 discharge safety cases passed");
}
