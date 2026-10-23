#include <windows.h>
#include <stdio.h>
typedef void* (__cdecl *QI)(unsigned); typedef int (__cdecl *F0)(void);
int main(void){
  HMODULE m=LoadLibraryExW(L"nvapi64.dll",NULL,0x800); printf("LoadLibraryExW(SEARCH_SYSTEM32) %p err %lu\n",m,GetLastError());
  if(!m) return 1; WCHAR p[MAX_PATH]; GetModuleFileNameW(m,p,MAX_PATH); printf("path %ls\n",p);
  QI q=(QI)GetProcAddress(m,"nvapi_QueryInterface"); void*dg=GetProcAddress(m,"nvapi_Direct_GetMethod"); printf("qi %p direct %p\n",q,dg);
  if(!q) return 2; void*a=q(0xad298d3f); printf("QI(ad298d3f) %p\n",a); F0 init=(F0)q(0x0150e828); printf("QI(Initialize) %p\n",init);
  if(init) printf("Initialize -> %d\n",init()); printf("QI(33c7358c) %p QI(593e8644) %p\n",q(0x33c7358c),q(0x593e8644)); return 0;}
