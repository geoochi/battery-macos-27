#import "../Sources/native.h"
#include <assert.h>
@interface FakeClient:NSObject<BATTNativeClient>
@property NSInteger limit;
@property NSInteger state;
@property NSInteger writes;
@property BOOL corrupt;
@property BOOL failRestore;
@property BOOL readFail;
@property BOOL partialFailure;
@property BOOL rejected;
@end
@implementation FakeClient
- (NSArray*)availableChargeLimitsWithError:(NSError**)e{if(self.readFail){*e=[NSError errorWithDomain:@"test" code:1 userInfo:nil];return nil;}return @[@80,@85,@90,@95,@100];}
- (unsigned char)getMCLLimitWithError:(NSError**)e{(void)e;return (unsigned char)self.limit;}
- (NSUInteger)isMCLCurrentlyEnabled:(NSError**)e{(void)e;return self.state;}
- (BOOL)setMCLLimit:(unsigned char)v error:(NSError**)e{self.writes++;if(self.rejected){*e=[NSError errorWithDomain:@"test" code:4 userInfo:nil];return NO;}if(self.failRestore&&v==80){*e=[NSError errorWithDomain:@"test" code:2 userInfo:nil];return NO;}self.limit=self.corrupt&&v==85?90:v;self.state=v==100?0:1;if(self.partialFailure&&v==85){*e=[NSError errorWithDomain:@"test" code:3 userInfo:nil];return NO;}return YES;}
@end
static FakeClient*fake(void){FakeClient*c=[FakeClient new];c.limit=80;c.state=1;return c;}
int main(void){@autoreleasepool{
 NSError*e=nil;FakeClient*c=fake();assert(!nativeSetLimit(c,50,&e));assert(c.writes==0&&c.limit==80);
 e=nil;assert(nativeSetLimit(c,85,&e));assert(c.writes==1&&c.limit==85);
 c=fake();c.corrupt=YES;e=nil;assert(!nativeSetLimit(c,85,&e));assert(c.writes==2&&c.limit==80);assert([e.localizedDescription containsString:@"Previous limit restored"]);
 c=fake();c.partialFailure=YES;e=nil;assert(!nativeSetLimit(c,85,&e));assert(c.writes==2&&c.limit==80);
 c=fake();c.corrupt=YES;c.failRestore=YES;e=nil;assert(!nativeSetLimit(c,85,&e));assert([e.localizedDescription containsString:@"Restoration was not verified"]);
 c=fake();c.readFail=YES;e=nil;assert(!nativeSetLimit(c,85,&e));assert(c.writes==0);
 c=fake();c.state=2;e=nil;assert(!nativeSetLimit(c,85,&e));assert(c.writes==0);
 c=fake();e=nil;assert(nativeSetLimit(c,80,&e));assert(c.writes==0);
 c=fake();e=nil;assert(nativeSetLimit(c,100,&e));assert(c.state==0&&c.limit==100);assert(nativeSetLimit(c,100,&e));assert(c.writes==1);
 c=fake();c.limit=50;c.rejected=YES;e=nil;assert(!nativeSetLimit(c,85,&e));assert(c.writes==1&&c.limit==50);assert([e.localizedDescription containsString:@"unchanged"]);
 c=fake();c.limit=70;c.corrupt=YES;e=nil;assert(!nativeSetLimit(c,85,&e));assert(c.writes==1);assert([e.localizedDescription containsString:@"cannot restore"]);assert([e.localizedDescription containsString:@"hold-native 70"]);
 puts("Native limit: unsupported targets, read failure, write/readback/rollback, disabled state passed");
}}
