#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <dlfcn.h>
#include <sys/resource.h>
static double now(){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
int main(int n,char **v){
 if(n!=4)return 2;
 void *h=dlopen(v[1],RTLD_NOW);if(!h){puts("library load failed");return 3;}
 int(*openio)(void**,const char*,int,void*,void**)=dlsym(h,"avio_open2");
 int(*readio)(void*,unsigned char*,int)=dlsym(h,"avio_read");
 int(*closeio)(void**)=dlsym(h,"avio_closep");
 int(*dictset)(void**,const char*,const char*,int)=dlsym(h,"av_dict_set");
 int(*netinit)(void)=dlsym(h,"avformat_network_init");
 void(*setlog)(int)=dlsym(h,"av_log_set_level");
 if(!openio||!readio||!closeio||!dictset)return 4;
 if(setlog)setlog(-8);if(netinit)netinit();
 char u[16384];FILE *f=fopen(v[2],"r");if(!f)return 5;fgets(u,sizeof(u),f);fclose(f);
 for(int i=0;u[i];i++)if(u[i]=='\n'||u[i]=='\r'){u[i]=0;break;}
 void *ctx=0,*opts=0;dictset(&opts,"user_agent","Lavf/62.3.100",0);dictset(&opts,"rw_timeout","15000000",0);dictset(&opts,"ca_file",v[3],0);dictset(&opts,"tls_verify","1",0);
 double t=now();int r=openio(&ctx,u,1,0,&opts);if(r<0){printf("open_error=%d\n",r);return 6;}
 unsigned char b[65536];long total=0;struct rusage a,z;getrusage(RUSAGE_SELF,&a);double start=now();
 while(total<8*1024*1024){r=readio(ctx,b,sizeof(b));if(r<=0)break;total+=r;}
 getrusage(RUSAGE_SELF,&z);double seconds=now()-start;
 double cpu=z.ru_utime.tv_sec-a.ru_utime.tv_sec+(z.ru_utime.tv_usec-a.ru_utime.tv_usec)/1e6+z.ru_stime.tv_sec-a.ru_stime.tv_sec+(z.ru_stime.tv_usec-a.ru_stime.tv_usec)/1e6;
 printf("bytes=%ld read_seconds=%.3f read_Mbps=%.2f cpu_seconds=%.3f open_seconds=%.3f\n",total,seconds,total*8/seconds/1e6,cpu,start-t);closeio(&ctx);return total==8*1024*1024?0:7;
}
