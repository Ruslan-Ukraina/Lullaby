/* Lullaby's nvapi64.dll: stands in front of D3DMetal's (Apple's Game Porting Toolkit),
 * which the run script stages as nvapi64_d3dm.dll.
 *
 * - Every function a game asks for goes to D3DMetal's, and the first request for each is
 *   logged by name (LULLABY_NVAPI_LOG, a Windows path), with whether D3DMetal has it.
 * - NVIDIA Reflex, which D3DMetal leaves as stubs, is answered here, the way Korthos
 *   Software's low_latency_layer does it for Vulkan (https://github.com/Korthos-Software/
 *   low_latency_layer, MIT): with low latency mode on, the game's NvAPI_D3D_Sleep holds
 *   each frame until no frame is queued in front of it, then the game's minimum frame
 *   interval. Waiting for the previous frame outright leaves the GPU idle while the CPU
 *   builds the next one, so frame N goes once frame N-2 is on the screen and its CPU part
 *   (averaged) would end as frame N-1 leaves the GPU (averaged): no queue and no bubble. "On the screen" comes from the D3DMetal layer's present feed (winemac.so
 *   fix 0003, <prefix>/.sevo/run/<Windows pid>.present). LULLABY_REFLEX=0 leaves Reflex
 *   to D3DMetal.
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include "nvapi_names.h"

typedef int NvAPI_Status;
#define NVAPI_OK 0
#define NVAPI_ERROR (-1)
#define NVAPI_INVALID_ARGUMENT (-5)
#define NVAPI_INCOMPATIBLE_STRUCT_VERSION (-9)

#define ID_SET_SLEEP_MODE 0xac1ca9e0u
#define ID_GET_SLEEP_STATUS 0xaef96ca1u
#define ID_SLEEP 0x852cd1d2u
#define ID_GET_LATENCY 0x1a587f9cu
#define ID_SET_LATENCY_MARKER 0xd9984c05u
#define ID_SET_ASYNC_FRAME_MARKER 0x13c98f73u
#define ID_NOTIFY_OUT_OF_BAND_QUEUE 0x03d6e8cbu

/* NVIDIA's nvapi.h (MIT), version 1 of each. */
typedef struct {
    UINT32 version;
    UINT8 bLowLatencyMode, bLowLatencyBoost;
    UINT32 minimumIntervalUs;
    UINT8 bUseMarkersToOptimize, bUseMinQueueTime;
    UINT8 rsvd[30];
} NV_SET_SLEEP_MODE_PARAMS;

typedef struct {
    UINT32 version;
    UINT8 bLowLatencyMode, bFsVrr, bCplVsyncOn;
    UINT32 sleepIntervalUs;
    UINT8 bUseGameSleep, bFullscreenIFlip, fgMultiplier, bDfgControl;
    UINT32 dfgFrameTimeTargetUs;
    UINT8 rsvd[114];
} NV_GET_SLEEP_STATUS_PARAMS;

enum { SIMULATION_START = 0, SIMULATION_END, RENDERSUBMIT_START, RENDERSUBMIT_END,
       PRESENT_START, PRESENT_END, INPUT_SAMPLE };

typedef struct {
    UINT32 version;
    UINT64 frameID;
    UINT32 markerType;
    UINT64 rsvd0;
    UINT8 rsvd[56];
} NV_LATENCY_MARKER_PARAMS;

typedef struct {
    UINT64 frameID, inputSampleTime, simStartTime, simEndTime, renderSubmitStartTime,
           renderSubmitEndTime, presentStartTime, presentEndTime, driverStartTime, driverEndTime,
           osRenderQueueStartTime, osRenderQueueEndTime, gpuRenderStartTime, gpuRenderEndTime;
    UINT32 gpuActiveRenderTimeUs, gpuFrameTimeUs;
    UINT64 cameraConstructedTime;
    UINT32 crossAdapterCopyTimeUs, aiFrameTimeUs;
    UINT8 rsvd[104];
} NV_FRAME_REPORT;

typedef struct {
    UINT32 version;
    NV_FRAME_REPORT frameReport[64];
    UINT8 rsvd[32];
} NV_LATENCY_RESULT_PARAMS;

/* The D3DMetal layer's present feed, as winemac.so fix 0003 writes it. */
#define FEED_MAGIC 0x544e45535250424cull
#define FEED_RING 256
typedef struct {
    UINT64 magic, version;
    volatile UINT64 acquired, presented;
    struct { volatile UINT64 acquire_ns, present_ns; } ring[FEED_RING];
} present_feed;

