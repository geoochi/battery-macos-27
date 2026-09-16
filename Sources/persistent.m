#import "persistent.h"
#import "native.h"
#include <sys/stat.h>
#include <sys/file.h>
#include <unistd.h>
static NSString *const domain=@"com.apple.smartcharging.topoffprotection";
// Keep the original reboot-test backup; never replace it with the experimental value.
static NSString *const state=@"/Library/Application Support/battctl-reboot-test";
static NSError *failure(NSString *s){return [NSError errorWithDomain:@"battctl.persistent" code:1 userInfo:@{NSLocalizedDescriptionKey:s}];}
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
 NSError *e=nil;NSDictionary *native=nativeSnapshot(nativeClient(&e),&e);
 NSMutableArray *errors=[NSMutableArray array];if(!native)[errors addObject:e.localizedDescription?:@"Native API unavailable"];
 e=nil;NSString *raw=command(@"/usr/bin/pmset",@[@"-g",@"battlimit"],&e);
 NSArray *limits=raw?parseBatteryLimits(raw,&e):nil;if(!limits)[errors addObject:e.localizedDescription?:@"Effective limits unavailable"];
 NSMutableDictionary *out=[limitAssessment(native,limits,battery,target) mutableCopy];
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
static NSInteger backupValue(NSError **e){
 NSString *file=[state stringByAppendingPathComponent:@"previous-limit"];
 if(!securePath(state,YES)||!securePath(file,NO)){if(e)*e=failure(@"Missing or unsafe original-limit backup; no setting changed");return -1;}
 NSString *value=[NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:e];
 for(NSNumber *n in @[@80,@85,@90,@95,@100])if(exactInteger(value,n.integerValue))return n.integerValue;
 if(e)*e=failure(@"Invalid original-limit backup");return -1;
}
int persistentHold50(void){
 NSDictionary *live=effectiveLimitSnapshot(@{},50);
 if([live[@"policy_active"] boolValue]){puts("50% is already active in PowerUI and the system battery policy. No change or reboot needed.\nReaching 50% and holding through sleep must still be measured: battctl monitor");return 0;}
 int lock=lockPreferences();if(lock<0)return 1;NSError *e=nil;int result=1;
 // The preference bypass is experimental and only verified on this build/model.
 NSString *build=command(@"/usr/bin/sw_vers",@[@"-buildVersion"],&e);
 NSString *model=command(@"/usr/sbin/sysctl",@[@"-n",@"hw.model"],&e);
 if(![build isEqual:@"26A428"]||![model isEqual:@"MacBookPro18,1"]){e=failure(@"Experimental 50% staging is verified only on MacBookPro18,1 / 26A428");goto done;}
 {
 NSDictionary *snapshot=nativeSnapshot(nativeClient(&e),&e);if(!snapshot)goto done;
 if(!exactInteger(snapshot[@"enabled_state"],1)||!exactInteger(readPreference(@"MCLFeatureState",&e),1)){e=failure(@"Enable Charge Limit in System Settings and finish temporary overrides first");goto done;}
 NSString *saved=readPreference(@"mclLimitValue",&e);if(!saved)goto done;
 struct stat s;BOOL exists=lstat(state.fileSystemRepresentation,&s)==0;NSInteger previous=-1;
 if(exists){
  previous=backupValue(&e);if(previous<0)goto done;
  if(exactInteger(saved,50)){puts("50% is saved with the original backup retained, but the effective policy is not 50%. Save your work and restart normally; then run battctl verify.");result=0;goto done;}
  // The backup remains the original limit, while rollback must restore the
  // current setting if this staging attempt fails.
  previous=[snapshot[@"selected_limit"] integerValue];
  if(![@[@80,@85,@90,@95,@100] containsObject:@(previous)]||!exactInteger(saved,previous)){e=failure(@"Saved and active supported limits differ; refusing to overwrite them");goto done;}
 }else{
  previous=[snapshot[@"selected_limit"] integerValue];
  if(![@[@80,@85,@90,@95,@100] containsObject:@(previous)]||!exactInteger(saved,previous)){e=failure(@"Saved and active supported limits must agree before staging");goto done;}
  if(mkdir(state.fileSystemRepresentation,0700)){e=failure(@"Cannot create backup directory");goto done;}
  NSString *file=[state stringByAppendingPathComponent:@"previous-limit"];
  int fd=open(file.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
  if(fd<0){e=failure(@"Cannot create original-limit backup");goto done;}
  NSData *data=[[[ @(previous) description] stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
  BOOL written=write(fd,data.bytes,data.length)==(ssize_t)data.length&&fsync(fd)==0;close(fd);
  if(!written){e=failure(@"Cannot persist original-limit backup; preference unchanged");goto done;}
 }
 if(!saveLimit(50,&e)){
  NSError *rollback=nil;BOOL restored=saveLimit(previous,&rollback);
  e=failure([NSString stringWithFormat:@"Staging failed: %@. Saved preference rollback: %@. Backup retained.",e.localizedDescription,restored?@"verified":rollback.localizedDescription]);goto done;
 }
 puts("Saved experimental limit=50; original limit backed up. No reboot performed.\nSave work and restart normally, then run battctl verify. Restore: sudo battctl restore");result=0;
 }
 done:if(result)fprintf(stderr,"%s\n",e.localizedDescription.UTF8String);close(lock);return result;
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
 if(!verified){e=failure(@"Original preference saved, but effective restoration is not verified. Backup retained. Restart normally, then check battctl native-limit and pmset -g battlimit");goto done;}
 if(!exactInteger(readPreference(@"mclLimitValue",&e),previous))goto done;
 // Retain the small backup for retries and future re-enabling; never overwrite it.
 printf("Restored saved and active limit to %ld%%. Original backup retained.\n",(long)previous);result=0;
 }
 done:if(result)fprintf(stderr,"%s\n",(e.localizedDescription?:@"Restoration not verified; backup retained").UTF8String);close(lock);return result;
}
