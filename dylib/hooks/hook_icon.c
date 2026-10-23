// Icon logic for non-Steam shortcuts
#include "hooks.h"
#include "../util/log.h"
#include "../util/peicon.h"

#include <dlfcn.h>
#include <limits.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#define LB_ICON_MAX_SIDE 4096

typedef void *(*lb_icon_render_fn)(const char *const *path_slot, int size);

static lb_icon_render_fn g_render_orig;

typedef struct { double x, y; } lb_pt_t;
typedef struct { double w, h; } lb_sz_t;
typedef struct { lb_pt_t origin; lb_sz_t size; } lb_rect_t;

typedef void *(*msg_0_t)(void *, void *);
typedef void *(*msg_id_t)(void *, void *, void *);
typedef void *(*msg_bytes_t)(void *, void *, void *, unsigned long, signed char);
typedef void  (*msg_long_t)(void *, void *, long);
typedef void  (*msg_size_t)(void *, void *, lb_sz_t);
typedef void  (*msg_draw_t)(void *, void *, lb_rect_t, lb_rect_t, unsigned long, double);
typedef void *(*msg_rep_t)(void *, void *, unsigned char **, long, long, long, long,
                           signed char, signed char, void *, long, long);

static void *(*lb_get_class)(const char *);
static void *(*lb_sel)(const char *);
static void  *g_msg_send;
static void  (*lb_release)(void *);
static void *(*lb_pool_push)(void);
static void  (*lb_pool_pop)(void *);
static void  *g_device_rgb;

static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static char           *g_cache_path;
static void           *g_cache_ico;
static size_t          g_cache_len;
static long            g_cache_mtime;
static long long       g_cache_size;

static pthread_once_t g_runtime_once = PTHREAD_ONCE_INIT;
static int            g_runtime_ok;

static void runtime_init(void) {
    lb_get_class = (void *(*)(const char *))dlsym(RTLD_DEFAULT, "objc_getClass");
    lb_sel       = (void *(*)(const char *))dlsym(RTLD_DEFAULT, "sel_registerName");
    g_msg_send   = dlsym(RTLD_DEFAULT, "objc_msgSend");
    lb_release   = (void (*)(void *))dlsym(RTLD_DEFAULT, "objc_release");
    lb_pool_push = (void *(*)(void))dlsym(RTLD_DEFAULT, "objc_autoreleasePoolPush");
    lb_pool_pop  = (void (*)(void *))dlsym(RTLD_DEFAULT, "objc_autoreleasePoolPop");

    void **rgb = (void **)dlsym(RTLD_DEFAULT, "NSDeviceRGBColorSpace");
    if (rgb) g_device_rgb = *rgb;

    g_runtime_ok = lb_get_class && lb_sel && g_msg_send && lb_release &&
                   lb_pool_push && lb_pool_pop && g_device_rgb;
    if (!g_runtime_ok) LB_WARN("icon: AppKit runtime unavailable, leaving icons to Steam");
}

static int runtime_ready(void) {
    pthread_once(&g_runtime_once, runtime_init);
    return g_runtime_ok;
}

static void *ico_copy_for_path(const char *path, size_t *out_len) {
    struct stat st;
    char unquoted[PATH_MAX];

    if (!path || !*path) return NULL;

    size_t len = strlen(path);
    if (len >= 2 && path[0] == '"' && path[len - 1] == '"') {
        if (len - 2 >= sizeof(unquoted)) return NULL;
        memcpy(unquoted, path + 1, len - 2);
        unquoted[len - 2] = '\0';
        path = unquoted;
    }

    if (stat(path, &st) != 0 || !S_ISREG(st.st_mode)) return NULL;

    pthread_mutex_lock(&g_lock);

    int hit = g_cache_ico && g_cache_path &&
              strcmp(g_cache_path, path) == 0 &&
              g_cache_mtime == (long)st.st_mtime &&
              g_cache_size == (long long)st.st_size;

    if (!hit) {
        pthread_mutex_unlock(&g_lock);

        size_t len = 0;
        void  *ico = lb_pe_icon_ico(path, &len);
        if (!ico) return NULL;
        char *dup = strdup(path);
        LB_LOG("icon: read an icon out of '%s'", path);

        pthread_mutex_lock(&g_lock);
        free(g_cache_ico);
        free(g_cache_path);
        g_cache_ico   = ico;
        g_cache_len   = len;
        g_cache_path  = dup;
        g_cache_mtime = (long)st.st_mtime;
        g_cache_size  = (long long)st.st_size;
    }

    void *copy = NULL;
    if (g_cache_len) {
        copy = malloc(g_cache_len);
        if (copy) {
            memcpy(copy, g_cache_ico, g_cache_len);
            *out_len = g_cache_len;
        }
    }
    pthread_mutex_unlock(&g_lock);
    return copy;
}

