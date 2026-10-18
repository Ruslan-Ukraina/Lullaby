/* Thread waiting under Wine: how long a wake takes, and how many a second.
 *
 * Five cases, each a stand-in for what a game does all frame long:
 *   pingpong  two threads hand a token back and forth over two events: round trip
 *   multi     WaitForMultipleObjects(any) over 16 events, one of them signalled: round trip
 *   waitall   WaitForMultipleObjects(all) over 4 events: round trip
 *   sema      one thread releases a semaphore, another takes it: operations a second
 *   mutex     4 threads lock and release one mutex around a little work: operations a second
 *
 * A line a case: name,ops_per_s,p50_us,p99_us,p999_us,n. The latency columns are the
 * round trip (two wakes) except for sema and mutex, which fill only ops_per_s.
 * Which sync backend runs is the engine's: WINEMSYNC=1, WINEWFUSYNC=1, or neither (the
 * wineserver). Usage: syncbench.exe [case ...]   with no argument, all of them.
 *
 * Built for perf/syncbench.sh (x86_64-w64-mingw32-gcc -O2). Nothing here touches a game. */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static LARGE_INTEGER freq;

static double us_between(LARGE_INTEGER a, LARGE_INTEGER b)
{
    return (double)(b.QuadPart - a.QuadPart) * 1e6 / (double)freq.QuadPart;
}

static int cmp_double(const void *a, const void *b)
{
    double x = *(const double *)a, y = *(const double *)b;
    return x < y ? -1 : x > y;
}

static void report(const char *name, double secs, size_t ops, double *lat, size_t n)
{
    double p50 = 0, p99 = 0, p999 = 0;
    if (lat && n)
    {
        qsort(lat, n, sizeof(*lat), cmp_double);
        p50 = lat[n / 2];
        p99 = lat[(size_t)((double)n * 0.99)];
        p999 = lat[(size_t)((double)n * 0.999)];
    }
    printf("%s,%.0f,%.2f,%.2f,%.2f,%zu\n", name, secs > 0 ? (double)ops / secs : 0, p50, p99, p999, ops);
    fflush(stdout);
}

static void check(HANDLE h, const char *what)
{
    if (!h) { fprintf(stderr, "syncbench: %s failed (%lu)\n", what, GetLastError()); exit(2); }
}

/* ---- pingpong ---- */

#define PINGPONG_N 50000
static HANDLE pp_ab, pp_ba;

static DWORD WINAPI pp_thread(void *arg)
{
    for (int i = 0; i < PINGPONG_N; i++)
    {
        WaitForSingleObject(pp_ab, INFINITE);
        SetEvent(pp_ba);
    }
    return 0;
}

static void run_pingpong(void)
{
    static double lat[PINGPONG_N];
    LARGE_INTEGER t0, t1, start, end;
    HANDLE th;

    pp_ab = CreateEventW(NULL, FALSE, FALSE, NULL); check(pp_ab, "event");
    pp_ba = CreateEventW(NULL, FALSE, FALSE, NULL); check(pp_ba, "event");
    th = CreateThread(NULL, 0, pp_thread, NULL, 0, NULL); check(th, "thread");
    QueryPerformanceCounter(&start);
    for (int i = 0; i < PINGPONG_N; i++)
    {
        QueryPerformanceCounter(&t0);
        SetEvent(pp_ab);
        WaitForSingleObject(pp_ba, INFINITE);
        QueryPerformanceCounter(&t1);
        lat[i] = us_between(t0, t1);
    }
    QueryPerformanceCounter(&end);
    WaitForSingleObject(th, INFINITE);
    CloseHandle(th); CloseHandle(pp_ab); CloseHandle(pp_ba);
    report("pingpong", us_between(start, end) / 1e6, PINGPONG_N, lat, PINGPONG_N);
}

/* ---- multi (any) and waitall ---- */

#define MULTI_N 50000
#define WAITALL_N 30000
#define MULTI_COUNT 16
#define ALL_COUNT 4
static HANDLE mw_ev[MULTI_COUNT], mw_ack;
static int mw_count, mw_n;
static BOOL mw_all;

static DWORD WINAPI mw_thread(void *arg)
{
    for (int i = 0; i < mw_n; i++)
    {
        DWORD r = WaitForMultipleObjects(mw_count, mw_ev, mw_all, INFINITE);
        if (r >= WAIT_OBJECT_0 + (DWORD)mw_count) { fprintf(stderr, "syncbench: wait returned %lu\n", r); exit(2); }
        SetEvent(mw_ack);
    }
    return 0;
}

