#import "adapter.h"
#import "native.h"
#import "persistent.h"
#include "adapter_policy.h"
#include "telemetry.h"
#include "smc.h"
#include <IOKit/IOMessage.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <mach/mach_time.h>
#include <mach-o/dyld.h>
#include <spawn.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <poll.h>
#include <signal.h>
#include <unistd.h>
extern char **environ;
static NSString *const directory=@"/Library/Application Support/battctl-adapter";
static NSString *const configPath=@"/Library/Application Support/battctl-adapter/config.plist";
static NSString *const statusPath=@"/Library/Application Support/battctl-adapter/status.json";
static NSString *const executable=@"/Library/Application Support/battctl-adapter/battctl";
static NSString *const launchPath=@"/Library/LaunchDaemons/com.geoochi.battctl.adapter.plist";
static NSString *const serviceName=@"system/com.geoochi.battctl.adapter";
static const char *lockPath="/var/run/com.geoochi.battctl.lock";
static volatile sig_atomic_t ending=0;
static BOOL sleeping=NO,resetAfterSleep=NO;
static io_connect_t powerConnection;
static int restoreAdapter(void) {uint8_t zero=0;return smcWrite("CHIE",&zero,1);}
static void stopAdapterSignal(int sig) {(void)sig;ending=1;}
static double continuousSeconds(void) {
 mach_timebase_info_data_t scale;mach_timebase_info(&scale);
 return (double)mach_continuous_time()*scale.numer/scale.denom/1e9;
}
static NSDictionary *properties(const char *name) {
 io_service_t s=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching(name));if(!s)return @{};
 CFMutableDictionaryRef p=NULL;IORegistryEntryCreateCFProperties(s,&p,kCFAllocatorDefault,0);IOObjectRelease(s);
 return p?CFBridgingRelease(p):@{};
}
static int command(NSString *path,NSArray *arguments,NSString **output) {
 NSTask *task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:path];task.arguments=arguments;
 NSPipe *pipe=[NSPipe pipe];task.standardOutput=pipe;task.standardError=pipe;
 if(![task launchAndReturnError:NULL])return -1;
 NSData *data=[pipe.fileHandleForReading readDataToEndOfFile];[task waitUntilExit];
 if(output)*output=[[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
 return task.terminationStatus;
}
static BOOL otherController(void) {
 NSString *output=nil;if(command(@"/bin/ps",@[@"-axo",@"comm="],&output))return YES;
 for(NSString *line in [output componentsSeparatedByString:@"\n"]){NSString *s=line.lowercaseString;
  if([s containsString:@"battopt"]||[s containsString:@"aldente"]||[s containsString:@"batfi"]||[s hasSuffix:@"/battery"]||[s hasSuffix:@"/batt"])return YES;
 }
 return NO;
}
static BOOL safeFile(NSString *path,BOOL folder) {
 struct stat s;if(lstat(path.fileSystemRepresentation,&s))return NO;
 return s.st_uid==0&&!(s.st_mode&0022)&&(folder?S_ISDIR(s.st_mode):S_ISREG(s.st_mode));
}
static BOOL prepareDirectory(void) {
 if(!safeFile(@"/Library",YES)||!safeFile(@"/Library/Application Support",YES))return NO;
 if(mkdir(directory.fileSystemRepresentation,0755)&&errno!=EEXIST)return NO;
 return safeFile(directory,YES);
}
static BOOL saveData(NSData *data,NSString *path) {
 return data&&[data writeToFile:path options:NSDataWritingAtomic error:NULL]&&chmod(path.fileSystemRepresentation,0644)==0;
}
static NSDictionary *configuration(void) {
 if(!safeFile(directory,YES)||!safeFile(configPath,NO))return nil;
 NSDictionary *d=[NSDictionary dictionaryWithContentsOfFile:configPath];
 id t=d[@"target"];
 if(![t isKindOfClass:NSNumber.class]||[t doubleValue]!=[t integerValue]||[t integerValue]<20||[t integerValue]>99||![d[@"version"] isEqual:@1])return nil;
 return d;
}
BOOL adapterConfigured(void) {return access(configPath.fileSystemRepresentation,F_OK)==0;}
NSDictionary *adapterAssessment(NSDictionary *battery) {
 if(!adapterConfigured())return nil;
 NSDictionary *config=configuration();
 NSData *data=safeFile(statusPath,NO)?[NSData dataWithContentsOfFile:statusPath]:nil;
 id parsed=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
 NSDictionary *state=[parsed isKindOfClass:NSDictionary.class]?parsed:@{};
 if([state[@"pid"] isKindOfClass:NSNumber.class]&&[state[@"pid"] intValue]>1&&kill([state[@"pid"] intValue],0)!=0&&errno==ESRCH){NSMutableDictionary *dead=[state mutableCopy];dead[@"running"]=@NO;state=dead;}
 return adapterAssessState(config,state,battery,NSDate.date.timeIntervalSince1970);
}
NSDictionary *adapterAssessState(NSDictionary *config,id input,NSDictionary *battery,double now) {
 NSDictionary *state=[input isKindOfClass:NSDictionary.class]?input:@{};
 NSNumber *target=config[@"target"];
 BOOL valid=[target isKindOfClass:NSNumber.class]&&target.integerValue>=20&&target.integerValue<=99&&target.doubleValue==target.integerValue;
 NSArray *phases=@[@"paused",@"native_holding",@"discharging_to_target",@"cycling_discharge",@"cycling_charge"];
 BOOL fields=[state[@"updated_at"] isKindOfClass:NSNumber.class]&&[state[@"running"] isKindOfClass:NSNumber.class]&&[state[@"lower_bound"] isKindOfClass:NSNumber.class]&&[phases containsObject:state[@"phase"]?:NSNull.null];
 double age=fields?now-[state[@"updated_at"] doubleValue]:-1;
 BOOL running=valid&&fields&&[state[@"target"] isEqual:target]&&age>=0&&age<15&&[state[@"running"] boolValue];
 NSMutableArray *errors=[NSMutableArray array];
 if(!running)[errors addObject:@"Adapter controller is not reporting a healthy heartbeat; run sudo battctl hold TARGET again or adapter-stop."];
 BOOL paused=[state[@"phase"] isEqual:@"paused"];
 if(paused)[errors addObject:@"Adapter control is paused; the existing native limit controls charging during sleep, lid closure or unplugging."];
 return @{@"backend":@"adapter",@"target":valid?target:(id)NSNull.null,@"target_source":@"adapter_configuration",
  @"battery":battery?:@{},@"controller_running":@(running),@"policy_active":@(running&&!paused),
  @"phase":running?state[@"phase"]:@"not_running",@"lower_bound":fields?state[@"lower_bound"]:(id)NSNull.null,
  @"native_limit":state[@"native_limit"]?:NSNull.null,@"adapter_cut":state[@"adapter_cut"]?:@NO,
  @"errors":errors};
}
static BOOL supportedHost(void) {
 NSString *model=nil,*build=nil;
 if(command(@"/usr/sbin/sysctl",@[@"-n",@"hw.model"],&model)||command(@"/usr/bin/sw_vers",@[@"-buildVersion"],&build)||![model isEqual:@"MacBookPro18,1"]||![build isEqual:@"26A428"]){fprintf(stderr,"Adapter mode is validated only on MacBookPro18,1 / 26A428.\n");return NO;}
 return YES;
}
static BOOL preflight(NSInteger target) {
 if(!supportedHost())return NO;
 NSDictionary *b=telemetry(properties("AppleSmartBattery"),properties("IOPMrootDomain"));
 if(![b[@"lid"] isEqual:@"open"]||![b[@"adapter_present"] isEqual:@YES]){fprintf(stderr,"Open the lid and connect the power adapter first.\n");return NO;}
 NSError *error=nil;NSDictionary *n=nativeSnapshot(nativeClient(&error),&error);
 if(!n||[n[@"selected_limit"] integerValue]<target){fprintf(stderr,"The native ceiling must be readable and at least the requested target; use hold-native for targets above the active native ceiling.\n");return NO;}
 if(smcOpen())return NO;uint8_t v=255;BOOL ok=!smcRead("CHIE",&v,1)&&v==0;IOServiceClose(smc);smc=0;
 if(!ok)fprintf(stderr,"CHIE is unavailable or already overridden; stop other battery controllers first.\n");
 return ok;
}
static int acquireLock(void) {
 int fd=open(lockPath,O_CREAT|O_RDWR|O_NOFOLLOW|O_CLOEXEC,0600);struct stat s;
 if(fd<0)return -1;
 if(fstat(fd,&s)||!S_ISREG(s.st_mode)||s.st_uid!=0||(s.st_mode&0022)||flock(fd,LOCK_EX|LOCK_NB)){close(fd);return -1;}
 return fd;
}
int adapterStop(void) {
 if(geteuid()!=0){fprintf(stderr,"Run with sudo.\n");return 1;}
 if(!adapterConfigured()&&access(launchPath.fileSystemRepresentation,F_OK)!=0)return 0;
 NSString *out=nil;
 if(command(@"/bin/launchctl",@[@"print",serviceName],NULL)==0&&command(@"/bin/launchctl",@[@"bootout",serviceName],&out)){
  fprintf(stderr,"Cannot stop adapter service: %s\n",out.UTF8String);return 1;
 }
 int lock=-1;for(int n=0;n<100&&lock<0;n++){lock=acquireLock();if(lock<0)usleep(100000);}
 if(lock<0){fprintf(stderr,"Controller/recovery still owns the lock; leaving recovery files intact.\n");return 1;}
 if(smcOpen()||restoreAdapter()){close(lock);fprintf(stderr,"Adapter restore failed; reconnect power and retry adapter-stop.\n");return 1;}
 IOServiceClose(smc);smc=0;
 BOOL cleaned=YES;
 for(NSString *path in @[configPath,statusPath,launchPath])if(unlink(path.fileSystemRepresentation)&&errno!=ENOENT)cleaned=NO;
 if(!cleaned){close(lock);fprintf(stderr,"Adapter restored but some service files could not be removed.\n");return 1;}
 close(lock);puts("Adapter controller stopped; power adapter restored. Native preferences unchanged.");return 0;
}
int adapterHold(NSInteger target) {
 if(geteuid()!=0){fprintf(stderr,"Run with sudo: battctl hold TARGET\n");return 1;}
 NSError *error=nil;NSDictionary *native=nativeSnapshot(nativeClient(&error),&error);
 if(!native||[native[@"selected_limit"] integerValue]<target){fprintf(stderr,"Requested target exceeds the readable native ceiling; use hold-native instead.\n");return 1;}
 if(adapterConfigured()||access(launchPath.fileSystemRepresentation,F_OK)==0){if(adapterStop())return 1;usleep(2000000);}
 if(!preflight(target)||!prepareDirectory())return 1;
 int lock=acquireLock();if(lock<0){fprintf(stderr,"Another battery controller owns the lock.\n");return 1;}
 uint32_t length=0;_NSGetExecutablePath(NULL,&length);char *path=calloc(length,1);
 if(!path||_NSGetExecutablePath(path,&length)){free(path);close(lock);return 1;}
 NSData *binary=[NSData dataWithContentsOfFile:@(path)];free(path);
 if(!saveData(binary,executable)||chmod(executable.fileSystemRepresentation,0755)){close(lock);return 1;}
 NSDictionary *config=@{@"version":@1,@"target":@(target)};
 NSData *configData=[NSPropertyListSerialization dataWithPropertyList:config format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
 if(!saveData(configData,configPath)){close(lock);return 1;}
 NSDictionary *plist=@{@"Label":@"com.geoochi.battctl.adapter",@"ProgramArguments":@[executable,@"adapter-daemon"],
  @"RunAtLoad":@YES,@"AbandonProcessGroup":@YES,@"KeepAlive":@{@"SuccessfulExit":@NO},@"ThrottleInterval":@30,
  @"StandardOutPath":[directory stringByAppendingPathComponent:@"controller.log"],
  @"StandardErrorPath":[directory stringByAppendingPathComponent:@"controller.log"]};
 NSData *plistData=[NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
 if(!safeFile(@"/Library/LaunchDaemons",YES)||!saveData(plistData,launchPath)){unlink(configPath.fileSystemRepresentation);close(lock);return 1;}
 close(lock);
 NSString *out=nil;
 if(command(@"/bin/launchctl",@[@"bootstrap",@"system",launchPath],&out)){
  fprintf(stderr,"Cannot start adapter service: %s\n",out.UTF8String);adapterStop();return 1;
 }
 for(int i=0;i<30;i++){
  NSDictionary *assessment=adapterAssessment(@{});
  if([assessment[@"controller_running"] boolValue]){
   printf("Adapter mode started: target=%ld%%, automatic range=%s..%ld%%; no reboot.\n",(long)target,[assessment[@"lower_bound"] description].UTF8String,(long)target);
   puts("Background control cycles the battery while the lid is open. Sleep/lid closure restores the adapter; the native ceiling then applies.\nCheck: battctl verify | Stop: sudo battctl adapter-stop");return 0;
  }
  usleep(200000);
 }
 fprintf(stderr,"Controller did not become healthy; restoring adapter. See controller.log in the adapter installation directory.\n");adapterStop();return 1;
}
static void powerEvent(void *ref,io_service_t service,natural_t type,void *arg) {
 (void)ref;(void)service;
 if(type==kIOMessageCanSystemSleep)IOAllowPowerChange(powerConnection,(long)arg);
 if(type==kIOMessageSystemWillSleep){sleeping=YES;resetAfterSleep=YES;if(restoreAdapter())ending=1;IOAllowPowerChange(powerConnection,(long)arg);}
 if(type==kIOMessageSystemHasPoweredOn){sleeping=NO;resetAfterSleep=YES;}
}
static BOOL registerPower(IONotificationPortRef *port,io_object_t *notifier) {
 powerConnection=IORegisterForSystemPower(NULL,port,powerEvent,notifier);
 if(!powerConnection)return NO;
 CFRunLoopAddSource(CFRunLoopGetCurrent(),IONotificationPortGetRunLoopSource(*port),kCFRunLoopCommonModes);return YES;
}
static void unregisterPower(IONotificationPortRef port,io_object_t notifier) {
 IODeregisterForSystemPower(&notifier);IOServiceClose(powerConnection);IONotificationPortDestroy(port);
}
static void signals(void) {
 signal(SIGTERM,stopAdapterSignal);signal(SIGINT,stopAdapterSignal);signal(SIGHUP,stopAdapterSignal);signal(SIGPIPE,SIG_IGN);
}
int adapterGuard(void) {
 struct stat input,lock,expected;
 if(geteuid()!=0||fstat(0,&input)||!S_ISFIFO(input.st_mode)||fstat(3,&lock)||lstat(lockPath,&expected)||lock.st_ino!=expected.st_ino||lock.st_dev!=expected.st_dev||lock.st_uid!=0||!S_ISREG(lock.st_mode))return 1;
 if(smcOpen())return 1;
 signals();IONotificationPortRef port=NULL;io_object_t notifier=0;
 if(!registerPower(&port,&notifier))return 1;
 if(write(1,"R",1)!=1)return 1;
 setsid(); // Keep recovery outside the controller process group.
 double heartbeat=continuousSeconds();
 while(!ending){
  struct pollfd p={.fd=0,.events=POLLIN|POLLHUP};
  if(poll(&p,1,0)>0){char bytes[128];ssize_t n=read(0,bytes,sizeof bytes);if(n<=0)break;heartbeat=continuousSeconds();}
  if(continuousSeconds()-heartbeat>10)break;
  CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.5,false);
 }
 // Keep the inherited controller lock until restoration succeeds. On persistent
 // failure retain this guard and retry, blocking a competing controller.
 while(restoreAdapter()){fprintf(stderr,"Watchdog: adapter recovery failed; retrying.\n");sleep(2);}
 unregisterPower(port,notifier);IOServiceClose(smc);return 0;
}
static int startGuard(int lock,pid_t *pid) {
 int heart[2],ready[2];if(pipe(heart))return -1;if(pipe(ready)){close(heart[0]);close(heart[1]);return -1;}
 int inherited=fcntl(lock,F_DUPFD_CLOEXEC,10);
 if(inherited<0){close(heart[0]);close(heart[1]);close(ready[0]);close(ready[1]);return -1;}
 posix_spawn_file_actions_t actions;posix_spawn_file_actions_init(&actions);
 posix_spawn_file_actions_adddup2(&actions,heart[0],0);
 posix_spawn_file_actions_adddup2(&actions,ready[1],1);
 posix_spawn_file_actions_adddup2(&actions,inherited,3);
 posix_spawnattr_t attr;posix_spawnattr_init(&attr);posix_spawnattr_setflags(&attr,POSIX_SPAWN_CLOEXEC_DEFAULT);
 char *argv[]={(char *)executable.fileSystemRepresentation,"adapter-guard",NULL};
 int result=posix_spawn(pid,executable.fileSystemRepresentation,&actions,&attr,argv,environ);
 posix_spawnattr_destroy(&attr);posix_spawn_file_actions_destroy(&actions);close(heart[0]);close(ready[1]);close(inherited);
 if(result){close(heart[1]);close(ready[0]);return -1;}
 struct pollfd poller={.fd=ready[0],.events=POLLIN};char byte=0;
 BOOL ok=poll(&poller,1,5000)>0&&read(ready[0],&byte,1)==1&&byte=='R';close(ready[0]);
 if(!ok){close(heart[1]);return -1;}
 return heart[1];
}
int adapterDaemon(void) {
 if(geteuid()!=0||!configuration())return 1;
 int lock=acquireLock();if(lock<0)return 1;
 signals();if(smcOpen()){close(lock);return 1;}
 if(restoreAdapter()){close(lock);return 1;}
 if(!supportedHost()){IOServiceClose(smc);close(lock);return 1;}
 IONotificationPortRef port=NULL;io_object_t notifier=0;
 if(!registerPower(&port,&notifier)){close(lock);return 1;}
 pid_t guard=0;int heart=startGuard(lock,&guard);
 if(heart<0){restoreAdapter();unregisterPower(port,notifier);close(lock);return 1;}
 AdapterPolicy policy;adapterPolicyInit(&policy,[configuration()[@"target"] intValue]);
 double nativeChecked=-1000;NSInteger nativeLimit=0;BOOL exact=NO,failed=NO,off=NO;
 NSDictionary *last=nil;NSString *lastPhase=nil;
 while(!ending){@autoreleasepool{
  if(write(heart,"H",1)!=1){failed=YES;break;}
  NSDictionary *config=configuration();if(!config){failed=YES;break;}
  if([config[@"target"] intValue]!=policy.target)adapterPolicyInit(&policy,[config[@"target"] intValue]);
  NSDictionary *battery=telemetry(properties("AppleSmartBattery"),properties("IOPMrootDomain"));
  NSNumber *percent=battery[@"percent"];
  if(![percent isKindOfClass:NSNumber.class]||percent.doubleValue<0||percent.doubleValue>100){failed=YES;break;}
  double now=continuousSeconds();
  if(now-nativeChecked>=60){
   if(otherController()){fprintf(stderr,"Another battery controller detected; restoring adapter.\n");failed=YES;break;}
   NSError *error=nil;NSDictionary *native=nativeSnapshot(nativeClient(&error),&error);
   if(!native||[native[@"selected_limit"] integerValue]<policy.target){failed=YES;break;}
   nativeLimit=[native[@"selected_limit"] integerValue];
   exact=nativeLimit==policy.target&&[effectiveLimitSnapshot(battery,policy.target)[@"policy_active"] boolValue];nativeChecked=now;
  }
  if(resetAfterSleep){off=NO;adapterPolicyStep(&policy,percent.doubleValue,false,exact,now);resetAfterSleep=NO;}
  BOOL open=[battery[@"lid"] isEqual:@"open"];
  // CHIE=8 masks BOTH connection flags. A false flag while we cut power is
  // expected and must never be mistaken for an unplug event.
  BOOL ready=!sleeping&&open&&(off||[battery[@"adapter_present"] isEqual:@YES]);
  off=adapterPolicyStep(&policy,percent.doubleValue,ready,exact,now);
  if(write(heart,"H",1)!=1){failed=YES;break;}
  uint8_t value=off?8:0;if(smcWrite("CHIE",&value,1)){failed=YES;break;}
  NSString *phase=!ready?@"paused":exact&&!off?@"native_holding":percent.doubleValue>policy.target?@"discharging_to_target":off?@"cycling_discharge":@"cycling_charge";
  last=@{@"target":@(policy.target),@"lower_bound":@(exact?policy.target:adapterLower(&policy)),@"phase":phase,
   @"running":@YES,@"updated_at":@(NSDate.date.timeIntervalSince1970),@"adapter_cut":@(off),@"native_limit":@(nativeLimit),@"pid":@(getpid())};
  if(!saveData([NSJSONSerialization dataWithJSONObject:last options:NSJSONWritingSortedKeys error:NULL],statusPath)){failed=YES;break;}
  if(![phase isEqual:lastPhase]){printf("target=%d lower=%d phase=%s battery=%.1f\n",policy.target,adapterLower(&policy),phase.UTF8String,percent.doubleValue);lastPhase=phase;}
  CFRunLoopRunInMode(kCFRunLoopDefaultMode,2,false);
 }}
 if(restoreAdapter())failed=YES;
 close(heart); // EOF triggers independent recovery, even if the parent is killed.
 if(last){NSMutableDictionary *final=[last mutableCopy];final[@"running"]=@NO;final[@"phase"]=failed?@"failed":@"stopped";saveData([NSJSONSerialization dataWithJSONObject:final options:0 error:NULL],statusPath);}
 unregisterPower(port,notifier);IOServiceClose(smc);close(lock);
 // The guard owns a duplicate lock until its final restoration is verified.
 return failed?1:0;
}
