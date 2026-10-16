#define COBJMACROS
#include <windows.h>
#include <stdio.h>
#include <dxgi1_4.h>
static const GUID IID_F = {0x7b7166ec,0x21c7,0x44ae,{0xb2,0x1a,0xc9,0xae,0x32,0x1a,0xe3,0x69}};
int main(void){ IDXGIFactory*f=0; HRESULT hr=CreateDXGIFactory(&IID_F,(void**)&f); printf("factory %08lx\n",hr);
 IDXGIAdapter*a; for(UINT i=0; f && IDXGIFactory_EnumAdapters(f,i,&a)!=DXGI_ERROR_NOT_FOUND; i++){ DXGI_ADAPTER_DESC d; IDXGIAdapter_GetDesc(a,&d);
 printf("adapter %u vendor 0x%04x device 0x%04x luid %ld.%lu name %ls\n",i,d.VendorId,d.DeviceId,d.AdapterLuid.HighPart,d.AdapterLuid.LowPart,d.Description);} return 0;}
