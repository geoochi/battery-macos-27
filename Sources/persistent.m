#import "persistent.h"
#import "native.h"
#include <sys/stat.h>
#include <sys/file.h>
#include <unistd.h>
#include <errno.h>
static NSString *const domain=@"com.apple.smartcharging.topoffprotection";
// Keep the original reboot-test backup; never replace it with the experimental value.
static NSString *const state=@"/Library/Application Support/battctl-reboot-test";
static NSString *const configurationPath=@"/Library/Preferences/com.geoochi.battctl.plist";
static NSDictionary *readTargetConfiguration(NSError **error);
static BOOL writeTargetConfiguration(NSDictionary *configuration, NSError **error);
static NSError *failure(NSString *s){return [NSError errorWithDomain:@"battctl.persistent" code:1 userInfo:@{NSLocalizedDescriptionKey:s}];}
BOOL parseHoldTarget(const char *text, NSInteger *target) {
 if(!text||!*text)return NO;
 NSInteger value=0;
 for(const char *c=text;*c;c++){
  if(*c<'0'||*c>'9')return NO;
  value=value*10+(*c-'0');if(value>99)return NO;
 }
 if(value<20)return NO;
 if(target)*target=value;return YES;
}
NSInteger targetFromConfiguration(NSDictionary *configuration, NSError **error) {
 if(!configuration)return 50; // v0.1.0 compatibility, not inferred from active policy.
 id value=[configuration isKindOfClass:NSDictionary.class]?configuration[@"target"]:nil;
 NSInteger target=0;
 if(![value isKindOfClass:NSNumber.class]||!parseHoldTarget([[value description] UTF8String],&target)){
  if(error)*error=failure(@"Invalid saved target configuration; specify verify TARGET to inspect an explicit target");return 0;
 }
 return target;
}
BOOL targetAlreadyApplied(NSInteger target,NSInteger savedPreference,NSDictionary *configuration,NSDictionary *live){
 return savedPreference==target&&targetFromConfiguration(configuration,NULL)==target&&[live[@"target"] integerValue]==target&&[live[@"policy_active"] boolValue];
}
BOOL persistTargetTransition(NSInteger target, NSInteger previous, NSDictionary *configuration,
 BOOL (^writePreference)(NSInteger,NSError **), BOOL (^writeConfiguration)(NSDictionary *,NSError **), NSError **error) {
 if(target<20||target>99||previous<20||previous>100){if(error)*error=failure(@"Invalid preference transition");return NO;}
 NSError *e=nil;
 BOOL saved=writePreference(target,&e);
 BOOL configAttempted=NO;
 if(saved){configAttempted=YES;saved=writeConfiguration(@{@"target":@(target)},&e);}
 if(saved)return YES;
 // Restore the immediately previous saved preference, never the original backup.
 // A failed writer can have partially applied a change, so verify both rollbacks.
 NSError *prefError=nil,*configError=nil;
 BOOL restoredPreference=writePreference(previous,&prefError);
 BOOL restoredConfiguration=!configAttempted||writeConfiguration(configuration,&configError);
 if(error)*error=failure([NSString stringWithFormat:@"Target update failed: %@. Previous saved preference: %@. Previous requested target: %@. Original-limit backup retained.",
  e.localizedDescription?:@"write failed",restoredPreference?@"restored":(prefError.localizedDescription?:@"RESTORATION NOT VERIFIED"),
  restoredConfiguration?@"restored":(configError.localizedDescription?:@"RESTORATION NOT VERIFIED")]);
 return NO;
}
static NSString *command(NSString *path,NSArray *args,NSError **error){
 NSTask *task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:path];task.arguments=args;
 NSPipe *pipe=[NSPipe pipe];task.standardOutput=pipe;task.standardError=pipe;
 if(![task launchAndReturnError:error])return nil;
 NSData *data=[pipe.fileHandleForReading readDataToEndOfFile];[task waitUntilExit];
 NSString *out=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
 if(task.terminationStatus||!out){if(error)*error=failure(out?:@"Invalid command output");return nil;}
 return [out stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}