typedef void *(__cdecl *query_fn)(unsigned int);
typedef void *(__cdecl *direct_fn)(void *, void *, void *, void *);

static INIT_ONCE init_once = INIT_ONCE_STATIC_INIT;
static query_fn real_query;
static direct_fn real_direct;
static BOOL reflex_here = TRUE;
static HANDLE log_file = INVALID_HANDLE_VALUE;
static SRWLOCK log_lock = SRWLOCK_INIT;

static void log_line(const char *fmt, ...)
{
    char buf[512];
    va_list ap;
    int n;
    DWORD written;

    if (log_file == INVALID_HANDLE_VALUE) return;
    va_start(ap, fmt);
    n = _vsnprintf(buf, sizeof(buf) - 2, fmt, ap);
    va_end(ap);
    if (n < 0) n = sizeof(buf) - 2;
    buf[n++] = '\n';
    AcquireSRWLockExclusive(&log_lock);
    WriteFile(log_file, buf, n, &written, NULL);
    ReleaseSRWLockExclusive(&log_lock);
}

static const char *name_of(unsigned int id)
{
    for (size_t i = 0; i < sizeof(nvapi_names) / sizeof(nvapi_names[0]); i++)
        if (nvapi_names[i].id == id) return nvapi_names[i].name;
    return "?";
}

static BOOL CALLBACK init(INIT_ONCE *once, void *param, void **ctx)
{
    WCHAR path[MAX_PATH];
    char value[8];
    HMODULE real;

    if (GetEnvironmentVariableW(L"LULLABY_NVAPI_LOG", path, MAX_PATH) - 1 < MAX_PATH - 1)
        log_file = CreateFileW(path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
                               OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (GetEnvironmentVariableA("LULLABY_REFLEX", value, sizeof(value)) && !strcmp(value, "0"))
        reflex_here = FALSE;
    log_line("=== lullaby nvapi64 (pid %lu): Reflex %s", GetCurrentProcessId(),
             reflex_here ? "paced by Lullaby" : "left to D3DMetal");
    if (!(real = LoadLibraryW(L"nvapi64_d3dm.dll")))
    {
        log_line("D3DMetal's nvapi64_d3dm.dll did not load (error %lu): every function is missing", GetLastError());
        return TRUE;
    }
    real_query = (query_fn)GetProcAddress(real, "nvapi_QueryInterface");
    real_direct = (direct_fn)GetProcAddress(real, "nvapi_Direct_GetMethod");
    return TRUE;
}

static void ensure_init(void)
{
    InitOnceExecuteOnce(&init_once, init, NULL, NULL);
}

/* ---- time: QueryPerformanceCounter is mach_continuous_time in 100 ns, the feed's clock ---- */

static LARGE_INTEGER qpc_freq;

static uint64_t now_ns(void)
{
    LARGE_INTEGER c;
    QueryPerformanceCounter(&c);
    return (uint64_t)(c.QuadPart / qpc_freq.QuadPart) * 1000000000ull +
           (uint64_t)(c.QuadPart % qpc_freq.QuadPart) * 1000000000ull / (uint64_t)qpc_freq.QuadPart;
}

LONG WINAPI NtDelayExecution(BOOLEAN alertable, const LARGE_INTEGER *timeout);

static void nap(uint64_t ns)
{
    LARGE_INTEGER rel;
    rel.QuadPart = -(LONGLONG)(ns / 100);
    NtDelayExecution(FALSE, &rel);
}

/* Sleeps to within a millisecond of the deadline, then yields until it. */
static void wait_until(uint64_t deadline)
{
    for (;;)
    {
        uint64_t t = now_ns();
        if (t >= deadline) return;
        if (deadline - t > 1500000) nap(deadline - t - 1000000);
        else SwitchToThread();
    }
}

/* ---- the present feed ---- */

static present_feed *feed;
static uint64_t feed_next_try;

/* Maps <WINEPREFIX>/.sevo/run/<pid>.present once the layer has written it. */
static present_feed *get_feed(void)
{
    char prefix[MAX_PATH], path[MAX_PATH + 64];
    HANDLE file, mapping;
    present_feed *view;
    uint64_t t;

    if (feed) return feed;
    t = now_ns();
    if (t < feed_next_try) return NULL;
    feed_next_try = t + 1000000000ull;
    DWORD n = GetEnvironmentVariableA("WINEPREFIX", prefix, sizeof(prefix));
    if (!n || n >= sizeof(prefix) || prefix[0] != '/') return NULL;
    snprintf(path, sizeof(path), "Z:%s/.sevo/run/%lu.present", prefix, GetCurrentProcessId());
    for (char *p = path; *p; p++) if (*p == '/') *p = '\\';
    file = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                       NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) return NULL;
    mapping = CreateFileMappingA(file, NULL, PAGE_READONLY, 0, sizeof(present_feed), NULL);
    CloseHandle(file);
    if (!mapping) return NULL;
    view = MapViewOfFile(mapping, FILE_MAP_READ, 0, 0, sizeof(present_feed));
    CloseHandle(mapping);
    if (!view) return NULL;
    if (view->magic != FEED_MAGIC || view->version != 1)
    {
        UnmapViewOfFile(view);
        return NULL;
    }
    log_line("reflex: reading the present feed %s", path);
    return feed = view;
}

