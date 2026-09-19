#import <Foundation/Foundation.h>
#include <IOKit/IOKitLib.h>
#include <signal.h>
#include <unistd.h>
#include "telemetry.h"
#include "native.h"
#include "persistent.h"
#include "version.h"
static volatile sig_atomic_t stopping;
static void stopSignal(int signal) {(void)signal;stopping=1;}
static NSDictionary *properties(const char *name) {
 io_service_t service=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching(name));
 if(!service)return @{};
 CFMutableDictionaryRef values=NULL;
 IOReturn result=IORegistryEntryCreateCFProperties(service,&values,kCFAllocatorDefault,0);
 IOObjectRelease(service);return result==0?CFBridgingRelease(values):@{};
}
static NSDictionary *batterySnapshot(void) {
 return telemetry(properties("AppleSmartBattery"),properties("IOPMrootDomain"));
}
static void printJSON(NSDictionary *value) {
 NSData *data=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:NULL];
 puts([[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
}
static BOOL conflictingController(void) {
 NSTask *task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:@"/bin/ps"];task.arguments=@[@"-axo",@"comm="];
 NSPipe *pipe=[NSPipe pipe];task.standardOutput=pipe;
 if(![task launchAndReturnError:NULL]){fprintf(stderr,"Cannot check running battery controllers.\n");return YES;}
 NSData *data=[pipe.fileHandleForReading readDataToEndOfFile];[task waitUntilExit];
 NSString *output=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
 for(NSString *line in [output componentsSeparatedByString:@"\n"]){
  NSString *name=line.lowercaseString;
  if([name containsString:@"battopt"]||[name containsString:@"aldente"]||[name containsString:@"batfi"]||[name hasSuffix:@"/battery"]||[name hasSuffix:@"/batt"]){
   fprintf(stderr,"Another battery controller is running. Stop it before changing native settings.\n");return YES;
  }
 }
 return task.terminationStatus!=0;
}
static BOOL experimentalControllerInstalled(void) {
 // Only detect leftovers; cleanup belongs to the upgrade script, not this CLI.
 return access("/Library/LaunchDaemons/com.geoochi.battctl.adapter.plist",F_OK)==0||
        access("/Library/Application Support/battctl-adapter/config.plist",F_OK)==0;
}
static void help(void) {
 puts("battctl " BATTCTL_VERSION " — native macOS charge limit\n"
      "Usage:\n"
      "  battctl hold TARGET                 Save an integer target (20..99); sudo required\n"
      "  battctl status [--json]              Read battery percentage, current and power\n"
      "  battctl verify [TARGET] [--json]     Verify the saved or explicit native target\n"
      "  battctl monitor [TARGET] [--json]    Repeat verification every 30 seconds\n"
      "  battctl doctor [--json]              Show native policy and controller conflicts\n"
      "  battctl restore                     Restore the original backed-up limit; sudo required\n"
      "  battctl --help | --version\n\n"
      "After changing the target, save work and restart normally if prompted.\n"
      "Before restart, the OLD limit still controls charging. No automatic reboot.\n"
      "macOS owns the policy; no battery-control daemon or interval cycling.\n"
      "For temporary full charging, use macOS Battery settings.");
}
int main(int argc,const char **argv) {@autoreleasepool{
 setbuf(stdout,NULL);
 if(argc==1||(argc==2&&(!strcmp(argv[1],"--help")||!strcmp(argv[1],"help")))){help();return 0;}
 if(argc==2&&!strcmp(argv[1],"--version")){puts("battctl " BATTCTL_VERSION);return 0;}
 NSString *command=@(argv[1]);
 if([command isEqual:@"hold"]||[command isEqual:@"restore"]){
  NSInteger target=0;BOOL hold=[command isEqual:@"hold"];
  if(hold?(argc!=3||!parseHoldTarget(argv[2],&target)):argc!=2){fprintf(stderr,"Usage: battctl %s%s\n",argv[1],hold?" TARGET (integer 20..99)":"");return 2;}
  if(experimentalControllerInstalled()){fprintf(stderr,"An experimental controller is still installed. Run sudo ./scripts/install.sh from this release to clean it up first.\n");return 1;}
  if(conflictingController())return 1;
  return hold?persistentHold(target):persistentRestore();
 }
 BOOL status=[command isEqual:@"status"],doctor=[command isEqual:@"doctor"],monitor=[command isEqual:@"monitor"],verify=[command isEqual:@"verify"];
 if(!status&&!doctor&&!monitor&&!verify){
  if([command isEqual:@"hold-native"])fprintf(stderr,"Command renamed: use sudo battctl hold TARGET.\n");
  else if([command isEqual:@"verify-native"])fprintf(stderr,"Command renamed: use battctl verify [TARGET].\n");
  else fprintf(stderr,"Unknown or removed command: %s. Run battctl --help.\n",argv[1]);return 2;
 }
 NSInteger target=0;BOOL json=NO;
 for(int i=2;i<argc;i++){
  if(!strcmp(argv[i],"--json")&&!json){json=YES;continue;}
  if((verify||monitor)&&!target&&parseHoldTarget(argv[i],&target))continue;
  fprintf(stderr,"Invalid arguments. Run battctl --help.\n");return 2;
 }
 signal(SIGINT,stopSignal);signal(SIGTERM,stopSignal);signal(SIGHUP,stopSignal);
 NSTimeInterval previous=0;int result=0;
 do{@autoreleasepool{
  NSDictionary *battery=batterySnapshot();
  if(status){
   if(json)printJSON(battery);
   else printf("%s battery=%s%% flow=%s power=%sW current=%smA lid=%s adapter=%s\n",[battery[@"time"] UTF8String],[battery[@"percent"] description].UTF8String,[battery[@"flow"] UTF8String],[battery[@"battery_watts"] description].UTF8String,[battery[@"current_mA"] description].UTF8String,[battery[@"lid"] UTF8String],[battery[@"adapter_present"] description].UTF8String);
   return 0;
  }
  NSMutableDictionary *report=[effectiveLimitSnapshot(battery,target) mutableCopy];
  report[@"backend"]=@"native";
  NSTimeInterval now=NSDate.date.timeIntervalSince1970;
  report[@"sample_gap_seconds"]=previous?@(now-previous):(id)NSNull.null;previous=now;
  if(doctor){
   BOOL conflict=conflictingController(),experimental=experimentalControllerInstalled();
   report[@"conflicting_controller"]=@(conflict);report[@"experimental_controller_installed"]=@(experimental);
   report[@"version"]=@BATTCTL_VERSION;
   if(conflict||experimental){report[@"policy_active"]=@NO;report[@"errors"]=[report[@"errors"] arrayByAddingObject:experimental?@"Run the release installer to remove the experimental controller.":@"Stop the conflicting battery controller."];}
  }
  result=[report[@"policy_active"] boolValue]?0:1;
  if(json||doctor)printJSON(report);
  else {
   printf("%s target=%s%% active_limit=%s%% policy=%s phase=%s battery=%s%% flow=%s power=%sW lid=%s adapter=%s\n",[battery[@"time"] UTF8String],[report[@"target"] description].UTF8String,[report[@"native"][@"selected_limit"] description].UTF8String,result?"NOT VERIFIED":"active",[report[@"phase"] UTF8String],[battery[@"percent"] description].UTF8String,[battery[@"flow"] UTF8String],[battery[@"battery_watts"] description].UTF8String,[battery[@"lid"] UTF8String],[battery[@"adapter_present"] description].UTF8String);
   for(NSString *error in report[@"errors"])fprintf(stderr,"%s\n",error.UTF8String);
  }
  if(!monitor)break;
  for(int i=0;i<30&&!stopping;i++)sleep(1);
 }}while(!stopping);
 return monitor?0:result;
}}
