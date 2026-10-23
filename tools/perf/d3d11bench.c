/* A synthetic Direct3D 11 scene for comparing Wine builds and renderers without a game.
 *
 * Two kinds of frame, picked by BENCH_MODE:
 *   cpu  (default)  BENCH_DRAWS (4000) small triangles, each with its own constant buffer
 *                   update (Map WRITE_DISCARD) and Draw: the load that falls on the API
 *                   translation (DXMT, D3DMetal) and on Wine's synchronisation.
 *   gpu             8 full-screen triangles with a BENCH_FILL (300) iteration pixel loop:
 *                   the load that falls on the GPU, with almost no API calls.
 *
 * BENCH_SECONDS (20) of frames after BENCH_WARMUP (3) seconds of warm-up; BENCH_VSYNC=1
 * presents with a sync interval of 1, otherwise 0. Frame times are the intervals between
 * Present calls returning. One line of key=value pairs at the end; BENCH_CSV names a file
 * for every frame time (ms). Nothing here reads or writes anything of a game.
 * Built by tools/perf/stand.sh (x86_64-w64-mingw32-gcc -O2 -ld3d11 -ldxgi -ld3dcompiler_47). */

#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char vs_src[] =
    "cbuffer C : register(b0) { float4 off; float4 col; };\n"
    "struct VO { float4 p : SV_Position; float4 c : COLOR; };\n"
    "VO main(uint id : SV_VertexID) {\n"
    "  float2 v = float2(id == 1 ? 0.02 : 0.0, id == 2 ? 0.02 : 0.0);\n"
    "  VO o; o.p = float4(v + off.xy, 0, 1); o.c = col; return o; }\n";

static const char vs_full_src[] =
    "struct VO { float4 p : SV_Position; float4 c : COLOR; };\n"
    "VO main(uint id : SV_VertexID) {\n"
    "  float2 v = float2(id == 1 ? 3.0 : -1.0, id == 2 ? 3.0 : -1.0);\n"
    "  VO o; o.p = float4(v, 0, 1); o.c = float4(0.2, 0.4, 0.6, 1); return o; }\n";

static const char ps_src[] =
    "struct VO { float4 p : SV_Position; float4 c : COLOR; };\n"
    "float4 main(VO i) : SV_Target {\n"
    "  float4 c = i.c;\n"
    "  for (int k = 0; k < FILL; k++) c = c * 0.999 + sin(c) * 0.001;\n"
    "  return c; }\n";

static LARGE_INTEGER freq;

static double ms_between(LARGE_INTEGER a, LARGE_INTEGER b)
{
    return (double)(b.QuadPart - a.QuadPart) * 1000.0 / (double)freq.QuadPart;
}

static int cmp_double(const void *a, const void *b)
{
    double x = *(const double *)a, y = *(const double *)b;
    return x < y ? -1 : x > y;
}

static LRESULT CALLBACK wnd_proc(HWND w, UINT m, WPARAM wp, LPARAM lp)
{
    if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(w, m, wp, lp);
}

static int env_int(const char *name, int def)
{
    const char *v = getenv(name);
    return v && *v ? atoi(v) : def;
}

static ID3DBlob *compile(const char *src, const char *target, const char *fill)
{
    ID3DBlob *code = NULL, *errors = NULL;
    D3D_SHADER_MACRO macros[] = { { "FILL", fill }, { NULL, NULL } };
    HRESULT hr = D3DCompile(src, strlen(src), NULL, macros, NULL, "main", target, 0, 0, &code, &errors);
    if (FAILED(hr))
    {
        fprintf(stderr, "d3d11bench: D3DCompile %s failed (%08lx): %s\n", target, (unsigned long)hr,
                errors ? (const char *)ID3D10Blob_GetBufferPointer(errors) : "?");
        exit(3);
    }
    if (errors) ID3D10Blob_Release(errors);
    return code;
}

