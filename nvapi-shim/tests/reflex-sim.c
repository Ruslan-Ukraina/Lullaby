/* A GPU-bound game against Lullaby's nvapi64.dll: does its Reflex shorten the queue?
 *
 * A "GPU" thread takes GPU_MS per frame from a queue QUEUE frames deep; Present blocks
 * while the queue is full, as a swapchain does. The game spends CPU_MS a frame and calls
 * NvAPI_D3D_Sleep and the latency markers the way the Reflex SDK says. Latency is the
 * time from a frame's simulation start to the GPU finishing it. The GPU thread writes
 * the present feed the D3DMetal layer writes (winemac.so fix 0003): a drawable is
 * taken at Present and shown when the GPU is done with it.
 *
 * Usage: reflex-sim.exe [0|1]   1 (default) turns low latency mode on.
 * Prints "frames N fps F latency L ms" over the last half of the run. */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define GPU_MS 20
#define CPU_MS 8
#define QUEUE 3
#define FRAMES 300

typedef void *(__cdecl *query_fn)(unsigned int);
typedef int (__cdecl *set_sleep_mode_fn)(void *, void *);
typedef int (__cdecl *sleep_fn)(void *);
typedef int (__cdecl *marker_fn)(void *, void *);

typedef struct { UINT32 version; UINT8 low, boost; UINT32 interval; UINT8 markers, minq; UINT8 rsvd[30]; } sleep_mode;
typedef struct { UINT32 version; UINT64 frame; UINT32 type; UINT64 rsvd0; UINT8 rsvd[56]; } marker;

static LARGE_INTEGER freq;
static double now_ms(void) { LARGE_INTEGER c; QueryPerformanceCounter(&c); return c.QuadPart * 1000.0 / freq.QuadPart; }

static HANDLE slots, work;               /* free queue slots, queued frames */
static double sim_start[FRAMES], gpu_done[FRAMES];

typedef struct {
    UINT64 magic, version;
    volatile UINT64 acquired, presented;
    struct { volatile UINT64 acquire_ns, present_ns; } ring[256];
} present_feed;
static present_feed *feed;

static UINT64 now_ns(void)
{
    LARGE_INTEGER c; QueryPerformanceCounter(&c);
    return (UINT64)(c.QuadPart / freq.QuadPart) * 1000000000ull + (UINT64)(c.QuadPart % freq.QuadPart) * 1000000000ull / freq.QuadPart;
}

static void open_feed(void)
{
    char prefix[MAX_PATH], path[MAX_PATH + 64];
    if (!GetEnvironmentVariableA("WINEPREFIX", prefix, sizeof(prefix))) return;
    snprintf(path, sizeof(path), "Z:%s/.sevo", prefix);
    for (char *p = path; *p; p++) if (*p == '/') *p = '\\';
    CreateDirectoryA(path, NULL);
    strcat(path, "\\run");
    CreateDirectoryA(path, NULL);
    snprintf(path + strlen(path), 64, "\\%lu.present", GetCurrentProcessId());
    HANDLE file = CreateFileA(path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                              NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL | FILE_FLAG_DELETE_ON_CLOSE, NULL);
    HANDLE map = CreateFileMappingA(file, NULL, PAGE_READWRITE, 0, sizeof(present_feed), NULL);
    feed = MapViewOfFile(map, FILE_MAP_WRITE, 0, 0, sizeof(present_feed));
    feed->version = 1;
    feed->magic = 0x544e45535250424cull;
}

static void spin(double ms) { double end = now_ms() + ms; while (now_ms() < end) ; }

static DWORD WINAPI gpu(void *arg)
{
    for (int i = 0; i < FRAMES; i++)
    {
        WaitForSingleObject(work, INFINITE);
        Sleep(GPU_MS);
        gpu_done[i] = now_ms();
        if (feed) { feed->ring[i % 256].present_ns = now_ns(); MemoryBarrier(); feed->presented++; }
        ReleaseSemaphore(slots, 1, NULL);
    }
    return 0;
}

int main(int argc, char **argv)
{
    int on = argc > 1 ? atoi(argv[1]) : 1;
    HMODULE nv = LoadLibraryA("nvapi64.dll");
    query_fn q = nv ? (query_fn)GetProcAddress(nv, "nvapi_QueryInterface") : NULL;
    set_sleep_mode_fn set_mode = q ? (set_sleep_mode_fn)q(0xac1ca9e0) : NULL;
    sleep_fn nv_sleep = q ? (sleep_fn)q(0x852cd1d2) : NULL;
    marker_fn set_marker = q ? (marker_fn)q(0xd9984c05) : NULL;
    int dev = 1;

    QueryPerformanceFrequency(&freq);
    timeBeginPeriod(1);
    open_feed();
    if (!set_mode || !nv_sleep || !set_marker) { printf("no Reflex functions (nvapi64 %p)\n", nv); return 1; }
    sleep_mode m = { sizeof(sleep_mode) | (1u << 16), (UINT8)on, 0, 0, 1, 0, {0} };
    printf("SetSleepMode %d\n", set_mode(&dev, &m));

    slots = CreateSemaphoreA(NULL, QUEUE, QUEUE, NULL);
    work = CreateSemaphoreA(NULL, 0, FRAMES, NULL);
    CreateThread(NULL, 0, gpu, NULL, 0, NULL);

    for (int i = 0; i < FRAMES; i++)
    {
        marker mk = { sizeof(marker) | (1u << 16), (UINT64)i + 1, 0, 0, {0} };
        nv_sleep(&dev);
        sim_start[i] = now_ms();
        mk.type = 0; set_marker(&dev, &mk);          /* SIMULATION_START */
        spin(CPU_MS);
        mk.type = 4; set_marker(&dev, &mk);          /* PRESENT_START */
        WaitForSingleObject(slots, INFINITE);        /* Present: blocks on a full queue */
        if (feed) { feed->ring[i % 256].acquire_ns = now_ns(); MemoryBarrier(); feed->acquired++; }
        ReleaseSemaphore(work, 1, NULL);
        mk.type = 5; set_marker(&dev, &mk);          /* PRESENT_END */
    }
    Sleep(GPU_MS * (QUEUE + 2));

    double lat = 0;
    int n = 0;
    for (int i = FRAMES / 2; i < FRAMES; i++) if (gpu_done[i] > 0) { lat += gpu_done[i] - sim_start[i]; n++; }
    double secs = (gpu_done[FRAMES - 1] - gpu_done[FRAMES / 2]) / 1000.0;
    printf("low latency %d: frames %d fps %.1f latency %.1f ms\n", on, n, (FRAMES / 2 - 1) / secs, lat / n);
    return 0;
}
