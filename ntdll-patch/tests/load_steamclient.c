/* Loads steamclient64.dll from beside this exe and reports what the ntdll detour
 * did to it. Exit status:
 *   0  CreateInterface jumps to lsteamclient.dll's CreateInterface and the
 *      module's DllMain was not called (the detour's whole job);
 *   1  steamclient64.dll loaded untouched (no detour);
 *   2  something in between, or the load failed. */
#include <windows.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    HMODULE sc, lsc;
    unsigned char *entry;
    void *target = NULL, *wanted = NULL;
    volatile LONG *calls;
    int redirected;

    sc = LoadLibraryW(L"steamclient64.dll");
    if (!sc) { printf("LoadLibrary(steamclient64.dll) failed: %lu\n", GetLastError()); return 2; }
    entry = (unsigned char *)GetProcAddress(sc, "CreateInterface");
    calls = (volatile LONG *)GetProcAddress(sc, "fake_dllmain_calls");
    if (!entry || !calls) { printf("the stand-in exports are missing\n"); return 2; }

    /* setup_trampolines writes movabs rax, <target> ; jmp rax */
    redirected = entry[0] == 0x48 && entry[1] == 0xB8 && entry[10] == 0xFF && entry[11] == 0xE0;
    if (redirected) memcpy(&target, entry + 2, sizeof(target));

    lsc = GetModuleHandleW(L"lsteamclient.dll");
    if (lsc) wanted = (void *)GetProcAddress(lsc, "CreateInterface");

    printf("steamclient64.dll at %p, CreateInterface at %p\n", (void *)sc, (void *)entry);
    printf("first bytes: %02x %02x .. %02x %02x\n", entry[0], entry[1], entry[10], entry[11]);
    printf("lsteamclient.dll %s at %p, its CreateInterface at %p\n",
           lsc ? "loaded" : "NOT loaded", (void *)lsc, wanted);
    printf("trampoline target %p, stand-in DllMain ran %ld time(s)\n", target, (long)*calls);

    if (redirected && lsc && target == wanted && *calls == 0)
    {
        printf("RESULT: redirected to lsteamclient, DllMain suppressed\n");
        return 0;
    }
    if (!redirected && !lsc && *calls == 1)
    {
        printf("RESULT: not redirected, steamclient64.dll loaded as is\n");
        return 1;
    }
    printf("RESULT: inconsistent\n");
    return 2;
}