int main(void)
{
    const char *mode = getenv("BENCH_MODE") && *getenv("BENCH_MODE") ? getenv("BENCH_MODE") : "cpu";
    int gpu_mode = !strcmp(mode, "gpu");
    int draws = gpu_mode ? 8 : env_int("BENCH_DRAWS", 4000);
    int fill = env_int("BENCH_FILL", gpu_mode ? 300 : 1);
    int seconds = env_int("BENCH_SECONDS", 20), warmup = env_int("BENCH_WARMUP", 3);
    int vsync = env_int("BENCH_VSYNC", 0);
    int width = env_int("BENCH_WIDTH", 1280), height = env_int("BENCH_HEIGHT", 720);
    char fill_s[16];
    WNDCLASSW wc = { 0 };
    HWND hwnd;
    DXGI_SWAP_CHAIN_DESC sd = { 0 };
    IDXGISwapChain *swap;
    ID3D11Device *dev;
    ID3D11DeviceContext *ctx;
    D3D_FEATURE_LEVEL level, want = D3D_FEATURE_LEVEL_11_0;
    ID3D11Texture2D *backbuffer;
    ID3D11RenderTargetView *rtv;
    ID3D11Buffer *cb;
    ID3D11VertexShader *vs;
    ID3D11PixelShader *ps;
    ID3DBlob *vsb, *psb;
    D3D11_BUFFER_DESC bd = { 0 };
    D3D11_VIEWPORT vp = { 0, 0, (float)width, (float)height, 0, 1 };
    HRESULT hr;
    double *times;
    size_t cap, count = 0;
    LARGE_INTEGER t_start, t_prev, t_now, t_begin;
    MSG msg;

    QueryPerformanceFrequency(&freq);
    snprintf(fill_s, sizeof(fill_s), "%d", fill);

    wc.lpfnWndProc = wnd_proc;
    wc.hInstance = GetModuleHandleW(NULL);
    wc.lpszClassName = L"LullabyD3D11Bench";
    RegisterClassW(&wc);
    hwnd = CreateWindowExW(0, wc.lpszClassName, L"Lullaby D3D11 bench", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                           100, 100, width + 16, height + 39, NULL, NULL, wc.hInstance, NULL);
    if (!hwnd) { fprintf(stderr, "d3d11bench: no window\n"); return 3; }

    sd.BufferCount = 3;
    sd.BufferDesc.Width = (UINT)width; sd.BufferDesc.Height = (UINT)height;
    sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.OutputWindow = hwnd;
    sd.SampleDesc.Count = 1;
    sd.Windowed = TRUE;
    sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
    hr = D3D11CreateDeviceAndSwapChain(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, &want, 1, D3D11_SDK_VERSION,
                                       &sd, &swap, &dev, &level, &ctx);
    if (FAILED(hr)) { fprintf(stderr, "d3d11bench: D3D11CreateDeviceAndSwapChain failed (%08lx)\n", (unsigned long)hr); return 3; }

    vsb = compile(gpu_mode ? vs_full_src : vs_src, "vs_5_0", fill_s);
    psb = compile(ps_src, "ps_5_0", fill_s);
    hr = ID3D11Device_CreateVertexShader(dev, ID3D10Blob_GetBufferPointer(vsb), ID3D10Blob_GetBufferSize(vsb), NULL, &vs);
    if (FAILED(hr)) { fprintf(stderr, "d3d11bench: vertex shader (%08lx)\n", (unsigned long)hr); return 3; }
    hr = ID3D11Device_CreatePixelShader(dev, ID3D10Blob_GetBufferPointer(psb), ID3D10Blob_GetBufferSize(psb), NULL, &ps);
    if (FAILED(hr)) { fprintf(stderr, "d3d11bench: pixel shader (%08lx)\n", (unsigned long)hr); return 3; }

    bd.ByteWidth = 32;
    bd.Usage = D3D11_USAGE_DYNAMIC;
    bd.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    bd.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    hr = ID3D11Device_CreateBuffer(dev, &bd, NULL, &cb);
    if (FAILED(hr)) { fprintf(stderr, "d3d11bench: constant buffer (%08lx)\n", (unsigned long)hr); return 3; }

    hr = IDXGISwapChain_GetBuffer(swap, 0, &IID_ID3D11Texture2D, (void **)&backbuffer);
    if (FAILED(hr)) { fprintf(stderr, "d3d11bench: GetBuffer (%08lx)\n", (unsigned long)hr); return 3; }
    hr = ID3D11Device_CreateRenderTargetView(dev, (ID3D11Resource *)backbuffer, NULL, &rtv);
    if (FAILED(hr)) { fprintf(stderr, "d3d11bench: RTV (%08lx)\n", (unsigned long)hr); return 3; }

    ID3D11DeviceContext_OMSetRenderTargets(ctx, 1, &rtv, NULL);
    ID3D11DeviceContext_RSSetViewports(ctx, 1, &vp);
    ID3D11DeviceContext_IASetPrimitiveTopology(ctx, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    ID3D11DeviceContext_VSSetShader(ctx, vs, NULL, 0);
    ID3D11DeviceContext_PSSetShader(ctx, ps, NULL, 0);
    ID3D11DeviceContext_VSSetConstantBuffers(ctx, 0, 1, &cb);

    cap = (size_t)(seconds + 5) * 2000;
    times = malloc(sizeof(double) * cap);
    QueryPerformanceCounter(&t_begin);
    t_prev = t_begin;
    t_start = t_begin;

    for (;;)
    {
        float clear[4] = { 0.05f, 0.05f, 0.08f, 1.0f };
        int quit = 0;

        while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE))
        {
            if (msg.message == WM_QUIT) quit = 1;
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        if (quit) break;

        ID3D11DeviceContext_ClearRenderTargetView(ctx, rtv, clear);
        for (int i = 0; i < draws; i++)
        {
            if (!gpu_mode)
            {
                D3D11_MAPPED_SUBRESOURCE m;
                if (SUCCEEDED(ID3D11DeviceContext_Map(ctx, (ID3D11Resource *)cb, 0, D3D11_MAP_WRITE_DISCARD, 0, &m)))
                {
                    float *f = m.pData;
                    f[0] = -0.95f + 1.9f * (float)(i % 100) / 100.0f;
                    f[1] = -0.95f + 1.9f * (float)((i / 100) % 100) / 100.0f;
                    f[2] = 0; f[3] = 0;
                    f[4] = (float)(i & 255) / 255.0f; f[5] = 0.5f; f[6] = 0.8f; f[7] = 1;
                    ID3D11DeviceContext_Unmap(ctx, (ID3D11Resource *)cb, 0);
                }
            }
            ID3D11DeviceContext_Draw(ctx, 3, 0);
        }
        hr = IDXGISwapChain_Present(swap, (UINT)vsync, 0);
        if (FAILED(hr)) { fprintf(stderr, "d3d11bench: Present failed (%08lx)\n", (unsigned long)hr); return 3; }
        QueryPerformanceCounter(&t_now);
        if (ms_between(t_begin, t_now) >= warmup * 1000.0)
        {
            if (!count) { t_start = t_prev; }
            if (count < cap) times[count++] = ms_between(t_prev, t_now);
        }
        t_prev = t_now;
        if (ms_between(t_begin, t_now) >= (warmup + seconds) * 1000.0) break;
    }

    if (count < 10) { fprintf(stderr, "d3d11bench: only %zu frames measured\n", count); return 4; }
    {
        double total = ms_between(t_start, t_prev), sum = 0;
        double *sorted = malloc(sizeof(double) * count);
        double low1 = 0, low01 = 0;
        size_t n1 = count / 100 ? count / 100 : 1, n01 = count / 1000 ? count / 1000 : 1;
        const char *csv = getenv("BENCH_CSV");

        memcpy(sorted, times, sizeof(double) * count);
        qsort(sorted, count, sizeof(double), cmp_double);
        for (size_t i = 0; i < count; i++) sum += times[i];
        /* 1 % and 0.1 % lows: the frame rate of the slowest 1 % / 0.1 % of frames */
        for (size_t i = count - n1; i < count; i++) low1 += sorted[i];
        for (size_t i = count - n01; i < count; i++) low01 += sorted[i];
        low1 = 1000.0 / (low1 / (double)n1);
        low01 = 1000.0 / (low01 / (double)n01);
        printf("d3d11bench mode=%s draws=%d fill=%d vsync=%d frames=%zu fps=%.1f avg_ms=%.3f p50_ms=%.3f p95_ms=%.3f "
               "p99_ms=%.3f p999_ms=%.3f low1_fps=%.1f low01_fps=%.1f seconds=%.1f\n",
               mode, draws, fill, vsync, count, (double)count * 1000.0 / total, sum / (double)count,
               sorted[count / 2], sorted[(size_t)((double)count * 0.95)], sorted[(size_t)((double)count * 0.99)],
               sorted[(size_t)((double)count * 0.999)], low1, low01, total / 1000.0);
        if (csv && *csv)
        {
            FILE *f = fopen(csv, "w");
            if (f) { for (size_t i = 0; i < count; i++) fprintf(f, "%.4f\n", times[i]); fclose(f); }
        }
        fflush(stdout);
    }
    return 0;
}
