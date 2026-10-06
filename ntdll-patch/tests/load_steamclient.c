/* Loads steamclient64.dll and reports what the ntdll detour did to it.
 *
 *   load_steamclient.exe            the stand-in beside this exe
 *   load_steamclient.exe <path>     any steamclient64.dll, Valve's included
 *
 * Exit status:
 *   0  CreateInterface jumps to lsteamclient.dll's CreateInterface, and for the
 *      stand-in its DllMain was not called (the detour's whole job);
 *   1  steamclient64.dll loaded untouched (no detour);
 *   2  something in between, or the load failed.
 * Valve's DLL has no fake_dllmain_calls export, so for it only the jump and
 * lsteamclient's presence are judged. */
#include <windows.h>
#include <stdio.h>
#include <string.h>

int wmain(int argc, WCHAR **argv)
{
    HMODULE sc, lsc;
    unsigned char *entry;
    void *target = NULL, *wanted = NULL;
    volatile LONG *calls;
    int redirected;

    const WCHAR *name = argc > 1 ? argv[1] : L"steamclient64.dll";

    sc = LoadLibraryW(name);
    if (!sc) { printf("LoadLibrary(%ls) failed: %lu\n", name, GetLastError()); return 2; }
    entry = (unsigned char *)GetProcAddress(sc, "CreateInterface");
    calls = (volatile LONG *)GetProcAddress(sc, "fake_dllmain_calls");
    if (!entry) { printf("%ls exports no CreateInterface\n", name); return 2; }

    /* setup_trampolines writes movabs rax, <target> ; jmp rax */
    redirected = entry[0] == 0x48 && entry[1] == 0xB8 && entry[10] == 0xFF && entry[11] == 0xE0;
    if (redirected) memcpy(&target, entry + 2, sizeof(target));

    lsc = GetModuleHandleW(L"lsteamclient.dll");
    if (lsc) wanted = (void *)GetProcAddress(lsc, "CreateInterface");

    printf("steamclient64.dll at %p, CreateInterface at %p\n", (void *)sc, (void *)entry);
    printf("first bytes: %02x %02x .. %02x %02x\n", entry[0], entry[1], entry[10], entry[11]);
    printf("lsteamclient.dll %s at %p, its CreateInterface at %p\n",
           lsc ? "loaded" : "NOT loaded", (void *)lsc, wanted);
    if (calls) printf("trampoline target %p, stand-in DllMain ran %ld time(s)\n", target, (long)*calls);
    else printf("trampoline target %p, not the stand-in so DllMain is not counted\n", target);

    if (redirected && lsc && target == wanted && (!calls || *calls == 0))
    {
        printf("RESULT: redirected to lsteamclient%s\n", calls ? ", DllMain suppressed" : "");
        return 0;
    }
    if (!redirected && !lsc && (!calls || *calls == 1))
    {
        printf("RESULT: not redirected, steamclient64.dll loaded as is\n");
        return 1;
    }
    printf("RESULT: inconsistent\n");
    return 2;
}
