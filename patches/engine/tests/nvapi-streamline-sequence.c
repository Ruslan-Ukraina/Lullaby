/* Streamline's getSystemCaps NVAPI sequence against the toolkit's nvapi64. */
#include <windows.h>
#include <stdio.h>
#include <string.h>
typedef void* (__cdecl *QI)(unsigned);
typedef int (__cdecl *F0)(void); typedef int (__cdecl *F2)(void*,void*);
typedef struct { unsigned version; void *pOSAdapterId; unsigned physicalGpuCount; void *physicalGpuHandles[64]; unsigned reserved[8]; } LOGDATA;
typedef struct { unsigned version; unsigned arch, impl, rev; } ARCH;
int main(void){
  HMODULE m=LoadLibraryA("nvapi64.dll"); printf("load %p\n",m); if(!m) return 1;
  QI q=(QI)GetProcAddress(m,"nvapi_QueryInterface"); printf("qi %p\n",q);
  int r=((F0)q(0x0150e828))(); printf("Initialize %d\n",r);
  void *h[64]={0}; unsigned n=0; r=((F2)q(0xe5ac921f))(h,&n); printf("EnumPhysicalGPUs %d n=%u h0=%p\n",r,n,h[0]);
  unsigned dv=0; char name[64]={0}; F2 gdv=(F2)q(0x2926aaad); printf("GetDriverAndBranchVersion fn %p\n",gdv); if(gdv){ r=gdv(&dv,name); printf("  -> %d ver %u branch %s\n",r,dv,name);}
  void *lg=0; F2 glp=(F2)q(0xadd604d1); printf("GetLogicalGPUFromPhysicalGPU fn %p\n",glp); if(glp){ r=glp(h[0],&lg); printf("  -> %d lg %p\n",r,lg);}
  LUID id={0}; LOGDATA ld; memset(&ld,0,sizeof ld); ld.version=sizeof(LOGDATA)|(1<<16); ld.pOSAdapterId=&id; F2 gli=(F2)q(0x842b066e); printf("GPU_GetLogicalGpuInfo fn %p\n",gli); if(gli){ r=gli(lg,&ld); printf("  -> %d luid %ld.%lu\n",r,id.HighPart,id.LowPart);}
  ARCH a={sizeof(ARCH)|(2<<16)}; F2 ga=(F2)q(0xd8265d24); printf("GPU_GetArchInfo fn %p\n",ga); if(ga){ r=ga(h[0],&a); printf("  -> %d arch 0x%x impl 0x%x\n",r,a.arch,a.impl);}
  return 0;}
