// The Steam panel's channel to Lullaby's settings. See settingsbridge.h.
#include "settingsbridge.h"
#include "../util/file.h"
#include "../util/log.h"

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

#define NP_SETTINGS_DIR        "lullaby-settings/"
#define NP_SETTINGS_MAX_REQ    (64 * 1024)
#define NP_SETTINGS_MAX_ANSWER (4 * 1024 * 1024)

int np_settings_timeout_ms = 15000;

static char g_token[NP_SETTINGS_TOKEN_LEN + 1];
static pthread_once_t g_token_once = PTHREAD_ONCE_INIT;

static void make_token(void) {
    uint8_t raw[NP_SETTINGS_TOKEN_LEN / 2];
    arc4random_buf(raw, sizeof(raw));
    for (size_t i = 0; i < sizeof(raw); i++)
        snprintf(g_token + 2 * i, 3, "%02x", raw[i]);
}

const char *np_settings_token(void) {
    pthread_once(&g_token_once, make_token);
    return g_token;
}

static const char *steamui_rest(const char *path) {
    const char *at = strstr(path, "/steamui/");
    if (at)
        return at + sizeof("/steamui/") - 1;
    if (strncmp(path, "steamui/", sizeof("steamui/") - 1) == 0)
        return path + sizeof("steamui/") - 1;
    return NULL;
}

int np_settings_should_serve(const char *path) {
    if (!path)
        return 0;
    const char *rest = steamui_rest(path);
    return rest && strncmp(rest, NP_SETTINGS_DIR, sizeof(NP_SETTINGS_DIR) - 1) == 0;
}

static int b64url_value(unsigned char c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '-') return 62;
    if (c == '_') return 63;
    return -1;
}

uint8_t *np_base64url_decode(const char *src, size_t len, size_t *out_len) {
    if (len % 4 == 1)
        return NULL;
    uint8_t *out = malloc(len * 3 / 4 + 3);
    if (!out)
        return NULL;
    size_t n = 0;
    uint32_t acc = 0;
    int bits = 0;
    for (size_t i = 0; i < len; i++) {
        int v = b64url_value((unsigned char)src[i]);
        if (v < 0) { free(out); return NULL; }
        acc = (acc << 6) | (uint32_t)v;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            out[n++] = (uint8_t)(acc >> bits);
        }
    }
    *out_len = n;
    return out;
}

static int same_token(const char *a, const char *b, size_t len) {
    unsigned char diff = 0;
    for (size_t i = 0; i < len; i++)
        diff |= (unsigned char)(a[i] ^ b[i]);
    return diff == 0;
}

static char *error_answer(const char *message, size_t *out_len) {
    char buf[512];
    int n = snprintf(buf, sizeof(buf), "{\"ok\":false,\"error\":\"%s\"}", message);
    if (n < 0 || (size_t)n >= sizeof(buf))
        n = (int)strlen(buf);
    char *copy = strdup(buf);
    if (copy && out_len)
        *out_len = (size_t)n;
    return copy;
}

// A request body the CLI may take as one argument: UTF-8 text without control bytes
// other than tab and newline.
static int plain_text(const uint8_t *bytes, size_t len) {
    for (size_t i = 0; i < len; i++) {
        if (bytes[i] == 0 || (bytes[i] < 0x20 && bytes[i] != '\t' && bytes[i] != '\n' && bytes[i] != '\r'))
            return 0;
    }
    return 1;
}

static long elapsed_ms(const struct timespec *since) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (now.tv_sec - since->tv_sec) * 1000 + (now.tv_nsec - since->tv_nsec) / 1000000;
}

// Runs `cli panel <request>` and collects what it prints, within the timeout.
static char *run_cli(const char *cli, const char *request, size_t *out_len) {
    int pipefd[2];
    if (pipe(pipefd) != 0)
        return error_answer("cannot reach lullaby-settings", out_len);
    fcntl(pipefd[0], F_SETFD, FD_CLOEXEC);

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], 1);
    posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addclose(&actions, pipefd[1]);

    char *argv[] = { (char *)cli, "panel", (char *)request, NULL };
    pid_t pid = 0;
    int rc = posix_spawn(&pid, cli, &actions, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    close(pipefd[1]);
    if (rc != 0) {
        close(pipefd[0]);
        NP_WARN("settings: cannot start %s (%s)", cli, strerror(rc));
        return error_answer(rc == ENOENT ? "lullaby-settings is not installed"
                                         : "lullaby-settings did not start", out_len);
    }

    size_t cap = 65536, len = 0;
    char *buf = malloc(cap);
    struct timespec start;
    clock_gettime(CLOCK_MONOTONIC, &start);
    int timed_out = 0, too_big = 0;
    while (buf) {
        long left = np_settings_timeout_ms - elapsed_ms(&start);
        if (left <= 0) { timed_out = 1; break; }
        struct pollfd pfd = { .fd = pipefd[0], .events = POLLIN };
        int ready = poll(&pfd, 1, (int)left);
        if (ready < 0 && errno == EINTR) continue;
        if (ready <= 0) { timed_out = ready == 0; break; }
        if (len + 4096 > cap) {
            if (cap >= NP_SETTINGS_MAX_ANSWER) { too_big = 1; break; }
            char *grown = realloc(buf, cap * 2);
            if (!grown) { free(buf); buf = NULL; break; }
            buf = grown;
            cap *= 2;
        }
        ssize_t got = read(pipefd[0], buf + len, cap - len - 1);
        if (got < 0 && errno == EINTR) continue;
        if (got <= 0) break;
        len += (size_t)got;
    }
    close(pipefd[0]);
    if (timed_out || too_big)
        kill(pid, SIGKILL);
    int status = 0;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}

    if (!buf)
        return error_answer("out of memory", out_len);
    if (timed_out || too_big) {
        free(buf);
        NP_WARN("settings: lullaby-settings %s", timed_out ? "timed out" : "answered too much");
        return error_answer(timed_out ? "lullaby-settings timed out" : "answer too large", out_len);
    }
    while (len && (buf[len - 1] == '\n' || buf[len - 1] == '\r'))
        len--;
    buf[len] = '\0';
    if (len == 0 || buf[0] != '{') {
        free(buf);
        NP_WARN("settings: lullaby-settings exited %d without an answer",
                WIFEXITED(status) ? WEXITSTATUS(status) : -1);
        return error_answer("lullaby-settings gave no answer", out_len);
    }
    *out_len = len;
    return buf;
}

