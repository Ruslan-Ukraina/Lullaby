/* A minimal Direct3D 9 program for trying a D3D9 backend: a window, a device, a clear and a
 * triangle for about four seconds, then a line in d3d9test.log (next to the exe) with the
 * adapter, the result of each step and the frames drawn. Exit code 0 only if frames were presented. */
#define COBJMACROS
#include <windows.h>
#include <d3d9.h>
#include <stdio.h>

typedef IDirect3D9 *(WINAPI *create_fn)(UINT);
struct vtx { float x, y, z, rhw; DWORD color; };

static LRESULT CALLBACK proc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    if (m == WM_DESTROY) PostQuitMessage(0);
    return DefWindowProcA(h, m, w, l);
}

int main(void)
{
    FILE *log = fopen("d3d9test.log", "w");
    if (!log) return 90;
    HMODULE dll = LoadLibraryA("d3d9.dll");
    fprintf(log, "d3d9.dll %s\n", dll ? "loaded" : "NOT loaded");
    create_fn create = dll ? (create_fn)GetProcAddress(dll, "Direct3DCreate9") : NULL;
    if (!create) { fprintf(log, "no Direct3DCreate9\n"); fclose(log); return 91; }

    WNDCLASSA wc = {0};
    wc.lpfnWndProc = proc; wc.hInstance = GetModuleHandleA(NULL); wc.lpszClassName = "d3d9test";
    RegisterClassA(&wc);
    HWND hwnd = CreateWindowA("d3d9test", "d3d9test", WS_OVERLAPPEDWINDOW | WS_VISIBLE, 100, 100, 640, 480, NULL, NULL, wc.hInstance, NULL);

    IDirect3D9 *d3d = create(D3D_SDK_VERSION);
    fprintf(log, "Direct3DCreate9 %s\n", d3d ? "ok" : "FAILED");
    if (!d3d) { fclose(log); return 92; }
    D3DADAPTER_IDENTIFIER9 id;
    if (SUCCEEDED(IDirect3D9_GetAdapterIdentifier(d3d, 0, 0, &id)))
        fprintf(log, "adapter: %s | driver: %s\n", id.Description, id.Driver);

    D3DPRESENT_PARAMETERS pp = {0};
    pp.Windowed = TRUE; pp.SwapEffect = D3DSWAPEFFECT_DISCARD; pp.BackBufferFormat = D3DFMT_UNKNOWN;
    pp.hDeviceWindow = hwnd; pp.PresentationInterval = D3DPRESENT_INTERVAL_ONE;
    IDirect3DDevice9 *dev = NULL;
    HRESULT hr = IDirect3D9_CreateDevice(d3d, 0, D3DDEVTYPE_HAL, hwnd, D3DCREATE_SOFTWARE_VERTEXPROCESSING, &pp, &dev);
    fprintf(log, "CreateDevice 0x%08lx\n", (unsigned long)hr);
    if (FAILED(hr)) { fclose(log); return 93; }

    DWORD start = GetTickCount(); int frames = 0;
    while (GetTickCount() - start < 4000) {
        MSG msg;
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageA(&msg); }
        float t = (float)(GetTickCount() - start) / 4000.0f;
        IDirect3DDevice9_Clear(dev, 0, NULL, D3DCLEAR_TARGET, D3DCOLOR_XRGB((int)(40 + 80 * t), 30, (int)(120 - 80 * t)), 1.0f, 0);
        struct vtx tri[3] = {
            {320.0f, 100.0f, 0.5f, 1.0f, 0xffff0000}, {500.0f, 380.0f, 0.5f, 1.0f, 0xff00ff00}, {140.0f, 380.0f, 0.5f, 1.0f, 0xff0000ff}};
        IDirect3DDevice9_BeginScene(dev);
        IDirect3DDevice9_SetFVF(dev, D3DFVF_XYZRHW | D3DFVF_DIFFUSE);
        IDirect3DDevice9_DrawPrimitiveUP(dev, D3DPT_TRIANGLELIST, 1, tri, sizeof(struct vtx));
        IDirect3DDevice9_EndScene(dev);
        if (SUCCEEDED(IDirect3DDevice9_Present(dev, NULL, NULL, NULL, NULL))) frames++;
    }
    fprintf(log, "frames presented: %d in %lu ms\n", frames, (unsigned long)(GetTickCount() - start));
    IDirect3DDevice9_Release(dev); IDirect3D9_Release(d3d);
    fclose(log);
    return frames > 0 ? 0 : 94;
}
