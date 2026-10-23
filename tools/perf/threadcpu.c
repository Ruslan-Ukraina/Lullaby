/* Where a process spends its processor time, thread by thread, from outside.
 *
 * Reads the kernel's per-thread counters through libproc (no task port, no entitlement,
 * no symbols: it works on a process that runs under Rosetta, where `sample` shows only
 * "<unknown binary>"). Two readings an interval apart give each thread's share of one
 * core; the threads are grouped by name, the way Wine, D3DMetal and Metal name them.
 *
 *   threadcpu [--seconds N] [--interval S] [--csv FILE] [--label NAME] PID...
 *
 * Prints one line a group (cpu% of one core, averaged over the run) and, with --csv, one
 * row a group: label,pid,group,threads,cpu_pct. Nothing is written to the process.
 * Build: clang -O2 -o out/threadcpu tools/perf/threadcpu.c */

#include <libproc.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define MAX_THREADS 2048
#define MAX_GROUPS 64

struct reading { uint64_t tid; uint64_t ns; char name[64]; };

static uint64_t now_ns(void)
{
    return clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
}

static int read_threads(pid_t pid, struct reading *out, int max)
{
    uint64_t ids[MAX_THREADS];
    int bytes = proc_pidinfo(pid, PROC_PIDLISTTHREADS, 0, ids, sizeof(ids));
    if (bytes <= 0) return -1;
    int n = 0, count = bytes / (int)sizeof(uint64_t);
    for (int i = 0; i < count && n < max; i++)
    {
        struct proc_threadinfo info;
        if (proc_pidinfo(pid, PROC_PIDTHREADINFO, ids[i], &info, sizeof(info)) != (int)sizeof(info))
            continue;
        out[n].tid = ids[i];
        out[n].ns = info.pth_user_time + info.pth_system_time;
        strlcpy(out[n].name, info.pth_name, sizeof(out[n].name));
        n++;
    }
    return n;
}

/* A thread's group: its name with the numbers and addresses taken out, so that
 * "QueueWorker for 0x7f99ff8dec68" and the next one are one group. */
static void group_of(const char *name, char *out, size_t size)
{
    size_t o = 0;
    if (!*name) { strlcpy(out, "(unnamed)", size); return; }
    for (const char *p = name; *p && o + 1 < size; p++)
    {
        if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X'))
        {
            p += 2;
            while ((*p >= '0' && *p <= '9') || (*p >= 'a' && *p <= 'f') || (*p >= 'A' && *p <= 'F')) p++;
            p--;
            if (o + 1 < size) out[o++] = '#';
            continue;
        }
        if (*p >= '0' && *p <= '9')
        {
            while (p[1] >= '0' && p[1] <= '9') p++;
            if (o + 1 < size) out[o++] = '#';
            continue;
        }
        out[o++] = *p;
    }
    out[o] = 0;
}

struct group { char name[64]; int threads; double cpu_ns; };

static int by_cpu(const void *a, const void *b)
{
    double x = ((const struct group *)a)->cpu_ns, y = ((const struct group *)b)->cpu_ns;
    return x < y ? 1 : x > y ? -1 : 0;
}

static int find_group(struct group *g, int *count, const char *name)
{
    for (int i = 0; i < *count; i++) if (!strcmp(g[i].name, name)) return i;
    if (*count >= MAX_GROUPS) return MAX_GROUPS - 1;
    strlcpy(g[*count].name, name, sizeof(g[*count].name));
    return (*count)++;
}

int main(int argc, char **argv)
{
    double seconds = 10, interval = 1;
    const char *csv = NULL, *label = "";
    pid_t pids[64];
    int npids = 0;

    for (int i = 1; i < argc; i++)
    {
        if (!strcmp(argv[i], "--seconds") && i + 1 < argc) seconds = atof(argv[++i]);
        else if (!strcmp(argv[i], "--interval") && i + 1 < argc) interval = atof(argv[++i]);
        else if (!strcmp(argv[i], "--csv") && i + 1 < argc) csv = argv[++i];
        else if (!strcmp(argv[i], "--label") && i + 1 < argc) label = argv[++i];
        else if (npids < 64 && atoi(argv[i]) > 0) pids[npids++] = (pid_t)atoi(argv[i]);
        else { fprintf(stderr, "threadcpu: unknown argument %s\n", argv[i]); return 2; }
    }
    if (!npids) { fprintf(stderr, "usage: threadcpu [--seconds N] [--interval S] [--csv FILE] [--label NAME] PID...\n"); return 2; }

    static struct reading prev[MAX_THREADS], cur[MAX_THREADS];
    FILE *out = csv ? fopen(csv, "a") : NULL;
    if (csv && !out) { perror("threadcpu: csv"); return 1; }
    if (out) { fseek(out, 0, SEEK_END); if (ftell(out) == 0) fprintf(out, "label,pid,group,threads,cpu_pct\n"); }

    for (int p = 0; p < npids; p++)
    {
        struct group groups[MAX_GROUPS];
        int ngroups = 0;
        memset(groups, 0, sizeof(groups));
        int np = read_threads(pids[p], prev, MAX_THREADS);
        if (np < 0) { fprintf(stderr, "threadcpu: pid %d: cannot read threads\n", pids[p]); continue; }
        uint64_t t_start = now_ns(), t_prev = t_start;
        double total_ns = 0;
        int peak_threads = np;

        while ((double)(now_ns() - t_start) < seconds * 1e9)
        {
            usleep((useconds_t)(interval * 1e6));
            int nc = read_threads(pids[p], cur, MAX_THREADS);
            if (nc < 0)
            {
                fprintf(stderr, "threadcpu: pid %d: gone or unreadable after %.1f s\n", pids[p], (double)(now_ns() - t_start) / 1e9);
                break;
            }
            peak_threads = nc > peak_threads ? nc : peak_threads;
            for (int i = 0; i < nc; i++)
            {
                uint64_t before = 0;
                for (int j = 0; j < np; j++) if (prev[j].tid == cur[i].tid) { before = prev[j].ns; break; }
                if (!before) continue; /* a thread born in this interval: counted from the next */
                char g[64];
                group_of(cur[i].name, g, sizeof(g));
                int gi = find_group(groups, &ngroups, g);
                double delta = cur[i].ns >= before ? (double)(cur[i].ns - before) : 0;
                groups[gi].cpu_ns += delta;
                total_ns += delta;
            }
            /* threads per group: from the latest reading */
            for (int i = 0; i < ngroups; i++) groups[i].threads = 0;
            for (int i = 0; i < nc; i++)
            {
                char g[64];
                group_of(cur[i].name, g, sizeof(g));
                groups[find_group(groups, &ngroups, g)].threads++;
            }
            memcpy(prev, cur, sizeof(cur[0]) * (size_t)nc);
            np = nc;
            t_prev = now_ns();
        }
        double wall = (double)(t_prev - t_start);
        if (wall <= 0) continue;
        printf("pid %d: %d threads (peak %d), %.0f%% of one core over %.1f s\n", pids[p], np, peak_threads,
               total_ns / wall * 100, wall / 1e9);
        qsort(groups, (size_t)ngroups, sizeof(groups[0]), by_cpu);
        for (int i = 0; i < ngroups; i++)
        {
            double pct = groups[i].cpu_ns / wall * 100;
            printf("  %-34s %3d threads  %6.1f%%\n", groups[i].name, groups[i].threads, pct);
            if (out) fprintf(out, "%s,%d,\"%s\",%d,%.2f\n", label, pids[p], groups[i].name, groups[i].threads, pct);
        }
    }
    if (out) fclose(out);
    return 0;
}
