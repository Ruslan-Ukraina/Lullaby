#ifndef LULLABY_CORE_MACHO_H
#define LULLABY_CORE_MACHO_H

#include <stdint.h>
#include <stddef.h>
#include <mach-o/loader.h>

int lb_await_image(const char *name, int timeout_ms,
                         const struct mach_header_64 **out_mh, intptr_t *out_slide,
                         char *out_path, size_t path_size);

void lb_await_stop(void);

int lb_find_segment(const struct mach_header_64 *mh, intptr_t slide,
                   const char *segname, uintptr_t *out_base, size_t *out_size);

int lb_get_section_containing(const struct mach_header_64 *mh, intptr_t slide,
                              uintptr_t addr, uintptr_t *out_base,
                              size_t *out_size);

int lb_function_bounds(const struct mach_header_64 *mh, intptr_t slide,
                       uintptr_t addr, uintptr_t *out_start, uintptr_t *out_end);

int lb_find_section(const struct mach_header_64 *mh, intptr_t slide,
                    const char *segname, const char *sectname,
                    uintptr_t *out_base, size_t *out_size);

// The indirect symbol table maps __stubs entries to imports.
const char *lb_import_stub_symbol(const struct mach_header_64 *mh, intptr_t slide,
                                  uintptr_t stub);

uintptr_t lb_import_stub_for_symbol(const struct mach_header_64 *mh, intptr_t slide,
                                    const char *symbol);

int lb_rebind_import(const struct mach_header_64 *mh, intptr_t slide,
                     const char *symbol, void *replacement);

#endif // LULLABY_CORE_MACHO_H
