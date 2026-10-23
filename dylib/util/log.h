// Logs
#ifndef LULLABY_UTIL_LOG_H
#define LULLABY_UTIL_LOG_H

#include <stdio.h>
#include <time.h>

extern int lb_log_level;
extern FILE *lb_log_file;
void lb_log_init(void);
void lb_log_attach(void);

enum {
    LB_LVL_ERR = 0,
    LB_LVL_WARN,
    LB_LVL_INFO,
    LB_LVL_DBG,
};

#define LB_LOG_PREFIX "[lullaby]"

#define LB_EMIT(level, tag, fmt, ...) do { \
    if (lb_log_level >= (level)) { \
        time_t _now = time(NULL); \
        struct tm _cal; localtime_r(&_now, &_cal); \
        char _ts[24]; \
        strftime(_ts, sizeof(_ts), "%Y-%m-%d %H:%M:%S", &_cal); \
        FILE *_sinks[2] = { stderr, lb_log_file }; \
        for (int _s = 0; _s < 2; _s++) { \
            if (_sinks[_s]) \
                fprintf(_sinks[_s], "%s " LB_LOG_PREFIX " %s " fmt "\n", \
                        _ts, tag, ##__VA_ARGS__); \
        } \
    } \
} while(0)

#define LB_ERR(fmt, ...)  LB_EMIT(LB_LVL_ERR,  "error", fmt, ##__VA_ARGS__)
#define LB_WARN(fmt, ...) LB_EMIT(LB_LVL_WARN, "warn",  fmt, ##__VA_ARGS__)
#define LB_LOG(fmt, ...)  LB_EMIT(LB_LVL_INFO, "info",  fmt, ##__VA_ARGS__)
#define LB_DBG(fmt, ...)  LB_EMIT(LB_LVL_DBG,  "debug", fmt, ##__VA_ARGS__)

int lb_log_first_hit(const void *anchor, unsigned long tag);

#define LB_LOG_FIRST_KEY(key, fmt, ...) do { \
    static const char lb_here = 0; \
    if (lb_log_level >= LB_LVL_DBG || lb_log_first_hit(&lb_here, (unsigned long)(key))) \
        LB_LOG(fmt, ##__VA_ARGS__); \
} while(0)

#define LB_LOG_FIRST(fmt, ...) LB_LOG_FIRST_KEY(0, fmt, ##__VA_ARGS__)

#endif // LULLABY_UTIL_LOG_H
