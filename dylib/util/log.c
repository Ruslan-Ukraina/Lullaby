// Logs
#include "log.h"
#include "file.h"
#include <stdlib.h>
#include <stdint.h>
#include <pthread.h>
#include <sys/stat.h>

int lb_log_level = LB_LVL_INFO;
FILE *lb_log_file = NULL;

#define LB_LOG_MAX_BYTES (16 * 1024 * 1024)

#define LB_SEEN_SLOTS 8192

struct lb_seen_slot {
    const void   *anchor;
    unsigned long tag;
    unsigned char filled;
};

static struct lb_seen_slot lb_seen[LB_SEEN_SLOTS];
static int lb_seen_overflow;

static unsigned long lb_seen_fold(const void *anchor, unsigned long tag) {
    unsigned long acc = 1469598103934665603UL; // FNV offset basis
    unsigned long bits = (unsigned long)(uintptr_t)anchor ^ (tag << 1);
    for (int b = 0; b < (int)sizeof(bits); b++) {
        acc ^= (bits & 0xFF);
        acc *= 1099511628211UL; // FNV prime
        bits >>= 8;
    }
    return acc;
}

int lb_log_first_hit(const void *anchor, unsigned long tag) {
    unsigned long start = lb_seen_fold(anchor, tag) % LB_SEEN_SLOTS;
    for (unsigned long step = 0; step < LB_SEEN_SLOTS; step++) {
        struct lb_seen_slot *slot = &lb_seen[(start + step) % LB_SEEN_SLOTS];
        if (slot->filled) {
            if (slot->anchor == anchor && slot->tag == tag)
                return 0; // seen before
            continue;
        }
        slot->anchor = anchor;
        slot->tag    = tag;
        slot->filled = 1;
        return 1; // first time
    }
    if (!lb_seen_overflow) {
        lb_seen_overflow = 1;
        LB_ERR("log dedupe table exhausted at %d entries; repeat lines now dropped",
               LB_SEEN_SLOTS);
    }
    return 0;
}

static void log_open(int may_rotate) {
    const char *want = getenv("LULLABY_LOG_LEVEL");
    if (want && want[0]) {
        int parsed = atoi(want);
        if (parsed >= LB_LVL_ERR && parsed <= LB_LVL_DBG)
            lb_log_level = parsed;
    }

    if (lb_log_file)
        return;

    const char *home = lb_home_dir();
    if (!home)
        home = "/tmp";

    char folder[512];
    char logpath[512];
    lb_support_path(folder, sizeof(folder), home, NULL);
    mkdir(folder, 0755);
    snprintf(logpath, sizeof(logpath), "%s/lullaby.log", folder);

    struct stat info;
    int oversize = (may_rotate && stat(logpath, &info) == 0
                    && info.st_size > LB_LOG_MAX_BYTES);
    lb_log_file = fopen(logpath, oversize ? "w" : "a");
    if (lb_log_file)
        setlinebuf(lb_log_file);
}

void lb_log_init(void) {
    log_open(1);
}

static pthread_once_t lb_attach_once = PTHREAD_ONCE_INIT;

static void log_attach_once(void) {
    log_open(0);
}

void lb_log_attach(void) {
    pthread_once(&lb_attach_once, log_attach_once);
}