/* ---- Reflex ---- */

#define MAX_WAIT_NS 50000000ull /* a frame that never shows waits no longer than this */
#define RING 64

static SRWLOCK reflex_lock = SRWLOCK_INIT;
static BOOL low_latency;
static UINT32 interval_us;
static BOOL game_sleeps, warned_no_feed;
static uint64_t last_release;      /* when the last Sleep returned */
static NV_FRAME_REPORT reports[RING];

/* Just in time: frame N is released once frame N-2 is on the screen, and no earlier than
   when its CPU part, done, meets frame N-1 leaving the GPU. Per released frame (frame_no):
   the feed's drawable count at its release, and its SIMULATION_START. */
#define FRAMES 8
static uint64_t frame_no;
static uint64_t acquired_at_release[FRAMES], sim_start_of[FRAMES];
static uint64_t release_of_game_id[RING];   /* by the game's frame id: when its Sleep returned */
static uint64_t prev_done;                  /* when the previous wait's frame reached the screen */
static double gpu_ns, cpu_ns;               /* averages: frame interval on screen, CPU time to Present */

/* stats for the log */
static uint64_t stat_since, stat_frames, stat_wait_ns, stat_timeouts;
/* PC latency, as Reflex names it: from a frame's SIMULATION_START to its reaching the screen. */
static uint64_t stat_latency_ns, stat_latency_samples;

static NV_FRAME_REPORT *report_for(uint64_t game_id)
{
    NV_FRAME_REPORT *r = &reports[game_id % RING];
    if (r->frameID != game_id)
    {
        memset(r, 0, sizeof(*r));
        r->frameID = game_id;
    }
    return r;
}

static void average(double *avg, double sample)
{
    *avg = *avg ? *avg * 0.9 + sample * 0.1 : sample;
}

static NvAPI_Status __cdecl lb_SetSleepMode(void *dev, NV_SET_SLEEP_MODE_PARAMS *p)
{
    if (!dev || !p) return NVAPI_INVALID_ARGUMENT;
    if ((p->version >> 16) != 1) return NVAPI_INCOMPATIBLE_STRUCT_VERSION;
    AcquireSRWLockExclusive(&reflex_lock);
    if (low_latency != !!p->bLowLatencyMode || interval_us != p->minimumIntervalUs)
        log_line("reflex: SetSleepMode low latency %d, boost %d, minimum interval %u us",
                 p->bLowLatencyMode, p->bLowLatencyBoost, p->minimumIntervalUs);
    low_latency = !!p->bLowLatencyMode;
    interval_us = p->minimumIntervalUs;
    ReleaseSRWLockExclusive(&reflex_lock);
    return NVAPI_OK;
}

static NvAPI_Status __cdecl lb_GetSleepStatus(void *dev, NV_GET_SLEEP_STATUS_PARAMS *p)
{
    if (!dev || !p) return NVAPI_INVALID_ARGUMENT;
    if ((p->version >> 16) != 1) return NVAPI_INCOMPATIBLE_STRUCT_VERSION;
    AcquireSRWLockShared(&reflex_lock);
    p->bLowLatencyMode = low_latency;
    p->bFsVrr = FALSE;
    p->bCplVsyncOn = FALSE;
    if ((p->version & 0xffff) >= offsetof(NV_GET_SLEEP_STATUS_PARAMS, rsvd))
    {
        p->sleepIntervalUs = interval_us;
        p->bUseGameSleep = game_sleeps;
    }
    ReleaseSRWLockShared(&reflex_lock);
    return NVAPI_OK;
}

/* Whether every drawable handed out before frame N-1's release is on the screen, i.e.
   frames up to N-2; *shown gets when the last of them got there. */
