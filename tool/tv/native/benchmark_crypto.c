#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <dlfcn.h>
static double now(){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
int main(int n,char**v){if(n!=2)return 2;void*h=dlopen(v[1],RTLD_NOW);if(!h){puts("load failed");return 3;}
 void(*init)(void*)=dlsym(h,"mbedtls_gcm_init");int(*key)(void*,int,const unsigned char*,unsigned)=dlsym(h,"mbedtls_gcm_setkey");
 int(*crypt)(void*,int,size_t,const unsigned char*,size_t,const unsigned char*,size_t,const unsigned char*,unsigned char*,size_t,unsigned char*)=dlsym(h,"mbedtls_gcm_crypt_and_tag");
 if(!init||!key||!crypt)return 4;void*ctx=calloc(1,16384);unsigned char k[32]={0},iv[12]={0},tag[16],in[16384]={0},out[16384];init(ctx);int r=key(ctx,2,k,256);if(r){printf("key=%d\n",r);return 5;}
 double t=now();for(int i=0;i<512;i++){r=crypt(ctx,1,sizeof(in),iv,sizeof(iv),0,0,in,out,sizeof(tag),tag);if(r)return 6;}double d=now()-t;
 printf("AES256_GCM bytes=8388608 seconds=%.3f MB_per_second=%.2f\n",d,8.388608/d);return 0;}
