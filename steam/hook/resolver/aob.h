// AOB pattern scanner
#ifndef LULLABY_RESOLVER_AOB_H
#define LULLABY_RESOLVER_AOB_H

#include <stdint.h>
#include <stddef.h>

// A compiled byte pattern with per-byte mask (0xFF = match, 0x00 = wildcard).
typedef struct {
    uint8_t *bytes;
    uint8_t *mask;
    int      length;
} lb_byte_pattern_t;

// Hex string like "AB ?? CD 01" into a compiled pattern.
int lb_compile_pattern(const char *hex_str, lb_byte_pattern_t *out);

void lb_release_pattern(lb_byte_pattern_t *pat);

// The sole match of `pat` in `size` bytes at `base`, or 0 when zero or
// multiple matches exist.
uintptr_t lb_scan_sole_match(uintptr_t base, size_t size, const lb_byte_pattern_t *pat);

#endif // LULLABY_RESOLVER_AOB_H