NSArray *parseBatteryLimits(NSString *text,NSError **error){
 if([[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] isEqual:@"No battery level limits set"])return @[];
 NSRange start=[text rangeOfString:@"("],end=[text rangeOfString:@")" options:NSBackwardsSearch];
 if(start.location==NSNotFound||end.location==NSNotFound||end.location<start.location){if(error)*error=failure(@"Cannot parse pmset battery limits");return nil;}
 NSData *data=[[text substringWithRange:NSMakeRange(start.location,NSMaxRange(end)-start.location)] dataUsingEncoding:NSUTF8StringEncoding];
 id rows=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:error];
 if(![rows isKindOfClass:NSArray.class]){if(error)*error=failure(@"Battery limits are not an array");return nil;}
 for(id row in rows)if(![row isKindOfClass:NSDictionary.class]){if(error)*error=failure(@"Malformed battery limit entry");return nil;}
 return rows;
}
static BOOL exactInteger(id value,NSInteger expected){
 if(![value isKindOfClass:NSNumber.class]&&![value isKindOfClass:NSString.class])return NO;
 NSScanner *scan=[NSScanner scannerWithString:[value description]];NSInteger number;
 return [scan scanInteger:&number]&&scan.isAtEnd&&number==expected;
}
NSDictionary *limitAssessment(NSDictionary *native,NSArray *limits,NSDictionary *battery,NSInteger target){
 BOOL active=native&&exactInteger(native[@"selected_limit"],target)&&exactInteger(native[@"enabled_state"],1);
 NSUInteger matches=0;BOOL mismatch=NO;
 for(NSDictionary *row in limits){
  if(![row[@"chargeSocLimitReason"] isEqual:@"manualChargeLimit"])continue;
  if(exactInteger(row[@"Terminated"],1))continue;
  if(exactInteger(row[@"Terminated"],0)&&exactInteger(row[@"chargeSocLimitSoc"],target))matches++;else mismatch=YES;
 }
 active=active&&matches>0&&!mismatch;
 NSString *phase=@"policy_not_verified";
 if(active){
  if([battery[@"adapter_present"] isEqual:@NO])phase=@"power_disconnected";
  else if(![battery[@"adapter_present"] isEqual:@YES]||![battery[@"percent"] isKindOfClass:NSNumber.class])phase=@"telemetry_unknown";
  else if([battery[@"percent"] doubleValue]>target+1)phase=[battery[@"flow"] isEqual:@"discharging"]?@"discharging_to_target":@"above_target";
  else if([battery[@"percent"] doubleValue]<target-1)phase=@"below_target";
  else phase=@"near_target"; // A single sample cannot establish sustained holding.
 }
 return @{@"target":@(target),@"policy_active":@(active),@"phase":phase,@"manual_limit_entries":@(matches)};
}
NSDictionary *effectiveLimitSnapshot(NSDictionary *battery,NSInteger target){
 NSError *configurationError=nil;NSString *source=@"argument";
 if(target==0){
  NSDictionary *configuration=readTargetConfiguration(&configurationError);
  if(!configurationError)target=targetFromConfiguration(configuration,&configurationError);
  source=configuration?@"configuration":@"legacy_default";
 }
 NSError *e=nil;NSDictionary *native=nativeSnapshot(nativeClient(&e),&e);
 NSMutableArray *errors=[NSMutableArray array];if(configurationError)[errors addObject:configurationError.localizedDescription];if(!native)[errors addObject:e.localizedDescription?:@"Native API unavailable"];
 e=nil;NSString *raw=command(@"/usr/bin/pmset",@[@"-g",@"battlimit"],&e);
 NSArray *limits=raw?parseBatteryLimits(raw,&e):nil;if(!limits)[errors addObject:e.localizedDescription?:@"Effective limits unavailable"];
 NSMutableDictionary *out=[limitAssessment(native,limits,battery,target) mutableCopy];
 out[@"target_source"]=source;
 if(configurationError){out[@"target"]=NSNull.null;out[@"policy_active"]=@NO;out[@"phase"]=@"configuration_error";}
 out[@"battery"]=battery?:@{};out[@"native"]=native?:@{};out[@"effective_limits"]=limits?:@[];out[@"errors"]=errors;
 return out;
}
static NSString *readPreference(NSString *key,NSError **e){return command(@"/usr/bin/defaults",@[@"read",domain,key],e);}
static BOOL saveLimit(NSInteger n,NSError **e){
 if(!command(@"/usr/bin/defaults",@[@"write",domain,@"mclLimitValue",@"-int",[@(n) description]],e))return NO;
 if(!exactInteger(readPreference(@"mclLimitValue",e),n)){if(e&&!*e)*e=failure(@"Saved preference readback mismatch");return NO;}return YES;
}
static int lockPreferences(void){
 if(geteuid()!=0){fprintf(stderr,"Run this command with sudo to save or restore the system preference.\n");return -1;}
 int fd=open("/var/run/com.geoochi.battctl.preference.lock",O_CREAT|O_RDWR|O_NOFOLLOW,0600);
 if(fd<0||flock(fd,LOCK_EX|LOCK_NB)){if(fd>=0)close(fd);fprintf(stderr,"Preference lock unavailable.\n");return -1;}return fd;
}
static BOOL securePath(NSString *path,BOOL directory){
 struct stat s;if(lstat(path.fileSystemRepresentation,&s))return NO;
 return s.st_uid==0&&!(s.st_mode&0022)&&(directory?S_ISDIR(s.st_mode):S_ISREG(s.st_mode));
}
static NSDictionary *readTargetConfiguration(NSError **error){
 struct stat info;
 if(lstat(configurationPath.fileSystemRepresentation,&info)){
  if(errno!=ENOENT&&error)*error=failure(@"Cannot inspect requested-target configuration");return nil;
 }
 if(!securePath(configurationPath,NO)){if(error)*error=failure(@"Unsafe requested-target configuration; expected a root-owned regular file without group/other write access");return nil;}
 NSData *data=[NSData dataWithContentsOfFile:configurationPath options:0 error:error];if(!data)return nil;
 id configuration=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:error];
 if(!configuration||!targetFromConfiguration(configuration,error))return nil;
 return configuration;
}
static BOOL writeTargetConfiguration(NSDictionary *configuration,NSError **error){
 struct stat info;
 if(lstat(configurationPath.fileSystemRepresentation,&info)==0&&!securePath(configurationPath,NO)){
  if(error)*error=failure(@"Refusing unsafe requested-target configuration");return NO;
 }
 if(!configuration){
  if(unlink(configurationPath.fileSystemRepresentation)&&errno!=ENOENT){if(error)*error=failure(@"Cannot remove requested-target configuration");return NO;}return YES;
 }
 if(!targetFromConfiguration(configuration,error))return NO;
 NSData *data=[NSPropertyListSerialization dataWithPropertyList:configuration format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
 if(!data||![data writeToFile:configurationPath options:NSDataWritingAtomic error:error])return NO;
 if(chmod(configurationPath.fileSystemRepresentation,0644)){if(error)*error=failure(@"Cannot make requested target readable for monitoring");return NO;}
 NSDictionary *after=readTargetConfiguration(error);
 if(![after isEqual:configuration]){if(error&&!*error)*error=failure(@"Requested-target readback mismatch");return NO;}return YES;
}
static NSInteger backupValue(NSError **e){
 NSString *file=[state stringByAppendingPathComponent:@"previous-limit"];
 if(!securePath(state,YES)||!securePath(file,NO)){if(e)*e=failure(@"Missing or unsafe original-limit backup; no setting changed");return -1;}
 NSString *value=[NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:e];
 for(NSNumber *n in @[@80,@85,@90,@95,@100])if(exactInteger(value,n.integerValue))return n.integerValue;
 if(e)*e=failure(@"Invalid original-limit backup");return -1;
}
int persistentHold(NSInteger target){
 if(target<20||target>99){fprintf(stderr,"Target must be an integer from 20 to 99; use macOS Battery settings for full charging.\n");return 2;}
 // Even a no-op must inspect the root preference: a pending or interrupted write
 // can differ from both active policy and our last saved requested target.
 int lock=lockPreferences();if(lock<0)return 1;int result=1;
 NSError *e=nil;NSDictionary *configuration=nil;
 NSString *build=command(@"/usr/bin/sw_vers",@[@"-buildVersion"],&e);
 NSString *model=command(@"/usr/sbin/sysctl",@[@"-n",@"hw.model"],&e);
 if(![build isEqual:@"26A428"]||![model isEqual:@"MacBookPro18,1"]){e=failure(@"Experimental staging is restricted to MacBookPro18,1 / 26A428; only 50% has completed hardware validation");goto done;}
 {
 // Read configuration under the lock, so rollback uses current state.
 configuration=readTargetConfiguration(&e);if(e)goto done;
 NSDictionary *snapshot=nativeSnapshot(nativeClient(&e),&e);if(!snapshot)goto done;
 if(!exactInteger(snapshot[@"enabled_state"],1)||!exactInteger(readPreference(@"MCLFeatureState",&e),1)){e=failure(@"Enable Charge Limit in System Settings and finish temporary overrides first");goto done;}
 NSString *saved=readPreference(@"mclLimitValue",&e);if(!saved)goto done;
 NSInteger previous=0;
 if(exactInteger(saved,100))previous=100;
 else if(!parseHoldTarget(saved.UTF8String,&previous)){e=failure(@"Invalid saved system limit; refusing to overwrite it");goto done;}
 NSDictionary *live=effectiveLimitSnapshot(@{},target);
 if(targetAlreadyApplied(target,previous,configuration,live)){
  printf("%ld%% is saved, active and matches the requested target. No change or reboot needed.\n",(long)target);result=0;goto done;
 }
 struct stat info;
 if(lstat(state.fileSystemRepresentation,&info)==0){
  if(backupValue(&e)<0)goto done;
  // An existing valid original backup permits experimental -> experimental
  // transitions and replacing a pending target. Keep that backup unchanged.
 }else{
  if(errno!=ENOENT){e=failure(@"Cannot inspect original-limit backup");goto done;}
  if(![snapshot[@"available_limits"] containsObject:@(previous)]||!exactInteger(snapshot[@"selected_limit"],previous)){
   e=failure(@"First staging requires matching saved/active supported limits for a recoverable original backup");goto done;
  }
  if(mkdir(state.fileSystemRepresentation,0700)){e=failure(@"Cannot create backup directory");goto done;}
  NSString *file=[state stringByAppendingPathComponent:@"previous-limit"];
  int fd=open(file.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
  if(fd<0){e=failure(@"Cannot create original-limit backup");goto done;}
  NSData *data=[[[ @(previous) description] stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
  BOOL written=write(fd,data.bytes,data.length)==(ssize_t)data.length&&fsync(fd)==0;close(fd);
  if(!written){e=failure(@"Cannot persist original-limit backup; preference unchanged");goto done;}
 }
 if(!persistTargetTransition(target,previous,configuration,
   ^BOOL(NSInteger value,NSError **error){return saveLimit(value,error);},
   ^BOOL(NSDictionary *value,NSError **error){return writeTargetConfiguration(value,error);},&e))goto done;
 NSDictionary *after=effectiveLimitSnapshot(@{},target);
 if([after[@"policy_active"] boolValue])printf("Saved target=%ld%% and verified the active policy. No reboot needed.\n",(long)target);
 else {
  printf("Saved target=%ld%%. Active native selection is still %s%%.\n",(long)target,[after[@"native"][@"selected_limit"] description].UTF8String);
  printf("Until restart, macOS continues using the OLD limit and may keep charging above the requested target.\nSave work and restart normally, then run battctl verify %ld. No reboot performed.\n",(long)target);
 }
 if(target!=50)puts("Only 50% has completed hardware validation; observe this target after restart, including sleep/wake.");
 puts("Original-limit backup retained. Restore: sudo battctl restore");result=0;
 }
 done:if(result)fprintf(stderr,"%s\n",(e.localizedDescription?:@"Target update failed").UTF8String);close(lock);return result;
}
int persistentRestore(void){
 int lock=lockPreferences();if(lock<0)return 1;NSError *e=nil;int result=1;
 NSInteger previous=backupValue(&e);if(previous<0)goto done;
 if(!saveLimit(previous,&e))goto done;
 {
 id<BATTNativeClient> client=nativeClient(&e);
 if(!client||!nativeSetLimit(client,previous,&e))goto done;
 NSDictionary *after=effectiveLimitSnapshot(@{},previous);
 BOOL verified=[after[@"policy_active"] boolValue];
 if(previous==100&&[after[@"errors"] count]==0&&exactInteger(after[@"native"][@"selected_limit"],100)&&exactInteger(after[@"native"][@"enabled_state"],0)){
  verified=YES;
  for(NSDictionary *row in after[@"effective_limits"]){
   if([row[@"chargeSocLimitReason"] isEqual:@"manualChargeLimit"]&&!exactInteger(row[@"Terminated"],1)&&(!exactInteger(row[@"Terminated"],0)||!exactInteger(row[@"chargeSocLimitSoc"],100)))verified=NO;
  }
 }
 if(!verified){e=failure(@"Original preference saved, but effective restoration is not verified. Backup retained. Restart normally, then check battctl doctor and pmset -g battlimit");goto done;}
 if(!exactInteger(readPreference(@"mclLimitValue",&e),previous))goto done;
 if(!writeTargetConfiguration(nil,&e))goto done;
 // Retain the small backup for retries and future re-enabling; never overwrite it.
 printf("Restored saved and active limit to %ld%%. Original backup retained.\n",(long)previous);result=0;
 }
 done:if(result)fprintf(stderr,"%s\n",(e.localizedDescription?:@"Restoration not verified; backup retained").UTF8String);close(lock);return result;
}
