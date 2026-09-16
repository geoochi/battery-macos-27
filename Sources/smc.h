#pragma once
#include <IOKit/IOKitLib.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
typedef struct { uint8_t major,minor,build,reserved; uint16_t release; } Version;
typedef struct { uint16_t version,length; uint32_t cpu,gpu,mem; } Limits;
typedef struct { uint32_t size,type; uint8_t attributes; } KeyInfo;
typedef struct { uint32_t key; Version version; Limits limits; KeyInfo info; uint8_t result,status,command; uint32_t data; uint8_t bytes[32]; } Packet;
_Static_assert(sizeof(Packet)==80,"SMC ABI mismatch");
static io_connect_t smc;
static bool smcDiagnostics=false;
static bool smcPermissionDenied=false;
static int smcOpen(void) {
 io_service_t s=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AppleSMC"));
 if(!s)return -1;
 kern_return_t r=IOServiceOpen(s,mach_task_self(),0,&smc); IOObjectRelease(s);return r==0?0:-1;
}
static int call(Packet *in,Packet *out) {
 size_t n=sizeof(*out);memset(out,0,n);
 kern_return_t r=IOConnectCallStructMethod(smc,2,in,sizeof(*in),out,&n);
 if(r==kIOReturnNotPrivileged)smcPermissionDenied=true;
 if(smcDiagnostics)fprintf(stderr,"key=%c%c%c%c cmd=%u IOReturn=0x%08x result=0x%02x returned=%zu dataSize=%u type=0x%08x\n",(char)(in->key>>24),(char)(in->key>>16),(char)(in->key>>8),(char)in->key,in->command,r,out->result,n,out->info.size,out->info.type);
 return r==0 && n==sizeof(*out) && out->result==0?0:-1;
}
static int smcRead(const char *key,uint8_t *bytes,uint32_t size) {
 Packet in={0},out; for(int i=0;i<4;i++)in.key=(in.key<<8)|(uint8_t)key[i];
 in.command=9;if(call(&in,&out)||out.info.size!=size||size>32)return -1;
 in.info=out.info;in.command=5;if(call(&in,&out))return -1;memcpy(bytes,out.bytes,size);return 0;
}
static int smcWrite(const char *key,const uint8_t *bytes,uint32_t size) {
 uint8_t old[32];if(smcRead(key,old,size))return -1;
 if(!memcmp(old,bytes,size))return 0;
 Packet in={0},out;for(int i=0;i<4;i++)in.key=(in.key<<8)|(uint8_t)key[i];
 in.info.size=size;in.command=6;memcpy(in.bytes,bytes,size);
 if(call(&in,&out)||smcRead(key,old,size)||memcmp(old,bytes,size)) {fprintf(stderr,"SMC write/readback failed: %s\n",key);return -1;}return 0;
}
