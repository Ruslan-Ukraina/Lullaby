// File/Path Helpers.
#ifndef LULLABY_UTIL_FILE_H
#define LULLABY_UTIL_FILE_H

#include <stdint.h>
#include <stddef.h>

// Caller owns the returned buffer. Refuses anything over 16 MB.
uint8_t *lb_read_whole_file(const char *path, size_t *out_len);

const char *lb_home_dir(void);

void lb_support_path(char *buf, size_t bufsz, const char *home, const char *rel);

#endif // LULLABY_UTIL_FILE_H
