/* Asks the running Steam client, through steamclient(64).dll -> lsteamclient (B1),
 * for the interfaces add-interfaces.py adds, and calls only methods that read:
 * SteamNetworkingSocketsSerialized005 GetCachedRelayTicketCount and GetSTUNServer
 * (the first of the three methods 005 adds), and SteamAppDisableUpdate001
 * SetAppUpdateDisabledSecondsRemaining(0), which tells Steam that updating is fine.
 * No app id is set, so the account shows no game. The exit code counts FAILs. */
#include <windows.h>
#include <stdio.h>
#include <string.h>

#ifdef _WIN64
#define THISCALL
#else
#define THISCALL __attribute__((thiscall))
#endif

typedef void *(*create_interface_t)(const char *, int *);
typedef int (THISCALL *create_pipe_t)(void *);
typedef int (THISCALL *release_pipe_t)(void *, int);
typedef int (THISCALL *connect_user_t)(void *, int);
typedef void (THISCALL *release_user_t)(void *, int, int);
typedef void *(THISCALL *generic_iface_t)(void *, int, int, const char *);
typedef unsigned (THISCALL *ticket_count_t)(void *);
typedef int (THISCALL *stun_server_t)(void *, int, char *, unsigned);
typedef void (THISCALL *disable_update_t)(void *, unsigned);

static int failures;
static void check(int ok, const char *what)
{
    printf("%s %s\n", ok ? "OK  " : "FAIL", what);
    if (!ok) failures++;
}
static void *slot(void *iface, int i) { return (*(void ***)iface)[i]; }

int main(void)
{
#ifdef _WIN64
    HMODULE sc = LoadLibraryA("steamclient64.dll");
#else
    HMODULE sc = LoadLibraryA("steamclient.dll");
#endif
    create_interface_t create;
    void *client, *ser, *adu;
    int pipe, user;
    char line[512], stun[256];

    check(sc != NULL, "steamclient loads");
    if (!sc) return failures;
    create = (create_interface_t)GetProcAddress(sc, "CreateInterface");
    client = create ? create("SteamClient020", NULL) : NULL;
    check(client != NULL, "SteamClient020 created");
    if (!client) return failures;

    pipe = ((create_pipe_t)slot(client, 0))(client);
    user = pipe ? ((connect_user_t)slot(client, 2))(client, pipe) : 0;
    snprintf(line, sizeof(line), "connected to the running Steam client (pipe %d, user %d)", pipe, user);
    check(pipe && user, line);
    if (!pipe || !user) return failures;

    ser = ((generic_iface_t)slot(client, 12))(client, user, pipe, "SteamNetworkingSocketsSerialized005");
    check(ser != NULL, "SteamNetworkingSocketsSerialized005 created");
    if (ser)
    {
        unsigned count = ((ticket_count_t)slot(ser, 5))(ser);
        int ok;
        snprintf(line, sizeof(line), "005 slot 5 GetCachedRelayTicketCount answered (%u)", count);
        check(1, line);
        memset(stun, 0, sizeof(stun));
        ok = ((stun_server_t)slot(ser, 8))(ser, 0, stun, sizeof(stun)) & 0xff;
        snprintf(line, sizeof(line), "005 slot 8 GetSTUNServer answered (%d, \"%.200s\")", ok, stun);
        check(1, line);
    }

    adu = ((generic_iface_t)slot(client, 12))(client, user, pipe, "SteamAppDisableUpdate001");
    check(adu != NULL, "SteamAppDisableUpdate001 created");
    if (adu)
    {
        ((disable_update_t)slot(adu, 0))(adu, 0);
        check(1, "SteamAppDisableUpdate001 SetAppUpdateDisabledSecondsRemaining(0) returned");
    }

    ((release_user_t)slot(client, 4))(client, pipe, user);
    ((release_pipe_t)slot(client, 1))(client, pipe);
    return failures;
}
