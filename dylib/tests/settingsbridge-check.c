// The Steam panel's channel (settingsbridge.c), hermetically: the token, the paths it
// answers, base64url, the token in the chunk, and the CLI run as it is in Steam Helper,
// with stand-in CLIs for an answer, a missing program, garbage and a hang.
#include "feats/settingsbridge.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int failed;
#define CHECK(cond, what) do { if (!(cond)) { failed++; printf("  FAIL  %s\n", what); } } while (0)

static void write_cli(const char *path, const char *body) {
    FILE *f = fopen(path, "w");
    fprintf(f, "#!/bin/sh\n%s\n", body);
    fclose(f);
    chmod(path, 0755);
}

static const char *b64url(const char *text, char *out) {
    static const char *abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    size_t len = strlen(text), o = 0;
    for (size_t i = 0; i < len; i += 3) {
        unsigned v = (unsigned char)text[i] << 16;
        if (i + 1 < len) v |= (unsigned char)text[i + 1] << 8;
        if (i + 2 < len) v |= (unsigned char)text[i + 2];
        out[o++] = abc[(v >> 18) & 63];
        out[o++] = abc[(v >> 12) & 63];
        if (i + 1 < len) out[o++] = abc[(v >> 6) & 63];
        if (i + 2 < len) out[o++] = abc[v & 63];
    }
    out[o] = '\0';
    return out;
}

static char *ask(const char *token, const char *nonce, const char *request, const char *cli) {
    char enc[4096], rest[8192];
    snprintf(rest, sizeof(rest), "notproton-settings/%s/%s/%s.json", token, nonce, b64url(request, enc));
    size_t len = 0;
    return np_settings_answer(rest, np_settings_token(), cli, &len);
}

int main(void) {
    const char *token = np_settings_token();
    CHECK(strlen(token) == NP_SETTINGS_TOKEN_LEN, "token is 32 characters");
    CHECK(strspn(token, "0123456789abcdef") == NP_SETTINGS_TOKEN_LEN, "token is hex");
    CHECK(np_settings_token() == token, "one token per process");

    CHECK(np_settings_should_serve("/S/Steam.AppBundle/Steam/Contents/MacOS/steamui/notproton-settings/x/y/z.json"),
          "a steamui settings path is served");
    CHECK(!np_settings_should_serve("/S/steamui/library.js"), "the chunk is not");
    CHECK(!np_settings_should_serve("/tmp/notproton-settings/x/y.json"), "a path outside steamui is not");
    CHECK(!np_settings_should_serve(NULL), "no path is not");

    size_t n = 0;
    uint8_t *raw = np_base64url_decode("eyJvcCI6InN0YXRlIn0", 19, &n);
    CHECK(raw && n == 14 && memcmp(raw, "{\"op\":\"state\"}", 14) == 0, "base64url decodes");
    free(raw);
    CHECK(np_base64url_decode("ab+c", 4, &n) == NULL, "standard base64 characters are refused");
    CHECK(np_base64url_decode("a", 1, &n) == NULL, "a truncated input is refused");

    const char *chunk = "x=\"__NP_SETTINGS_TOKEN__\";y=\"__NP_SETTINGS_TOKEN__\"";
    size_t out_len = 0;
    char *keyed = np_settings_inject_token(chunk, strlen(chunk), "abc", &out_len);
    CHECK(keyed && strcmp(keyed, "x=\"abc\";y=\"abc\"") == 0 && out_len == 15, "the token replaces every placeholder");
    free(keyed);
    CHECK(np_settings_inject_token("plain", 5, "abc", &out_len) == NULL, "a chunk without placeholder is left alone");

    char dir[] = "/tmp/settingsbridge.XXXXXX";
    if (!mkdtemp(dir)) { perror("mkdtemp"); return 1; }
    char echo_cli[256], junk_cli[256], hang_cli[256], missing[256];
    snprintf(echo_cli, sizeof(echo_cli), "%s/echo", dir);
    snprintf(junk_cli, sizeof(junk_cli), "%s/junk", dir);
    snprintf(hang_cli, sizeof(hang_cli), "%s/hang", dir);
    snprintf(missing, sizeof(missing), "%s/missing", dir);
    write_cli(echo_cli, "[ \"$1\" = panel ] || exit 9\nprintf '{\"ok\":true,\"got\":%s}\\n' \"$2\"");
    write_cli(junk_cli, "echo not json");
    write_cli(hang_cli, "sleep 30");

    char *answer = ask(token, "1", "{\"op\":\"set\",\"app\":3527290,\"id\":\"fps\",\"value\":true}", echo_cli);
    CHECK(answer && strcmp(answer, "{\"ok\":true,\"got\":{\"op\":\"set\",\"app\":3527290,\"id\":\"fps\",\"value\":true}}") == 0,
          "a request reaches the CLI as one argument and its answer comes back");
    free(answer);

    answer = ask("0123456789abcdef0123456789abcdef", "1", "{\"op\":\"state\"}", echo_cli);
    CHECK(answer && strstr(answer, "\"refused\""), "a wrong token is refused");
    free(answer);

    size_t len = 0;
    answer = np_settings_answer("notproton-settings/short/1/e30.json", token, echo_cli, &len);
    CHECK(answer && strstr(answer, "\"refused\""), "a short token is refused");
    free(answer);

    char rest[256];
    snprintf(rest, sizeof(rest), "notproton-settings/%s/1/e30.txt", token);
    answer = np_settings_answer(rest, token, echo_cli, &len);
    CHECK(answer && strstr(answer, "malformed"), "a request must end in .json");
    free(answer);
    snprintf(rest, sizeof(rest), "notproton-settings/%s/1/AA.json", token);
    answer = np_settings_answer(rest, token, echo_cli, &len);
    CHECK(answer && strstr(answer, "malformed"), "a request with a NUL byte is refused");
    free(answer);

    answer = ask(token, "2", "{\"op\":\"state\"}", missing);
    CHECK(answer && strstr(answer, "not installed"), "a missing CLI is reported");
    free(answer);
    answer = ask(token, "3", "{\"op\":\"state\"}", junk_cli);
    CHECK(answer && strstr(answer, "no answer"), "an answer that is not JSON is reported");
    free(answer);

    np_settings_timeout_ms = 300;
    answer = ask(token, "4", "{\"op\":\"state\"}", hang_cli);
    CHECK(answer && strstr(answer, "timed out"), "a CLI that hangs is stopped");
    free(answer);

    char cmd[600];
    snprintf(cmd, sizeof(cmd), "rm -rf '%s'", dir);
    if (system(cmd) != 0) printf("  note: could not remove %s\n", dir);

    if (failed) { printf("settingsbridge-check: %d failed\n", failed); return 1; }
    printf("==> settingsbridge-check: the panel's requests reach notproton-settings only with this process's token\n");
    return 0;
}
