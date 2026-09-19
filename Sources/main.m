#import <Foundation/Foundation.h>
#include <IOKit/IOMessage.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <signal.h>
#include <sys/file.h>
#include <unistd.h>
#include "smc.h"
#include "policy.h"
#include "telemetry.h"
#include "native.h"
#include "persistent.h"
#include "version.h"
#include "adapter.h"
static int target=50;static bool firmware,legacyPair,pending=true,sleeping=false,failed=false;
static const char *adapterKey;static uint8_t adapterOff;
static volatile sig_atomic_t stopping;
static io_connect_t powerPort;static IOPMAssertionID assertion=kIOPMNullAssertionID;
static NSDictionary *properties(const char *name) {
 io_service_t s=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching(name));if(!s)return nil;
 CFMutableDictionaryRef d=NULL;IOReturn r=IORegistryEntryCreateCFProperties(s,&d,kCFAllocatorDefault,0);IOObjectRelease(s);
 return r==0?CFBridgingRelease(d):nil;
}
static void printTelemetry(bool json){
 NSDictionary *d=telemetry(properties("AppleSmartBattery"),properties("IOPMrootDomain"));
 if(json){NSData*data=[NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingSortedKeys error:NULL];puts([[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding].UTF8String);return;}
 printf("%s battery=%s%% flow=%s power=%sW current=%smA lid=%s adapter=%s\n",[d[@"time"] UTF8String],[[d[@"percent"] description] UTF8String],[d[@"flow"] UTF8String],[[d[@"battery_watts"] description] UTF8String],[[d[@"current_mA"] description] UTF8String],[d[@"lid"] UTF8String],[[d[@"adapter_present"] description] UTF8String]);
}
static int battery(void){NSDictionary *d=properties("AppleSmartBattery");NSNumber *c=d[@"CurrentCapacity"],*m=d[@"MaxCapacity"];if(!c||!m||m.intValue<=0)return -1;int p=(int)(100.0*c.doubleValue/m.doubleValue);return p>=0&&p<=100?p:-1;}
static bool lidOpen(void){id v=properties("IOPMrootDomain")[@"AppleClamshellState"];return v && ![v boolValue];}
static bool plugged(void){NSDictionary*d=properties("AppleSmartBattery");id v=d[@"AppleRawExternalConnected"];return v?[v boolValue]:[d[@"ExternalConnected"] boolValue];}
static int byteWrite(const char*k,uint8_t v){return smcWrite(k,&v,1);}
static int adapter(bool on){return adapterKey?byteWrite(adapterKey,on?0:adapterOff):-1;}
static int charging(bool on){uint8_t b[4]={on?0:1,0,0,0};if(legacyPair){int a=byteWrite("CH0B",on?0:2);int c=byteWrite("CH0C",on?0:2);return a||c?-1:0;}return smcWrite("CHTE",b,4);}
static uint32_t decode(uint8_t*b){return b[0]|((uint32_t)b[1]<<8)|((uint32_t)b[2]<<16)|((uint32_t)b[3]<<24);}
static int limit(void){uint8_t a,u[4],l[4];if(smcRead("bfF0",&a,1)||smcRead("bfD0",u,4)||smcRead("bfE0",l,4))return -1;
 if(a==2&&decode(u)==(uint32_t)target&&decode(l)==(uint32_t)(target-2))return 0;
 uint8_t upper[4]={(uint8_t)target,0,0,0},lower[4]={(uint8_t)(target-2),0,0,0};
 if(byteWrite("bfF0",0)||smcWrite("bfD0",upper,4)||smcWrite("bfE0",lower,4)||byteWrite("bfF0",2)){
 // Best-effort rollback of all four stages, even if one restoration fails.
 int e1=byteWrite("bfF0",0),e2=smcWrite("bfD0",u,4),e3=smcWrite("bfE0",l,4),e4=byteWrite("bfF0",a);
 if(e1||e2||e3||e4)fprintf(stderr,"Firmware rollback failed; run reset with sudo.\n");return -1;}return 0;
}
static void releaseAssertion(void){if(assertion!=kIOPMNullAssertionID){IOPMAssertionRelease(assertion);assertion=kIOPMNullAssertionID;}}
static void emergency(void){if(adapter(true))fprintf(stderr,"ERROR: cannot restore adapter; reconnect power and run battctl reset with sudo.\n");releaseAssertion();}
static void step(void){@autoreleasepool{
 if(sleeping||failed)return;
 int p=battery();if(p<0){emergency();failed=true;return;}
 if(p<=target)pending=false;
 if(firmware){if(limit()){emergency();failed=true;return;}}
 else {static bool charge=false;if(p<=target-2)charge=true;if(p>=target)charge=false;if(charging(charge)){emergency();failed=true;return;}}
 bool discharge=shouldDischarge(pending,p,target,lidOpen(),plugged(),sleeping);
 if(adapter(!discharge)){emergency();failed=true;return;}
 if(discharge&&assertion==kIOPMNullAssertionID){if(IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep,kIOPMAssertionLevelOn,CFSTR("battctl discharge to target"),&assertion)!=kIOReturnSuccess){emergency();failed=true;return;}}
 if(!discharge)releaseAssertion();
 static int previous=-1;static bool wasDischarging=false;
 if(p!=previous||wasDischarging!=discharge){printf("battery=%d%% target=%d%% mode=%s phase=%s\n",p,target,firmware?"firmware":"legacy",discharge?"discharging":pending?"paused":"holding");previous=p;wasDischarging=discharge;}
}}
static void powerEvent(void *ref,io_service_t service,natural_t type,void *arg){(void)ref;(void)service;
 if(type==kIOMessageCanSystemSleep)IOAllowPowerChange(powerPort,(long)arg);
 if(type==kIOMessageSystemWillSleep){sleeping=true;emergency();if(!firmware&&charging(false)){fprintf(stderr,"Failed to disable charging before sleep\n");failed=true;}IOAllowPowerChange(powerPort,(long)arg);}
 if(type==kIOMessageSystemHasPoweredOn){sleeping=false;step();}
}
static void tick(CFRunLoopTimerRef timer,void*ctx){(void)timer;(void)ctx;step();if(stopping||failed)CFRunLoopStop(CFRunLoopGetCurrent());}
static void stopSignal(int s){(void)s;stopping=1;}
static bool conflict(void){NSTask*t=[NSTask new];t.executableURL=[NSURL fileURLWithPath:@"/bin/ps"];t.arguments=@[@"-axo",@"pid=,comm="];NSPipe*p=[NSPipe pipe];t.standardOutput=p;NSError*e=nil;if(![t launchAndReturnError:&e])return true;NSData*d=[p.fileHandleForReading readDataToEndOfFile];[t waitUntilExit];NSString*s=[[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding];
 for(NSString*line in [s componentsSeparatedByString:@"\n"]){NSString*l=line.lowercaseString;if([l containsString:@"battopt"]||[l containsString:@"aldente"]||[l containsString:@"batfi"]||[l hasSuffix:@"/battery"]||[l hasSuffix:@"/batt"]){fprintf(stderr,"Conflicting battery controller: %s\n",line.UTF8String);return true;}}return t.terminationStatus!=0;
}
static bool detect(void){uint8_t b[4];firmware=!smcRead("bfF0",b,1)&&!smcRead("bfD0",b,4)&&!smcRead("bfE0",b,4);legacyPair=!smcRead("CH0B",b,1)&&!smcRead("CH0C",b,1);bool legacy=legacyPair||!smcRead("CHTE",b,4);
 const char*keys[]={"CH0I","CH0J","CHIE"};for(int i=0;i<3;i++)if(!smcRead(keys[i],b,1)){adapterKey=keys[i];adapterOff=i==2?8:1;break;}
 printf("control=%s adapter=%s\n",firmware?"firmware":legacy?"legacy":"unavailable (or permission denied)",adapterKey?adapterKey:"unavailable");return (firmware||legacy)&&adapterKey;
}
int main(int argc,const char**argv){@autoreleasepool{
 setbuf(stdout,NULL);
 if(argc==2&&(!strcmp(argv[1],"--version")||!strcmp(argv[1],"version"))){puts("battctl " BATTCTL_VERSION);return 0;}
 if(argc<2||!strcmp(argv[1],"help")||!strcmp(argv[1],"--help")){puts("battctl hold TARGET | hold-native TARGET | adapter-stop | verify [TARGET] [--json] | verify-native [TARGET] [--json] | monitor [TARGET] [--json] | restore\nbattctl status [--json] | watch [--json] | native-limit [80..100] | doctor\nhold: start background adapter control, integer 20..99, sudo, lid open and AC connected; no reboot.\nhold-native: stage a native target; a manual reboot may be required.\nadapter-stop: stop background control and restore adapter power (sudo).\nverify/monitor: follow adapter control when configured, otherwise the saved native target (legacy default 50), or check an explicit TARGET; monitor every 30 seconds.\nverify-native: inspect only the native policy, even during adapter control.\nrestore: stop adapter control and restore the original native limit (sudo).\nLegacy SMC only: run [50] | reset (sudo; unavailable on current firmware).");return 0;}
 if(!strcmp(argv[1],"adapter-daemon")&&argc==2)return adapterDaemon();
 if(!strcmp(argv[1],"adapter-guard")&&argc==2)return adapterGuard();
 if(!strcmp(argv[1],"adapter-stop")&&argc==2)return adapterStop();
 if(!strcmp(argv[1],"hold")||!strcmp(argv[1],"hold-native")){
 NSInteger requested=0;
 if(argc!=3||!parseHoldTarget(argv[2],&requested)){fprintf(stderr,"Usage: battctl hold TARGET (integer 20..99; use native-limit 100 for full charge)\n");return 2;}
 if(conflict())return 1;
 if(!strcmp(argv[1],"hold"))return adapterHold(requested);
 if(adapterStop())return 1;
 return persistentHold(requested);
 }
 if(!strcmp(argv[1],"restore")){
 if(argc!=2)return 2;if(conflict())return 1;
 if(adapterStop())return 1;return persistentRestore();
 }
 if(!strcmp(argv[1],"verify")||!strcmp(argv[1],"verify-native")||!strcmp(argv[1],"monitor")){
 NSInteger requested=0;BOOL json=NO;
 for(int i=2;i<argc;i++){
  if(!strcmp(argv[i],"--json")&&!json){json=YES;continue;}
  if(requested==0&&parseHoldTarget(argv[i],&requested))continue;
  fprintf(stderr,"Expected verify/monitor [TARGET] [--json], TARGET integer 20..99\n");return 2;
 }
 BOOL monitor=!strcmp(argv[1],"monitor");signal(SIGINT,stopSignal);signal(SIGTERM,stopSignal);
 NSTimeInterval previous=0;int result=0;
 do{@autoreleasepool{
  NSDictionary *batterySample=telemetry(properties("AppleSmartBattery"),properties("IOPMrootDomain"));
  NSDictionary *adapterReport=!strcmp(argv[1],"verify-native")?nil:adapterAssessment(batterySample);
  NSMutableDictionary *d=[(adapterReport?:effectiveLimitSnapshot(batterySample,requested)) mutableCopy];
  if(adapterReport&&requested&&(![d[@"target"] isKindOfClass:NSNumber.class]||[d[@"target"] integerValue]!=requested)){d[@"policy_active"]=@NO;d[@"errors"]=[d[@"errors"] arrayByAddingObject:@"Requested target differs from the running adapter controller."];}

  NSTimeInterval now=NSDate.date.timeIntervalSince1970;
  d[@"sample_gap_seconds"]=previous?@(now-previous):(id)NSNull.null;previous=now;
  result=[d[@"policy_active"] boolValue]?0:1;
  if(json){NSData *data=[NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingSortedKeys error:NULL];puts([[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding].UTF8String);}
  else{NSDictionary *b=d[@"battery"];printf("%s target=%s%% policy=%s phase=%s battery=%s%% flow=%s power=%sW lid=%s adapter=%s\n",[b[@"time"] UTF8String],[[d[@"target"] description] UTF8String],result?"NOT VERIFIED":"active",[d[@"phase"] UTF8String],[[b[@"percent"] description] UTF8String],[b[@"flow"] UTF8String],[[b[@"battery_watts"] description] UTF8String],[b[@"lid"] UTF8String],[[b[@"adapter_present"] description] UTF8String]);if(d[@"lower_bound"])printf("backend=adapter automatic_range=%s..%s%% native_limit=%s%%\n",[d[@"lower_bound"] description].UTF8String,[d[@"target"] description].UTF8String,[d[@"native_limit"] description].UTF8String);for(NSString *e in d[@"errors"])fprintf(stderr,"%s\n",e.UTF8String);}
  if(!monitor)break;for(int i=0;i<30&&!stopping;i++)sleep(1);
 }}while(!stopping);return monitor?0:result;
 }
 if(!strcmp(argv[1],"doctor")){
 if(argc!=2)return 2;
 NSDictionary *sample=telemetry(properties("AppleSmartBattery"),properties("IOPMrootDomain"));
 NSDictionary *d=adapterAssessment(sample)?:effectiveLimitSnapshot(sample,0);
 NSData *data=[NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:NULL];puts([[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
 BOOL c=conflict();
 if(adapterConfigured())return c||![d[@"policy_active"] boolValue]?1:0;
 if([d[@"policy_active"] boolValue]){printf("Native %s%% policy is active; SMC access is not required. Verify actual holding and sleep retention on your device.\n",[d[@"target"] description].UTF8String);return c?1:0;}
 // Fall through to legacy diagnostics only when the requested native policy is not active.
 }
 if(!strcmp(argv[1],"native-limit")){
 if(argc>3){fprintf(stderr,"Usage: battctl native-limit [percent]\n");return 2;}
 NSError*e=nil;id<BATTNativeClient> c=nativeClient(&e);if(!c){fprintf(stderr,"%s\n",e.localizedDescription.UTF8String);return 1;}
 if(argc==3){char*end;long n=strtol(argv[2],&end,10);if(!argv[2][0]||*end||n<20||n>100){fprintf(stderr,"Invalid percentage\n");return 2;}
 if(conflict())return 1;
 if(adapterConfigured()){fprintf(stderr,"Stop adapter control first: sudo battctl adapter-stop\n");return 1;}
 if(!nativeSetLimit(c,n,&e)){fprintf(stderr,"%s\n",e.localizedDescription.UTF8String);return 1;}}
 NSDictionary*d=nativeSnapshot(c,&e);if(!d){fprintf(stderr,"%s\n",e.localizedDescription.UTF8String);return 1;}
 NSData*data=[NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:NULL];puts([[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding].UTF8String);return 0;
 }
 if(!strcmp(argv[1],"status")||!strcmp(argv[1],"watch")){
 if(argc>3||(argc==3&&strcmp(argv[2],"--json"))){fprintf(stderr,"Expected status/watch [--json]\n");return 2;}
 bool watch=!strcmp(argv[1],"watch");signal(SIGINT,stopSignal);signal(SIGTERM,stopSignal);
 do{@autoreleasepool{printTelemetry(argc==3);}if(!watch)break;for(int i=0;i<5&&!stopping;i++)sleep(1);}while(!stopping);
 return 0;
 }
 if(adapterConfigured()&&(!strcmp(argv[1],"run")||!strcmp(argv[1],"reset"))){fprintf(stderr,"Stop adapter control first.\n");return 1;}
 const char*cmd=argv[1];bool readOnly=!strcmp(cmd,"status")||!strcmp(cmd,"doctor");
 if(!readOnly&&strcmp(cmd,"run")&&strcmp(cmd,"reset")){fprintf(stderr,"Unknown command\n");return 2;}
 if(argc>3||(argc==3&&strcmp(cmd,"run"))){fprintf(stderr,"Invalid arguments\n");return 2;}
 if(argc==3){char*end;long n=strtol(argv[2],&end,10);if(!argv[2][0]||*end||n<20||n>90){fprintf(stderr,"Target must be an integer from 20 to 90\n");return 2;}target=(int)n;}
 printf("battery=%d%% lid=%s adapterPresent=%s\n",battery(),lidOpen()?"open":"closed/unknown",plugged()?"yes":"no");
 if(smcOpen()){fprintf(stderr,"Cannot open AppleSMC; try sudo\n");return 1;}
 if(!strcmp(cmd,"doctor")){
 NSError*e=nil;NSDictionary*d=nativeSnapshot(nativeClient(&e),&e);
 if(d)printf("native=PowerUI selected=%s%% setter_values=%s; use hold-native TARGET for experimental reboot staging\n",[d[@"selected_limit"] description].UTF8String,[d[@"available_limits"] description].UTF8String);
 else fprintf(stderr,"Native API: %s\n",e.localizedDescription.UTF8String);
 }
 smcDiagnostics=!strcmp(cmd,"doctor");
 bool supported=detect();smcDiagnostics=false;
 if(!supported&&smcPermissionDenied)fprintf(stderr,"SMC denied charge-control access (kIOReturnNotPrivileged, 0xe00002c1), effective UID=%u. %s\n",geteuid(),geteuid()==0?"Legacy SMC control is denied even as root; use hold-native/verify-native for the native preference backend.":"Use sudo doctor to distinguish user permissions from system restrictions.");
 if(readOnly){bool c=conflict();if(firmware){uint8_t a,u[4],l[4];if(!smcRead("bfF0",&a,1)&&!smcRead("bfD0",u,4)&&!smcRead("bfE0",l,4))printf("firmware active=%u lower=%u upper=%u\n",a,decode(l),decode(u));}IOServiceClose(smc);return !strcmp(cmd,"doctor")&&(!supported||c)?1:0;}
 if(geteuid()!=0){fprintf(stderr,"Administrator access required. Run with sudo.\n");return 1;}
 int lock=open("/var/run/com.geoochi.battctl.lock",O_CREAT|O_RDWR|O_NOFOLLOW,0600);if(lock<0||flock(lock,LOCK_EX|LOCK_NB)){fprintf(stderr,"Another battctl is running or lock failed\n");return 1;}
 if(conflict())return 1;
 if(!supported){fprintf(stderr,"No supported charge controller; refusing to discharge.\n");return 1;}
 if(!strcmp(cmd,"reset")){int a=adapter(true);int b=firmware?byteWrite("bfF0",0):charging(true);return a||b?1:0;}
 IONotificationPortRef port;io_object_t notifier;
 powerPort=IORegisterForSystemPower(NULL,&port,powerEvent,&notifier);if(!powerPort){fprintf(stderr,"Cannot register sleep hook\n");return 1;}
 CFRunLoopAddSource(CFRunLoopGetCurrent(),IONotificationPortGetRunLoopSource(port),kCFRunLoopCommonModes);
 signal(SIGINT,stopSignal);signal(SIGTERM,stopSignal);signal(SIGHUP,stopSignal);
 CFRunLoopTimerRef timer=CFRunLoopTimerCreate(NULL,CFAbsoluteTimeGetCurrent(),2,0,0,tick,NULL);CFRunLoopAddTimer(CFRunLoopGetCurrent(),timer,kCFRunLoopCommonModes);
 CFRunLoopRun();emergency();if(!firmware&&charging(false))failed=true;
 CFRunLoopTimerInvalidate(timer);CFRelease(timer);IODeregisterForSystemPower(&notifier);IOServiceClose(powerPort);IONotificationPortDestroy(port);IOServiceClose(smc);close(lock);return failed?1:0;
}}