static BOOL older_frames_shown(present_feed *f, uint64_t need, uint64_t *shown)
{
    UINT64 presented = f->presented;
    MemoryBarrier();
    if (presented < need) return FALSE;
    *shown = f->ring[(need - 1) % FEED_RING].present_ns;
    return TRUE;
}

static NvAPI_Status __cdecl lb_Sleep(void *dev)
{
    uint64_t start, deadline, t, need = 0, shown = 0, target = 0;
    present_feed *f;
    BOOL on, timed_out = FALSE;
    UINT32 interval;

    if (!dev) return NVAPI_INVALID_ARGUMENT;
    AcquireSRWLockExclusive(&reflex_lock);
    if (!game_sleeps) log_line("reflex: the game calls Sleep");
    game_sleeps = TRUE;
    on = low_latency;
    interval = interval_us;
    f = on ? get_feed() : NULL;
    if (on && !f && !warned_no_feed)
    {
        log_line("reflex: no present feed (an upscaler or another renderer?), frames go unpaced");
        warned_no_feed = TRUE;
    }
    if (f && frame_no) need = acquired_at_release[frame_no % FRAMES];
    ReleaseSRWLockExclusive(&reflex_lock);

    start = now_ns();
    if (f && need)
    {
        deadline = start + MAX_WAIT_NS;
        while (!older_frames_shown(f, need, &shown))
        {
            if (now_ns() >= deadline) { timed_out = TRUE; break; }
            nap(250000);
        }
        if (!timed_out)
        {
            if (!shown || shown > now_ns()) shown = now_ns();
            AcquireSRWLockExclusive(&reflex_lock);
            if (prev_done && shown > prev_done && shown - prev_done < 100000000ull)
                average(&gpu_ns, (double)(shown - prev_done));
            prev_done = shown;
            /* Frame N-1 leaves the GPU about one frame interval after N-2 showed; frame N
               starts its CPU part that long before, less a margin against a bubble. */
            if (gpu_ns && cpu_ns && cpu_ns < gpu_ns)
                target = shown + (uint64_t)(gpu_ns - cpu_ns - 1000000 - gpu_ns * 0.05);
            if (sim_start_of[(frame_no - 1) % FRAMES] && sim_start_of[(frame_no - 1) % FRAMES] < shown)
            {
                stat_latency_ns += shown - sim_start_of[(frame_no - 1) % FRAMES];
                stat_latency_samples++;
            }
            ReleaseSRWLockExclusive(&reflex_lock);
            if (target > now_ns()) wait_until(target);
        }
    }
    if (interval && last_release) wait_until(last_release + (uint64_t)interval * 1000);
    t = now_ns();

    AcquireSRWLockExclusive(&reflex_lock);
    frame_no++;
    acquired_at_release[frame_no % FRAMES] = f ? f->acquired : 0;
    sim_start_of[frame_no % FRAMES] = 0;
    last_release = t;
    stat_frames++;
    stat_wait_ns += t - start;
    stat_timeouts += timed_out;
    if (!stat_since) stat_since = t;
    else if (t - stat_since >= 5000000000ull)
    {
        double secs = (t - stat_since) / 1e9;
        log_line("reflex: %s, %.1f fps, held %.2f ms a frame, PC latency %.1f ms, GPU %.2f ms, CPU %.2f ms, %llu frames not shown in time",
                 on ? (f ? "low latency" : "low latency without a feed") : "off",
                 stat_frames / secs, stat_wait_ns / 1e6 / stat_frames,
                 stat_latency_samples ? stat_latency_ns / 1e6 / stat_latency_samples : -1.0,
                 gpu_ns / 1e6, cpu_ns / 1e6, stat_timeouts);
        stat_since = t;
        stat_frames = stat_wait_ns = stat_timeouts = 0;
        stat_latency_ns = stat_latency_samples = 0;
    }
    ReleaseSRWLockExclusive(&reflex_lock);
    return NVAPI_OK;
}

