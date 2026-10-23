/* Loads Valve's steamclient the way a game does and checks what the B1 loader hook
 * left behind: CreateInterface and the entry point jump into lsteamclient.dll. Only
 * addresses are compared, nothing of Steam's is called, so no Steam is needed.
 *
 *   trampcheck.exe            steamclient64.dll (x86_64 build) or steamclient.dll (i386)
 * Prints one OK or FAIL line per check; the exit code is the number of FAILs. */
#include <windows.h>
#include <stdio.h>
#include <string.h>

static int failures;

static void check(int ok, const char *what)
{
    printf("%s %s\n", ok ? "OK  " : "FAIL", what);
    if (!ok) failures++;
}

/* The jump the hook writes: movabs rax, target; jmp rax  /  mov eax, target; jmp eax */
static void *jump_target(const unsigned char *code)
{
    void *target = NULL;
#ifdef _WIN64
    if (code[0] != 0x48 || code[1] != 0xb8 || code[10] != 0xff || code[11] != 0xe0) return NULL;
    memcpy(&target, code + 2, sizeof(target));
#else
    if (code[0] != 0xb8 || code[5] != 0xff || code[6] != 0xe0) return NULL;
    memcpy(&target, code + 1, sizeof(target));
#endif
    return target;
}

static void *entry_of(HMODULE mod)
{
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)((char *)mod + ((IMAGE_DOS_HEADER *)mod)->e_lfanew);
    return (char *)mod + nt->OptionalHeader.AddressOfEntryPoint;
}

int main(int argc, char **argv)
{
#ifdef _WIN64
    const char *name = argc > 1 ? argv[1] : "steamclient64.dll";
#else
    const char *name = argc > 1 ? argv[1] : "steamclient.dll";
#endif
    HMODULE sc, lsc;
    FARPROC sc_ci, lsc_ci;
    char line[256];

    sc = LoadLibraryA(name);
    snprintf(line, sizeof(line), "%s loads (error %lu)", name, sc ? 0 : GetLastError());
    check(sc != NULL, line);
    if (!sc) return failures;

    lsc = GetModuleHandleA("lsteamclient.dll");
    check(lsc != NULL, "lsteamclient.dll was loaded by the loader hook");
    if (!lsc) return failures;

    sc_ci = GetProcAddress(sc, "CreateInterface");
    lsc_ci = GetProcAddress(lsc, "CreateInterface");
    check(sc_ci && lsc_ci && jump_target((const unsigned char *)sc_ci) == (void *)lsc_ci,
          "steamclient CreateInterface jumps to lsteamclient CreateInterface");
    check(jump_target(entry_of(sc)) == entry_of(lsc),
          "steamclient entry point jumps to lsteamclient entry point");
    return failures;
}