static void *render(void *bytes, size_t len, int side) {
    void *pool = lb_pool_push();

    void *data = ((msg_bytes_t)g_msg_send)(
        lb_get_class("NSData"),
        lb_sel("dataWithBytesNoCopy:length:freeWhenDone:"),
        bytes, (unsigned long)len, 1);

    if (!data) {
        free(bytes);
        lb_pool_pop(pool);
        return NULL;
    }

    void *img = ((msg_id_t)g_msg_send)(
        ((msg_0_t)g_msg_send)(lb_get_class("NSImage"), lb_sel("alloc")),
        lb_sel("initWithData:"), data);
    if (!img) {
        lb_pool_pop(pool);
        return NULL;
    }

    void *rep = ((msg_rep_t)g_msg_send)(
        ((msg_0_t)g_msg_send)(lb_get_class("NSBitmapImageRep"), lb_sel("alloc")),
        lb_sel("initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:"
               "samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bytesPerRow:"
               "bitsPerPixel:"),
        NULL, side, side, 8, 4, 1, 0, g_device_rgb, 4L * side, 32);

    if (!rep) {
        lb_release(img);
        lb_pool_pop(pool);
        return NULL;
    }

    void *gc  = lb_get_class("NSGraphicsContext");
    void *ctx = ((msg_id_t)g_msg_send)(gc, lb_sel("graphicsContextWithBitmapImageRep:"), rep);
    if (!ctx) {
        lb_release(img);
        lb_release(rep);
        lb_pool_pop(pool);
        return NULL;
    }

    ((msg_long_t)g_msg_send)(ctx, lb_sel("setImageInterpolation:"), 2);
    ((msg_0_t)g_msg_send)(gc, lb_sel("saveGraphicsState"));
    ((msg_id_t)g_msg_send)(gc, lb_sel("setCurrentContext:"), ctx);

    lb_sz_t   size = { (double)side, (double)side };
    lb_rect_t dst  = { { 0.0, 0.0 }, { (double)side, (double)side } };
    lb_rect_t src  = { { 0.0, 0.0 }, { 0.0, 0.0 } };

    ((msg_size_t)g_msg_send)(img, lb_sel("setSize:"), size);
    ((msg_draw_t)g_msg_send)(img, lb_sel("drawInRect:fromRect:operation:fraction:"),
                             dst, src, 1, 1.0);

    ((msg_0_t)g_msg_send)(gc, lb_sel("restoreGraphicsState"));

    lb_release(img);
    lb_pool_pop(pool);
    return rep;
}

static void *lb_icon_render(const char *const *path_slot, int side) {
    const char *path = path_slot ? *path_slot : NULL;

    if (side <= 0 || side > LB_ICON_MAX_SIDE || !path || !runtime_ready())
        return g_render_orig ? g_render_orig(path_slot, side) : NULL;

    size_t len   = 0;
    void  *bytes = ico_copy_for_path(path, &len);
    if (!bytes)
        return g_render_orig ? g_render_orig(path_slot, side) : NULL;

    void *rep = render(bytes, len, side);
    if (!rep)
        return g_render_orig ? g_render_orig(path_slot, side) : NULL;

    return rep;
}

static lb_patch_entry_t g_hooks[] = {
    {
        .label            = "shortcut-icon",
        .signature        = "steamui::ShortcutIconRender",
        .entry            = (void *)lb_icon_render,
        .trampoline       = (void **)&g_render_orig,
        .tolerate_missing = 1,
        .mode             = LB_PATCH_REPLACE,
    },
};

int lb_hooks_icon_count(void) {
    return (int)(sizeof(g_hooks) / sizeof(g_hooks[0]));
}

lb_patch_entry_t *lb_hooks_icon_defs(void) {
    return g_hooks;
}