char *np_settings_answer(const char *rest, const char *token, const char *cli, size_t *out_len) {
    if (strncmp(rest, NP_SETTINGS_DIR, sizeof(NP_SETTINGS_DIR) - 1) != 0)
        return error_answer("not a settings request", out_len);
    const char *p = rest + sizeof(NP_SETTINGS_DIR) - 1;

    // <token>/<nonce>/<payload>.json
    const char *slash = strchr(p, '/');
    if (!slash || (size_t)(slash - p) != NP_SETTINGS_TOKEN_LEN
        || !same_token(p, token, NP_SETTINGS_TOKEN_LEN))
        return error_answer("refused", out_len);
    const char *nonce = slash + 1;
    slash = strchr(nonce, '/');
    if (!slash || slash == nonce || slash - nonce > 32)
        return error_answer("malformed request", out_len);
    const char *payload = slash + 1;
    size_t plen = strlen(payload);
    if (plen < 6 || strcmp(payload + plen - 5, ".json") != 0 || strchr(payload, '/'))
        return error_answer("malformed request", out_len);
    plen -= 5;
    if (plen > NP_SETTINGS_MAX_REQ * 4 / 3 + 4)
        return error_answer("request too large", out_len);

    size_t req_len = 0;
    uint8_t *req = np_base64url_decode(payload, plen, &req_len);
    if (!req || req_len == 0 || !plain_text(req, req_len)) {
        free(req);
        return error_answer("malformed request", out_len);
    }
    char *request = malloc(req_len + 1);
    if (!request) { free(req); return error_answer("out of memory", out_len); }
    memcpy(request, req, req_len);
    request[req_len] = '\0';
    free(req);

    char *answer = run_cli(cli, request, out_len);
    free(request);
    return answer;
}

int np_settings_serve(const char *path) {
    np_log_attach();
    const char *rest = steamui_rest(path);
    if (!rest)
        return -1;
    const char *home = np_home_dir();
    if (!home)
        return -1;
    char cli[1100];
    np_support_path(cli, sizeof(cli), home, "lullaby-settings");

    size_t len = 0;
    char *answer = np_settings_answer(rest, np_settings_token(), cli, &len);
    if (!answer)
        return -1;

    char dir[1024];
    np_support_path(dir, sizeof(dir), home, NULL);
    char tmpl[1100];
    snprintf(tmpl, sizeof(tmpl), "%s/settings-answer.XXXXXX", dir);
    int fd = mkstemp(tmpl);
    if (fd < 0) { free(answer); return -1; }
    unlink(tmpl);
    for (size_t done = 0; done < len; ) {
        ssize_t n = write(fd, answer + done, len - done);
        if (n <= 0) { close(fd); free(answer); return -1; }
        done += (size_t)n;
    }
    free(answer);
    if (lseek(fd, 0, SEEK_SET) != 0) { close(fd); return -1; }
    NP_LOG_FIRST("settings: the Steam panel reached lullaby-settings (%s pid %d)", getprogname(), getpid());
    return fd;
}

char *np_settings_inject_token(const char *src, size_t len, const char *token, size_t *out_len) {
    const char *ph = NP_SETTINGS_TOKEN_PLACEHOLDER;
    size_t phlen = strlen(ph), tlen = strlen(token);
    size_t count = 0;
    for (size_t i = 0; i + phlen <= len; i++)
        if (memcmp(src + i, ph, phlen) == 0) { count++; i += phlen - 1; }
    if (count == 0)
        return NULL;
    size_t total = len + count * tlen - count * phlen;
    char *out = malloc(total + 1);
    if (!out)
        return NULL;
    size_t o = 0;
    for (size_t i = 0; i < len; ) {
        if (i + phlen <= len && memcmp(src + i, ph, phlen) == 0) {
            memcpy(out + o, token, tlen);
            o += tlen;
            i += phlen;
        } else {
            out[o++] = src[i++];
        }
    }
    out[o] = '\0';
    *out_len = o;
    return out;
}