static void run_multi(const char *name, int count, int n, BOOL all)
{
    double *lat = malloc(sizeof(double) * (size_t)n);
    LARGE_INTEGER t0, t1, start, end;
    HANDLE th;

    mw_count = count; mw_n = n; mw_all = all;
    for (int i = 0; i < count; i++) { mw_ev[i] = CreateEventW(NULL, FALSE, FALSE, NULL); check(mw_ev[i], "event"); }
    mw_ack = CreateEventW(NULL, FALSE, FALSE, NULL); check(mw_ack, "event");
    th = CreateThread(NULL, 0, mw_thread, NULL, 0, NULL); check(th, "thread");
    QueryPerformanceCounter(&start);
    for (int i = 0; i < n; i++)
    {
        QueryPerformanceCounter(&t0);
        if (all) for (int k = 0; k < count; k++) SetEvent(mw_ev[k]);
        else SetEvent(mw_ev[i % count]);
        WaitForSingleObject(mw_ack, INFINITE);
        QueryPerformanceCounter(&t1);
        lat[i] = us_between(t0, t1);
    }
    QueryPerformanceCounter(&end);
    WaitForSingleObject(th, INFINITE);
    CloseHandle(th); CloseHandle(mw_ack);
    for (int i = 0; i < count; i++) CloseHandle(mw_ev[i]);
    report(name, us_between(start, end) / 1e6, (size_t)n, lat, (size_t)n);
    free(lat);
}

/* ---- sema ---- */

#define SEMA_N 200000
static HANDLE sem;

static DWORD WINAPI sema_consumer(void *arg)
{
    for (int i = 0; i < SEMA_N; i++) WaitForSingleObject(sem, INFINITE);
    return 0;
}

static void run_sema(void)
{
    LARGE_INTEGER start, end;
    HANDLE th;

    sem = CreateSemaphoreW(NULL, 0, SEMA_N, NULL); check(sem, "semaphore");
    th = CreateThread(NULL, 0, sema_consumer, NULL, 0, NULL); check(th, "thread");
    QueryPerformanceCounter(&start);
    for (int i = 0; i < SEMA_N; i++) ReleaseSemaphore(sem, 1, NULL);
    WaitForSingleObject(th, INFINITE);
    QueryPerformanceCounter(&end);
    CloseHandle(th); CloseHandle(sem);
    report("sema", us_between(start, end) / 1e6, SEMA_N, NULL, 0);
}

/* ---- mutex ---- */

#define MUTEX_THREADS 4
#define MUTEX_N 50000
static HANDLE mtx;
static volatile LONG guarded;

static DWORD WINAPI mutex_thread(void *arg)
{
    for (int i = 0; i < MUTEX_N; i++)
    {
        WaitForSingleObject(mtx, INFINITE);
        for (volatile int k = 0; k < 20; k++) guarded++;
        ReleaseMutex(mtx);
    }
    return 0;
}

static void run_mutex(void)
{
    HANDLE th[MUTEX_THREADS];
    LARGE_INTEGER start, end;

    mtx = CreateMutexW(NULL, FALSE, NULL); check(mtx, "mutex");
    QueryPerformanceCounter(&start);
    for (int i = 0; i < MUTEX_THREADS; i++) { th[i] = CreateThread(NULL, 0, mutex_thread, NULL, 0, NULL); check(th[i], "thread"); }
    WaitForMultipleObjects(MUTEX_THREADS, th, TRUE, INFINITE);
    QueryPerformanceCounter(&end);
    for (int i = 0; i < MUTEX_THREADS; i++) CloseHandle(th[i]);
    CloseHandle(mtx);
    report("mutex", us_between(start, end) / 1e6, (size_t)MUTEX_THREADS * MUTEX_N, NULL, 0);
}

int main(int argc, char **argv)
{
    static const struct { const char *name; void (*run)(void); } cases[] = {
        { "pingpong", run_pingpong }, { "sema", run_sema }, { "mutex", run_mutex },
    };
    BOOL want_multi, want_waitall;

    QueryPerformanceFrequency(&freq);
    want_multi = argc < 2;
    want_waitall = argc < 2;
    for (int a = 1; a < argc; a++)
    {
        if (!strcmp(argv[a], "multi")) want_multi = TRUE;
        if (!strcmp(argv[a], "waitall")) want_waitall = TRUE;
    }
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++)
    {
        BOOL run = argc < 2;
        for (int a = 1; a < argc; a++) if (!strcmp(argv[a], cases[i].name)) run = TRUE;
        if (run) cases[i].run();
    }
    if (want_multi) run_multi("multi", MULTI_COUNT, MULTI_N, FALSE);
    if (want_waitall) run_multi("waitall", ALL_COUNT, WAITALL_N, TRUE);
    return 0;
}