static NvAPI_Status __cdecl lb_SetLatencyMarker(void *dev, NV_LATENCY_MARKER_PARAMS *p)
{
    uint64_t us = now_ns() / 1000;
    NV_FRAME_REPORT *r;

    if (!dev || !p) return NVAPI_INVALID_ARGUMENT;
    if ((p->version >> 16) != 1) return NVAPI_INCOMPATIBLE_STRUCT_VERSION;
    AcquireSRWLockExclusive(&reflex_lock);
    r = report_for(p->frameID);
    switch (p->markerType)
    {
    case SIMULATION_START:
        r->simStartTime = us;
        if (!sim_start_of[frame_no % FRAMES]) sim_start_of[frame_no % FRAMES] = us * 1000;
        release_of_game_id[p->frameID % RING] = last_release;
        break;
    case SIMULATION_END: r->simEndTime = us; break;
    case RENDERSUBMIT_START: r->renderSubmitStartTime = us; break;
    case RENDERSUBMIT_END: r->renderSubmitEndTime = us; break;
    case PRESENT_START: r->presentStartTime = us; break;
    case PRESENT_END:
        r->presentEndTime = us;
        /* The CPU part of a frame: from its release to Present returning. */
        if (release_of_game_id[p->frameID % RING] && us * 1000 > release_of_game_id[p->frameID % RING])
            average(&cpu_ns, (double)(us * 1000 - release_of_game_id[p->frameID % RING]));
        release_of_game_id[p->frameID % RING] = 0;
        break;
    case INPUT_SAMPLE: r->inputSampleTime = us; break;
    default: break;
    }
    ReleaseSRWLockExclusive(&reflex_lock);
    return NVAPI_OK;
}

static NvAPI_Status __cdecl lb_GetLatency(void *dev, NV_LATENCY_RESULT_PARAMS *p)
{
    uint64_t newest = 0;

    if (!dev || !p) return NVAPI_INVALID_ARGUMENT;
    if ((p->version >> 16) != 1) return NVAPI_INCOMPATIBLE_STRUCT_VERSION;
    AcquireSRWLockShared(&reflex_lock);
    /* Oldest first, as the driver reports them. */
    for (int i = 0; i < RING; i++) if (reports[i].frameID > newest) newest = reports[i].frameID;
    for (int i = 0; i < 64; i++)
    {
        uint64_t id = newest >= 63 ? newest - 63 + i : (uint64_t)i;
        if (reports[id % RING].frameID == id) p->frameReport[i] = reports[id % RING];
        else memset(&p->frameReport[i], 0, sizeof(p->frameReport[i]));
    }
    ReleaseSRWLockShared(&reflex_lock);
    return NVAPI_OK;
}

static NvAPI_Status __cdecl lb_SetAsyncFrameMarker(void *queue, void *params)
{
    return queue && params ? NVAPI_OK : NVAPI_INVALID_ARGUMENT;
}

static NvAPI_Status __cdecl lb_NotifyOutOfBandCommandQueue(void *queue, int type)
{
    return queue ? NVAPI_OK : NVAPI_INVALID_ARGUMENT;
}

static void *reflex_function(unsigned int id)
{
    switch (id)
    {
    case ID_SET_SLEEP_MODE: return lb_SetSleepMode;
    case ID_GET_SLEEP_STATUS: return lb_GetSleepStatus;
    case ID_SLEEP: return lb_Sleep;
    case ID_GET_LATENCY: return lb_GetLatency;
    case ID_SET_LATENCY_MARKER: return lb_SetLatencyMarker;
    case ID_SET_ASYNC_FRAME_MARKER: return lb_SetAsyncFrameMarker;
    case ID_NOTIFY_OUT_OF_BAND_QUEUE: return lb_NotifyOutOfBandCommandQueue;
    default: return NULL;
    }
}

/* ---- exports ---- */

static unsigned int seen[1024];
static unsigned int seen_count;

void *__cdecl nvapi_QueryInterface(unsigned int id)
{
    void *real_fn, *ours;
    BOOL first = TRUE;

    ensure_init();
    real_fn = real_query ? real_query(id) : NULL;
    ours = reflex_here ? reflex_function(id) : NULL;

    AcquireSRWLockExclusive(&log_lock);
    for (unsigned int i = 0; i < seen_count; i++) if (seen[i] == id) { first = FALSE; break; }
    if (first && seen_count < sizeof(seen) / sizeof(seen[0])) seen[seen_count++] = id;
    ReleaseSRWLockExclusive(&log_lock);
    if (first)
        log_line("query 0x%08x %s: %s", id, name_of(id),
                 ours ? (real_fn ? "Lullaby (D3DMetal has one too)" : "Lullaby")
                      : (real_fn ? "D3DMetal" : "missing"));
    return ours ? ours : real_fn;
}

void *__cdecl nvapi_Direct_GetMethod(void *a, void *b, void *c, void *d)
{
    ensure_init();
    return real_direct ? real_direct(a, b, c, d) : NULL;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, void *reserved)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        DisableThreadLibraryCalls(instance);
        QueryPerformanceFrequency(&qpc_freq);
    }
    return TRUE;
}
