/* Swapchain without a window: D3DMetal 4.0b3 asks Wine for the best window
   (FindBestWindowHWND) with this swapchain's size. */
#define COBJMACROS
#include <windows.h>
#include <stdio.h>
#include <d3d12.h>
#include <dxgi1_4.h>
static const GUID IID_F2 = {0x50c83a1c,0xe072,0x4c48,{0x87,0xb0,0x36,0x30,0xfa,0x36,0xa6,0xd0}};
static const GUID IID_Dev = {0x189819f1,0x1db6,0x4b57,{0xbe,0x54,0x18,0x21,0x33,0x9b,0x85,0xf7}};
static const GUID IID_Q = {0x0ec870a6,0x5d7e,0x4c22,{0x8c,0xfe,0x05,0xaa,0xb3,0x44,0xc9,0x8b}};
int main(void){
  WNDCLASSA wc={0}; wc.lpfnWndProc=DefWindowProcA; wc.hInstance=GetModuleHandleA(0); wc.lpszClassName="fbw"; RegisterClassA(&wc);
  RECT r={0,0,640,480}; AdjustWindowRect(&r,WS_OVERLAPPEDWINDOW,FALSE);
  HWND w=CreateWindowA("fbw","fbw-test",WS_OVERLAPPEDWINDOW|WS_VISIBLE,100,100,r.right-r.left,r.bottom-r.top,0,0,wc.hInstance,0);
  ShowWindow(w,SW_SHOW); UpdateWindow(w); printf("window %p\n",w); fflush(stdout);
  IDXGIFactory2*f=0; HRESULT hr=CreateDXGIFactory2(0,&IID_F2,(void**)&f); printf("factory %08lx\n",hr);
  ID3D12Device*d=0; hr=D3D12CreateDevice(NULL,D3D_FEATURE_LEVEL_11_0,&IID_Dev,(void**)&d); printf("device %08lx\n",hr);
  D3D12_COMMAND_QUEUE_DESC qd={0}; ID3D12CommandQueue*q=0; hr=ID3D12Device_CreateCommandQueue(d,&qd,&IID_Q,(void**)&q); printf("queue %08lx\n",hr);
  DXGI_SWAP_CHAIN_DESC1 sd={0}; sd.Width=640; sd.Height=480; sd.Format=DXGI_FORMAT_R8G8B8A8_UNORM; sd.SampleDesc.Count=1;
  sd.BufferUsage=DXGI_USAGE_RENDER_TARGET_OUTPUT; sd.BufferCount=2; sd.SwapEffect=DXGI_SWAP_EFFECT_FLIP_DISCARD; sd.Scaling=DXGI_SCALING_STRETCH;
  IDXGISwapChain1*s=0; hr=IDXGIFactory2_CreateSwapChainForComposition(f,(IUnknown*)q,&sd,NULL,&s); printf("composition swapchain %08lx %p\n",hr,s); fflush(stdout);
  if(s){ for(int i=0;i<30;i++){ MSG m; while(PeekMessageA(&m,0,0,0,PM_REMOVE)) DispatchMessageA(&m); hr=IDXGISwapChain1_Present(s,1,0); Sleep(16);} printf("present %08lx\n",hr);}
  printf("done\n"); return 0;
}
