/*
 * Copyright (c) 2015, 2019, 2020, 2021, 2022 Valve Corporation
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this
 * list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 * this list of conditions and the following disclaimer in the documentation and/or
 * other materials provided with the distribution.
 *
 * 3. Neither the name of the copyright holder nor the names of its contributors
 * may be used to endorse or promote products derived from this software without
 * specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
 * ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/* This is a stub steam.exe implementation for use inside Proton. It provides
 * a small subset of the actual Steam functionality for games that expect
 * Windows version of Steam running. */

#include "ntstatus.h"
#define WIN32_NO_STATUS
#include <windows.h>
#include <winsvc.h>
#include <winternl.h>
#include <shellapi.h>
#include <shlwapi.h>
#include <string.h>
#include <stdio.h>
#include <limits.h>
#include <string>

#pragma push_macro("_WIN32")
#pragma push_macro("__cdecl")
#pragma push_macro("strncpy")
#undef _WIN32
#undef __cdecl
#undef strncpy
#include "steam_api.h"
#pragma pop_macro("_WIN32")
#pragma pop_macro("__cdecl")
#pragma pop_macro("strncpy")

#include "wine/debug.h"

#include "wine/unixlib.h"
#include "wine/heap.h"

#include <msi.h>

WINE_DEFAULT_DEBUG_CHANNEL(steam);

/* from shlobj.h, which breaks because of DECLSPEC_IMPORT EXTERN_C in C++ */
#define CSIDL_LOCAL_APPDATA 0x001c
#define CSIDL_FLAG_CREATE   0x8000

EXTERN_C WINSHELLAPI HRESULT WINAPI SHGetFolderPathA(HWND hwnd, int nFolder, HANDLE hToken, DWORD dwFlags, LPSTR pszPath);
EXTERN_C WINSHELLAPI HRESULT WINAPI SHGetFolderPathW(HWND hwnd, int nFolder, HANDLE hToken, DWORD dwFlags, LPWSTR pszPath);
#define SHGetFolderPath WINELIB_NAME_AW(SHGetFolderPath)


static bool env_nonzero(const char *env)
{
    const char *v = getenv(env);
    return v != NULL && *v && v[0] != '0';
}

static void set_active_process_pid(void)
{
    DWORD pid = GetCurrentProcessId();
    RegSetKeyValueA(HKEY_CURRENT_USER, "Software\\Valve\\Steam\\ActiveProcess", "pid", REG_DWORD, &pid, sizeof(pid));
}

static void set_client_dll_paths(void)
{
    static const char steam_dir[] = "C:\\Program Files (x86)\\Steam\\";
    char path64[MAX_PATH];
    char path32[MAX_PATH];
    const char *universe = "Public";

    snprintf(path64, sizeof(path64), "%ssteamclient64.dll", steam_dir);
    snprintf(path32, sizeof(path32), "%ssteamclient.dll", steam_dir);

    RegSetKeyValueA(HKEY_CURRENT_USER, "Software\\Valve\\Steam\\ActiveProcess",
                    "SteamClientDll64", REG_SZ, path64, (DWORD)strlen(path64) + 1);
    RegSetKeyValueA(HKEY_CURRENT_USER, "Software\\Valve\\Steam\\ActiveProcess",
                    "SteamClientDll", REG_SZ, path32, (DWORD)strlen(path32) + 1);
    RegSetKeyValueA(HKEY_CURRENT_USER, "Software\\Valve\\Steam\\ActiveProcess",
                    "Universe", REG_SZ, universe, (DWORD)strlen(universe) + 1);
    RegSetKeyValueA(HKEY_CURRENT_USER, "Software\\Valve\\Steam",
                    "SteamPath", REG_SZ, steam_dir, (DWORD)sizeof(steam_dir));
}

/* Values Proton's wine.inf sets. Ubisoft Connect needs them to see Steam (upstream
 * NotProton 1.1.x, "Set the Steam install path registry values Ubisoft Connect checks"). */
static void set_install_paths(void)
{
    static const char install_dir[] = "C:\\Program Files (x86)\\Steam";
    static const char steam_exe[] = "C:\\Program Files (x86)\\Steam\\steam.exe";

    RegSetKeyValueA(HKEY_LOCAL_MACHINE, "Software\\Wow6432Node\\Valve\\Steam",
                    "InstallPath", REG_SZ, install_dir, (DWORD)sizeof(install_dir));
    RegSetKeyValueA(HKEY_LOCAL_MACHINE, "Software\\Valve\\Steam",
                    "InstallPath", REG_SZ, install_dir, (DWORD)sizeof(install_dir));
    RegSetKeyValueA(HKEY_CURRENT_USER, "Software\\Valve\\Steam",
                    "SteamExe", REG_SZ, steam_exe, (DWORD)sizeof(steam_exe));
    RegSetKeyValueA(HKEY_CURRENT_USER, "Software\\Valve\\Steam\\ActiveProcess",
                    "SteamPath", REG_SZ, install_dir, (DWORD)sizeof(install_dir));
}

static DWORD WINAPI create_steam_window(void *arg)
{
    static WNDCLASSEXW wndclass = { sizeof(WNDCLASSEXW) };
    static const WCHAR class_nameW[] = {'v','g','u','i','P','o','p','u','p','W','i','n','d','o','w',0};
    static const WCHAR steamW[] = {'S','t','e','a','m',0};
    MSG msg;

    wndclass.lpfnWndProc = DefWindowProcW;
    wndclass.lpszClassName = class_nameW;

    RegisterClassExW(&wndclass);
    CreateWindowW(class_nameW, steamW, WS_POPUP, 40, 40,
                  400, 300, NULL, NULL, NULL, NULL);

    while (GetMessageW(&msg, NULL, 0, 0))
    {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    return 0;
}

typedef void *(*create_interface_func)(const char *name, int *err);

static HMODULE steamclient_module;
static ISteamClient *steam_client;
static HSteamPipe steam_client_pipe;
static HSteamUser steam_client_user;
static ISteamUtils *steam_client_utils;
static ISteamApps *steam_client_apps;

static bool steam_client_init(void)
{
    create_interface_func create_interface;

    steamclient_module = LoadLibraryA("steamclient64.dll");
    if (!steamclient_module)
    {
        WINE_ERR("steam_client_init: no steamclient64.dll, error %u\n", GetLastError());
        return false;
    }

    create_interface = (create_interface_func)GetProcAddress(steamclient_module, "CreateInterface");
    if (!create_interface)
    {
        WINE_ERR("steam_client_init: steamclient64.dll exports no CreateInterface\n");
        return false;
    }

    steam_client = (ISteamClient *)create_interface(STEAMCLIENT_INTERFACE_VERSION, NULL);
    if (!steam_client)
    {
        WINE_ERR("steam_client_init: no %s from steamclient64.dll\n", STEAMCLIENT_INTERFACE_VERSION);
        return false;
    }

    steam_client_pipe = steam_client->CreateSteamPipe();
    if (!steam_client_pipe)
    {
        WINE_ERR("steam_client_init: CreateSteamPipe failed\n");
        return false;
    }

    steam_client_user = steam_client->ConnectToGlobalUser(steam_client_pipe);
    if (!steam_client_user)
    {
        WINE_ERR("steam_client_init: ConnectToGlobalUser failed\n");
        return false;
    }

    steam_client_utils = steam_client->GetISteamUtils(steam_client_pipe, STEAMUTILS_INTERFACE_VERSION);
    steam_client_apps = steam_client->GetISteamApps(steam_client_user, steam_client_pipe,
                                                    STEAMAPPS_INTERFACE_VERSION);
    if (!steam_client_utils || !steam_client_apps)
    {
        WINE_ERR("steam_client_init: %s %p, %s %p\n",
                 STEAMUTILS_INTERFACE_VERSION, steam_client_utils,
                 STEAMAPPS_INTERFACE_VERSION, steam_client_apps);
        return false;
    }

    return true;
}

static void steam_client_shutdown(void)
{
    if (steam_client && steam_client_pipe)
    {
        if (steam_client_user)
            steam_client->ReleaseUser(steam_client_pipe, steam_client_user);
        steam_client->BReleaseSteamPipe(steam_client_pipe);
        steam_client->BShutdownIfAllPipesClosed();
    }

    if (steamclient_module)
        FreeLibrary(steamclient_module);

    steam_client = NULL;
    steam_client_pipe = 0;
    steam_client_user = 0;
    steam_client_utils = NULL;
    steam_client_apps = NULL;
    steamclient_module = NULL;
}

/* requires steam API to be initialized */
static void setup_steam_registry(void)
{
    const char *ui_lang, *language, *languages, *locale = NULL;
    uint32 appid;
    char buf[256];
    HKEY key;
    LSTATUS status;
    const int system_locale_appids[] = {
        1284210 /* Guild Wars 2 */
    };

    ui_lang = steam_client_utils->GetSteamUILanguage();
    WINE_TRACE("UI language: %s\n", wine_dbgstr_a(ui_lang));
    RegSetKeyValueA(HKEY_CURRENT_USER, "Software\\Valve\\Steam", "language",
                    REG_SZ, ui_lang, strlen(ui_lang) + 1);

    appid = steam_client_utils->GetAppID();
    WINE_TRACE("appid: %u\n", appid);
    sprintf(buf, "Software\\Valve\\Steam\\Apps\\%u", appid);
    status = RegCreateKeyA(HKEY_CURRENT_USER, buf, &key);
    if (!status)
    {
        DWORD value;
        value = 1;
        RegSetKeyValueA(key, NULL, "Installed", REG_DWORD, &value, sizeof(value));
        RegSetKeyValueA(key, NULL, "Running", REG_DWORD, &value, sizeof(value));
        value = 0;
        RegSetKeyValueA(key, NULL, "Updating", REG_DWORD, &value, sizeof(value));
        RegCloseKey(key);
    }
    else WINE_ERR("Could not create key: %u\n", status);

    language = steam_client_apps->GetCurrentGameLanguage();
    languages = steam_client_apps->GetAvailableGameLanguages();
    WINE_TRACE( "Game language %s, available %s\n", wine_dbgstr_a(language), wine_dbgstr_a(languages) );

    if (strchr(languages, ',') == NULL) /* If there is a list of languages then respect that */
    {
        for (int i = 0; i < (sizeof(system_locale_appids) / sizeof(*system_locale_appids)); i++)
        {
            if (system_locale_appids[i] == appid)
            {
                WINE_TRACE("Not changing system locale for application %i\n",appid);
                language = NULL;
            }
        }
    }

    if (!language) locale = NULL;
    else if (!strcmp( language, "arabic" )) locale = "ar_001.UTF-8";
    else if (!strcmp( language, "bulgarian" )) locale = "bg_BG.UTF-8";
    else if (!strcmp( language, "schinese" )) locale = "zh_CN.UTF-8";
    else if (!strcmp( language, "tchinese" )) locale = "zh_TW.UTF-8";
    else if (!strcmp( language, "czech" )) locale = "cs_CZ.UTF-8";
    else if (!strcmp( language, "danish" )) locale = "da_DK.UTF-8";
    else if (!strcmp( language, "dutch" )) locale = "nl_NL.UTF-8";
    else if (!strcmp( language, "english" )) locale = "en_US.UTF-8";
    else if (!strcmp( language, "finnish" )) locale = "fi_FI.UTF-8";
    else if (!strcmp( language, "french" )) locale = "fr_FR.UTF-8";
    else if (!strcmp( language, "german" )) locale = "de_DE.UTF-8";
    else if (!strcmp( language, "greek" )) locale = "el_GR.UTF-8";
    else if (!strcmp( language, "hungarian" )) locale = "hu_HU.UTF-8";
    else if (!strcmp( language, "italian" )) locale = "it_IT.UTF-8";
    else if (!strcmp( language, "japanese" )) locale = "ja_JP.UTF-8";
    else if (!strcmp( language, "koreana" )) locale = "ko_KR.UTF-8";
    else if (!strcmp( language, "norwegian" )) locale = "nb_NO.UTF-8";
    else if (!strcmp( language, "polish" )) locale = "pl_PL.UTF-8";
    else if (!strcmp( language, "portuguese" )) locale = "pt_PT.UTF-8";
    else if (!strcmp( language, "brazilian" )) locale = "pt_BR.UTF-8";
    else if (!strcmp( language, "romanian" )) locale = "ro_RO.UTF-8";
    else if (!strcmp( language, "russian" )) locale = "ru_RU.UTF-8";
    else if (!strcmp( language, "spanish" )) locale = "es_ES.UTF-8";
    else if (!strcmp( language, "latam" )) locale = "es_419.UTF-8";
    else if (!strcmp( language, "swedish" )) locale = "sv_SE.UTF-8";
    else if (!strcmp( language, "thai" )) locale = "th_TH.UTF-8";
    else if (!strcmp( language, "turkish" )) locale = "tr_TR.UTF-8";
    else if (!strcmp( language, "ukrainian" )) locale = "uk_UA.UTF-8";
    else if (!strcmp( language, "vietnamese" )) locale = "vi_VN.UTF-8";
    else WINE_FIXME( "Unsupported game language %s\n", wine_dbgstr_a(language) );

    /* HACK: Bug 23597 Granado Espada Japan (1219160) launcher needs Japanese locale to display correctly */
    if (appid == 1219160)
        locale = "ja_JP.UTF-8";

    if (locale)
    {
        WINE_FIXME( "Game language %s, defaulting LC_CTYPE / LC_MESSAGES to %s.\n", wine_dbgstr_a(language), locale );
        setenv( "LC_CTYPE", locale, FALSE );
        setenv( "LC_MESSAGES", locale, FALSE );
    }
}

static bool write_string_to_file(const WCHAR *filename, const std::string &contents)
{
    HANDLE ofile = CreateFileW(filename, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
            FILE_ATTRIBUTE_NORMAL, NULL);
    if(ofile == INVALID_HANDLE_VALUE)
        return false;

    DWORD written;

    if(!WriteFile(ofile, contents.data(), (DWORD)contents.length(), &written, NULL))
    {
        CloseHandle(ofile);
        return false;
    }

    CloseHandle(ofile);

    return true;
}

static bool convert_path_to_win(std::string &s)
{
    WCHAR *path = wine_get_dos_file_name(s.c_str());
    if(!path)
        return false;

    DWORD sz = WideCharToMultiByte(CP_UTF8, 0, path, -1, NULL, 0, NULL, NULL);
    if(!sz)
    {
        HeapFree(GetProcessHeap(), 0, path);
        return false;
    }

    char *pathUTF8 = (char *)HeapAlloc(GetProcessHeap(), 0, sz);
    if(!pathUTF8)
    {
        HeapFree(GetProcessHeap(), 0, path);
        return false;
    }

    sz = WideCharToMultiByte(CP_UTF8, 0, path, -1, pathUTF8, sz, NULL, NULL);
    if(!sz)
    {
        HeapFree(GetProcessHeap(), 0, pathUTF8);
        HeapFree(GetProcessHeap(), 0, path);
        return false;
    }

    s = pathUTF8;

    HeapFree(GetProcessHeap(), 0, pathUTF8);
    HeapFree(GetProcessHeap(), 0, path);

    return true;
}

static WCHAR *strchrW(WCHAR *h, WCHAR n)
{
    do
    {
        if(*h == n)
            return h;
    } while (*h++);

    return NULL;
}

int strncmpW(const WCHAR *l, const WCHAR *r, int n)
{
    if(n <= 0)
        return 0;

    while(--n > 0 && *l && *l == *r){
        l++;
        r++;
    }

    return *l - *r;
}

static WCHAR *find_quote(WCHAR *str)
{
    WCHAR *end = strchrW(str, '"'), *ch;
    int odd;
    while (end)
    {
        odd = 0;
        ch = end - 1;
        while (ch >= str && *ch == '\\')
        {
            odd = !odd;
            --ch;
        }
        if (!odd)
            return end;
        end = strchrW(end + 1, '"');
    }
    return NULL;
}

static BOOL WINAPI console_ctrl_handler(DWORD dwCtrlType)
{
    return TRUE;
}

static BOOL streq_niw(const WCHAR *l, const WCHAR *r, size_t len)
{
    while(len > 0){
        if(towlower(*l) != towlower(*r))
            return FALSE;
        ++l; ++r; --len;
    }
    return TRUE;
}

static WCHAR* get_end_of_excutable_name(WCHAR *cmdline)
{
    BOOL quoted = FALSE;
    WCHAR *executable_name_end = cmdline;

    /* find the end of the first arg...*/
    while (*executable_name_end != '\0' &&
           (*executable_name_end != ' ' || quoted))
    {
        quoted ^= *executable_name_end == '"';

        executable_name_end++;
    }

    return executable_name_end;
}

static BOOL should_use_shell_execute(WCHAR *cmdline)
{
    BOOL use_shell_execute = TRUE;
    const WCHAR *executable_name_end = (const WCHAR*)get_end_of_excutable_name(cmdline);

    /* if the executable is quoted backtrack a bit */
    if (*(executable_name_end - 1) == '"')
        --executable_name_end;


    /* backtrack to before the end of the arg
     * and check if we end in .exe or not
     * and determine whether to use ShellExecute
     * based on that */
    executable_name_end -= strlen(".exe");

    if (executable_name_end >= cmdline)
    {
        static const WCHAR exeW[] = {'.','e','x','e',0};

        if (streq_niw(executable_name_end, exeW, sizeof(exeW) / sizeof(*exeW) - 1))
            use_shell_execute = FALSE;
    }

    return use_shell_execute;
}

static HANDLE run_process(BOOL *should_await, BOOL game_process)
{
    static const WCHAR link2eaW[] = {'l','i','n','k','2','e','a',':','/','/',0};
    static const WCHAR link2ea_pathW[] =
    {
        'S','o','f','t','w','a','r','e','\\','C','l','a','s','s','e','s','\\','l','i','n','k','2','e','a',0
    };
    static const WCHAR ea_desktop_pathW[] =
    {
        'S','o','f','t','w','a','r','e','\\','E','l','e','c','t','r','o','n','i','c',' ','A','r','t','s',
        '\\','E','A',' ','D','e','s','k','t','o','p',0
    };
    static const WCHAR ea_core_pathW[] =
    {
        'S','o','f','t','w','a','r','e','\\','E','l','e','c','t','r','o','n','i','c',' ','A','r','t','s',
        '\\','E','A',' ','C','o','r','e',0
    };
    static const WCHAR IsUnavailableW[] = {'I','s','U','n','a','v','a','i','l','a','b','l','e',0};
    WCHAR *cmdline = GetCommandLineW();
    STARTUPINFOW si = { sizeof(si) };
    PROCESS_INFORMATION pi;
    DWORD flags = CREATE_UNICODE_ENVIRONMENT;
    BOOL use_shell_execute = TRUE, link2ea = FALSE;
    BOOL hide_window;

    /* skip argv[0] */
    if (*cmdline == '"')
    {
        cmdline = find_quote(cmdline + 1);
        if (cmdline) cmdline++;
    }
    else
    {
        cmdline = strchrW(cmdline, ' ');
    }
    if (!cmdline)
    {
        WINE_ERR("Invalid command\n");
        return INVALID_HANDLE_VALUE;
    }
    while (*cmdline == ' ') cmdline++;

    /* convert absolute unix path to dos */
    if (cmdline[0] == '/' ||
            (cmdline[0] == '"' && cmdline[1] == '/'))
    {
        WCHAR *scratchW;
        char *scratchA;
        WCHAR *start, *end, *dos, *remainder, *new_cmdline;
        size_t argv0_len;
        int r;
        DWORD_PTR console;
        SHFILEINFOW sfi;

        static const WCHAR dquoteW[] = {'"',0};

        WINE_TRACE("Converting unix command: %s\n", wine_dbgstr_w(cmdline));

        if (cmdline[0] == '"')
        {
            start = cmdline + 1;
            end = find_quote(start);
            if (!end)
            {
                WINE_ERR("Unmatched quote? %s\n", wine_dbgstr_w(cmdline));
                goto run;
            }
            remainder = end + 1;
        }
        else
        {
            start = cmdline;
            end = strchrW(start, ' ');
            if (!end)
                end = strchrW(start, '\0');
            remainder = end;
        }

        argv0_len = end - start;

        scratchW = (WCHAR *)HeapAlloc(GetProcessHeap(), 0, (argv0_len + 1) * sizeof(WCHAR));
        memcpy(scratchW, start, argv0_len * sizeof(WCHAR));
        scratchW[argv0_len] = '\0';

        r = WideCharToMultiByte(CP_UNIXCP, 0, scratchW, -1,
                NULL, 0, NULL, NULL);
        if (!r)
        {
            WINE_ERR("Char conversion size failed?\n");
            goto run;
        }

        scratchA = (char *)HeapAlloc(GetProcessHeap(), 0, r);

        r = WideCharToMultiByte(CP_UNIXCP, 0, scratchW, -1,
                scratchA, r, NULL, NULL);
        if (!r)
        {
            WINE_ERR("Char conversion failed?\n");
            goto run;
        }

        dos = wine_get_dos_file_name(scratchA);

        CoInitialize(NULL);

        console = SHGetFileInfoW(dos, 0, &sfi, sizeof(sfi), SHGFI_EXETYPE);
        if (console)
        {
            if (!HIWORD(console))
                flags |= CREATE_NEW_CONSOLE;
        }

        new_cmdline = (WCHAR *)HeapAlloc(GetProcessHeap(), 0,
                (lstrlenW(dos) + 3 + lstrlenW(remainder) + 1) * sizeof(WCHAR));
        lstrcpyW(new_cmdline, dquoteW);
        lstrcatW(new_cmdline, dos);
        lstrcatW(new_cmdline, dquoteW);
        lstrcatW(new_cmdline, remainder);

        cmdline = new_cmdline;
    }

run:
    WINE_TRACE("Running command %s\n", wine_dbgstr_w(cmdline));

    SetConsoleCtrlHandler( console_ctrl_handler, TRUE );

    use_shell_execute = should_use_shell_execute(cmdline);
    if (use_shell_execute && lstrlenW(cmdline) > 10 && !memcmp(cmdline, link2eaW, 10 *sizeof(WCHAR)))
    {
        HDESK desktop = GetThreadDesktop(GetCurrentThreadId());
        DWORD is_unavailable, type, size;
        SC_HANDLE manager, service;
        SERVICE_STATUS status;
        DWORD timeout = 3000;
        HKEY eakey;
        BOOL ret;

        link2ea = TRUE;
        if (!SetUserObjectInformationA(desktop, 1000, &timeout, sizeof(timeout)))
            WINE_ERR("Failed to set desktop timeout, err %u.\n", GetLastError());

        if (!RegOpenKeyExW(HKEY_LOCAL_MACHINE, ea_desktop_pathW, 0, KEY_ALL_ACCESS, &eakey))
        {
            size = sizeof(is_unavailable);
            if (!RegQueryValueExW(eakey, IsUnavailableW, NULL, &type, (BYTE *)&is_unavailable, &size)
                    && type == REG_DWORD && is_unavailable)
            {
                WINE_ERR("EA Desktop\\IsUnavailable is set, clearing.\n");
                is_unavailable = 0;
                RegSetValueExW(eakey, IsUnavailableW, 0, REG_DWORD, (BYTE *)&is_unavailable, sizeof(is_unavailable));
            }
            RegCloseKey(eakey);
        }
        if ((manager = OpenSCManagerA(NULL, SERVICES_ACTIVE_DATABASEA, SERVICE_QUERY_STATUS)))
        {
            if ((service = OpenServiceA(manager, "EABackgroundService", SERVICE_QUERY_STATUS)))
            {
                if (QueryServiceStatus(service, &status))
                {
                    TRACE("dwCurrentState %#x.\n", status.dwCurrentState);
                    if (status.dwCurrentState == SERVICE_STOP_PENDING || status.dwCurrentState == SERVICE_STOPPED)
                    {
                        ret = DeleteFileA("C:\\ProgramData\\EA Desktop\\backgroundservice.ini");
                        WARN("Tried to delete backgroundservice.ini, ret %d, error %u.\n", ret, GetLastError());
                    }
                }
                else ERR("Could not query service status, error %u.\n", GetLastError());
                CloseServiceHandle(service);
            }
            else TRACE("Could not open EABackgroundService, error %u.\n", GetLastError());
            CloseServiceHandle(manager);
        }
        else ERR("Could not open service manager, error %u.\n", GetLastError());
    }
    hide_window = env_nonzero("PROTON_HIDE_PROCESS_WINDOW");

    /* only await the process finishing if we launch a process directly...
     * Steam simply calls ShellExecuteA with the same parameters.
     * this avoids the edge case where we could ShellExecute and
     * then that process ends up ShellExecuting something as a throw away */
    *should_await = !use_shell_execute;

    WINE_TRACE("Executing via %s\n",
        wine_dbgstr_a(use_shell_execute ? "ShellExecuteW" : "CreateProcessW"));

    if (use_shell_execute)
    {
        WCHAR *param = NULL;
        WCHAR *executable_name_end = get_end_of_excutable_name(cmdline);
        if (*executable_name_end != '\0')
        {
            *executable_name_end = '\0';
            param = executable_name_end+1;
        }
        static const WCHAR verb[] = { 'o', 'p', 'e', 'n', 0 };
        INT_PTR ret;

        if ((ret = (INT_PTR)ShellExecuteW(NULL, verb, cmdline, param, NULL, hide_window ? SW_HIDE : SW_SHOWNORMAL)) < 32)
        {
            WINE_ERR("Failed to execute %s, ret %u.\n", wine_dbgstr_w(cmdline), (unsigned int)ret);
            if (game_process && ret == SE_ERR_NOASSOC && link2ea)
            {
                static const WCHAR msi_guidW[] = {'{','C','2','6','2','2','0','8','5','-','A','B','D','2','-','4','9','E','5','-','8','A','B','9','-','D','3','D','6','A','6','4','2','C','0','9','1','}',0};
                static const WCHAR REMOVE_ALL_W[] = {'R','E','M','O','V','E','=','A','L','L',0};

                /* Try to uninstall EA desktop so it is set up from prerequisites on the next run. */
                UINT ret = MsiConfigureProductExW(msi_guidW, 0, INSTALLSTATE_DEFAULT, REMOVE_ALL_W);

                WINE_TRACE("MsiConfigureProductExW ret %u.\n", ret);
                /* If uninstall failed this should trigger interactive repair window on the EA setup run. */
                RegDeleteTreeW(HKEY_LOCAL_MACHINE, link2ea_pathW);
                RegDeleteTreeW(HKEY_LOCAL_MACHINE, ea_desktop_pathW);
                RegDeleteTreeW(HKEY_LOCAL_MACHINE, ea_core_pathW);
            }
        }
        return INVALID_HANDLE_VALUE;
    }
    else
    {
        if (hide_window)
        {
            si.dwFlags |= STARTF_USESHOWWINDOW;
            si.wShowWindow = SW_HIDE;
        }

        /* Hand the child our own std handles, otherwise everything it prints is lost
         * (upstream NotProton 1.1.x, "Stop steam shim from discarding output of launched
         * games"): the game's own output then reaches lullaby-wine.log. */
        /* Not for a program that gets a console of its own: pinned to the log, it could not clear or move
         * its console (upstream NotProton 1.2.0, "Windows console games"). */
        BOOL inherit = !(flags & CREATE_NEW_CONSOLE);
        if (inherit)
        {
            si.dwFlags |= STARTF_USESTDHANDLES;
            si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
            si.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
            si.hStdError = GetStdHandle(STD_ERROR_HANDLE);
        }

        if (!CreateProcessW(NULL, cmdline, NULL, NULL, inherit, flags, NULL, NULL, &si, &pi))
        {
            WINE_ERR("Failed to create process %s: %u\n", wine_dbgstr_w(cmdline), GetLastError());
            return INVALID_HANDLE_VALUE;
        }

        CloseHandle(pi.hThread);

        return pi.hProcess;
    }
}

/* Forward stub steam.exe commands to the native steam client */
static BOOL steam_command_handler(int argc, char *argv[])
{
    BOOL restart_self = FALSE;
    const char *sgi;

    /* If there are command line options, only forward steam:// and options start with - */
    if (argc > 1 && StrStrIA(argv[1], "steam://") != argv[1] && argv[1][0] != '-')
        return FALSE;

    if (argc > 2 && !strcmp(argv[1], "--") && (sgi = getenv("SteamGameId")))
    {
        char s[64];

        snprintf(s, sizeof(s), "steam://launch/%s", sgi);
        if (!(restart_self = !strcmp(argv[2], s)))
        {
            snprintf(s, sizeof(s), "steam://rungameid/%s", sgi);
            restart_self = !strcmp(argv[2], s);
        }
    }
    if (restart_self)
    {
        HANDLE event;

        event = OpenEventA(SYNCHRONIZE, FALSE, "PROTON_STEAM_EXE_RESTART_APP");
        if (event)
        {
            SetEvent(event);
            CloseHandle(event);
            WINE_TRACE("Signalled app restart.\n");
        }
        else
            WINE_ERR("Restart event not found.\n");
        return TRUE;
    }

    if (argc <= 1)
        return FALSE;

    for (int i = 1; i < argc; ++i)
    {
        char cmdline[1024];
        STARTUPINFOA si = { sizeof(si) };
        PROCESS_INFORMATION pi;

        if (StrStrIA(argv[i], "steam://") != argv[i])
            continue;

        snprintf(cmdline, sizeof(cmdline),
                 "C:\\windows\\system32\\winebrowser.exe \"%s\"", argv[i]);
        if (!CreateProcessA(NULL, cmdline, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi))
        {
            WINE_ERR("Failed to forward %s.\n", argv[i]);
            break;
        }
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
        WINE_TRACE("Forwarded %s to the native client.\n", argv[i]);
        break;
    }

    return TRUE;
}

static void setup_steam_files(void)
{
    static const WCHAR config_pathW[] =
    {
        'C',':','\\','P','r','o','g','r','a','m',' ','F','i','l','e','s',' ','(','x','8','6',')','\\','S','t','e','a','m',
        '\\','c','o','n','f','i','g',0,
    };
    static const WCHAR steamapps_pathW[] =
    {
        'C',':','\\','P','r','o','g','r','a','m',' ','F','i','l','e','s',' ','(','x','8','6',')','\\','S','t','e','a','m',
        '\\','s','t','e','a','m','a','p','p','s',0,
    };
    static const WCHAR libraryfolders_nameW[] =
    {
        'C',':','\\','P','r','o','g','r','a','m',' ','F','i','l','e','s',' ','(','x','8','6',')','\\','S','t','e','a','m',
        '\\','s','t','e','a','m','a','p','p','s','\\','l','i','b','r','a','r','y','f','o','l','d','e','r','s','.','v','d','f',0,
    };
    const char *steam_install_path = getenv("STEAM_COMPAT_CLIENT_INSTALL_PATH");
    const char *steam_library_paths = getenv("STEAM_COMPAT_LIBRARY_PATHS");
    const char *start, *end, *next;
    unsigned int i, index = 0;
    std::string contents;
    char idx_str[10];

    if (!CreateDirectoryW(config_pathW, NULL) && GetLastError() != ERROR_ALREADY_EXISTS)
    {
        WINE_ERR("Failed to create config directory, GetLastError() %u.\n", GetLastError());
        return;
    }

    if (!CreateDirectoryW(steamapps_pathW, NULL) && GetLastError() != ERROR_ALREADY_EXISTS)
    {
        WINE_ERR("Failed to create steamapps directory, GetLastError() %u.\n", GetLastError());
        return;
    }

    contents += "\"LibraryFolders\"\n{\n";

    WINE_TRACE("steam_install_path %s.\n", wine_dbgstr_a(steam_install_path));

    if (steam_install_path)
    {
        std::string s = steam_install_path;

        if (convert_path_to_win(s))
        {
            sprintf(idx_str, "%u", index);
            ++index;

            for (i = 0; i < s.length(); ++i)
            {
                if (s[i] == '\\')
                {
                    s.insert(i, 1, '\\');
                    ++i;
                }
            }

            contents += std::string("\t\"") + idx_str + "\"\n\t{\n\t\t\"path\"\t\t\"" + s + "\"\n\t}\n";
        }
        else
        {
            WINE_ERR("Could not convert %s to win path.\n", wine_dbgstr_a(s.c_str()));
        }
    }

    WINE_TRACE("steam_library_paths %s.\n", wine_dbgstr_a(steam_library_paths));

    start = steam_library_paths;
    while (start && *start)
    {
        std::string s;

        if (!(next = strchr(start, ':')))
            next = start + strlen(start);
        end = next;

        if (end != start && end[-1] == '/')
            --end;

        while (end != start && end[-1] != '/' )
            --end;
        if (end != start)
            --end;

        s.append(start, end - start);
        if (convert_path_to_win(s))
        {
            sprintf(idx_str, "%u", index);
            ++index;

            for (i = 0; i < s.length(); ++i)
            {
                if (s[i] == '\\')
                {
                    s.insert(i, 1, '\\');
                    ++i;
                }
            }

            contents += std::string("\t\"") + idx_str + "\"\n\t{\n\t\t\"path\"\t\t\"" + s + "\"\n\t}\n";
        }
        else
        {
            WINE_ERR("Could not convert %s to win path.\n", wine_dbgstr_a(s.c_str()));
        }
        if (*next == ':')
            ++next;
        start = next;
    }

    contents += "}\n";

    if (!write_string_to_file(libraryfolders_nameW, contents))
        WINE_ERR("Could not write %s.\n", wine_dbgstr_w(libraryfolders_nameW));
}

#ifndef DIRECTORY_QUERY
#define DIRECTORY_QUERY 0x0001
#endif

static HANDLE find_ack_event(void)
{
    static const WCHAR steam_ack_event[] = {'S','T','E','A','M','_','S','T','A','R','T','_','A','C','K','_','E','V','E','N','T',0};
    static const WCHAR name[] = {'\\','B','a','s','e','N','a','m','e','d','O','b','j','e','c','t','s','\\','S','e','s','s','i','o','n','\\','1',0};
    DIRECTORY_BASIC_INFORMATION *di;
    OBJECT_ATTRIBUTES attr;
    HANDLE dir, ret = NULL;
    ULONG context, size;
    UNICODE_STRING str;
    char buffer[1024];
    NTSTATUS status;

    di = (DIRECTORY_BASIC_INFORMATION *)buffer;

    RtlInitUnicodeString(&str, name);
    InitializeObjectAttributes(&attr, &str, 0, 0, NULL);
    status = NtOpenDirectoryObject( &dir, DIRECTORY_QUERY, &attr );
    if (status)
    {
        WINE_WARN("Failed to open directory %s, status %#x.\n", wine_dbgstr_w(name), status);
        return NULL;
    }

    status = NtQueryDirectoryObject(dir, di, sizeof(buffer), TRUE, TRUE, &context, &size);
    while (!status)
    {
        if (!strncmpW(di->ObjectName.Buffer, steam_ack_event, ARRAY_SIZE(steam_ack_event) - 1))
        {
            WINE_TRACE("Found event %s.\n", wine_dbgstr_w(di->ObjectName.Buffer));
            ret = OpenEventW(SYNCHRONIZE, FALSE, di->ObjectName.Buffer);
            if (!ret)
                WINE_WARN("Failed to create event, err %u.\n", GetLastError());
            break;
        }
        status = NtQueryDirectoryObject(dir, di, sizeof(buffer), TRUE, FALSE, &context, &size);
    }
    if (status && status != STATUS_NO_MORE_ENTRIES)
        WINE_WARN("NtQueryDirectoryObject failed, status %#x.\n", status);
    WINE_TRACE("ret %p.\n", ret);

    CloseHandle(dir);
    return ret;
}

static DWORD WINAPI steam_drm_thread(void *arg)
{
    HANDLE consume, produce;
    HANDLE start_ack = NULL;
    HANDLE child = arg;
    DWORD pid;
    LONG prev;

    consume = CreateSemaphoreA(NULL, 0, 512, "STEAM_DIPC_CONSUME");
    if (!consume)
    {
        WINE_ERR("Failed to create consume semaphore, err %u.\n", GetLastError());
        return -1;
    }
    produce = CreateSemaphoreA(NULL, 1, 512, "SREAM_DIPC_PRODUCE");
    if (!produce)
    {
        CloseHandle(consume);
        WINE_ERR("Failed to create produce semaphore, err %u.\n", GetLastError());
        return -1;
    }

    pid = GetProcessId(child);

    WINE_TRACE("Child pid %04x.\n", pid);

    while (WaitForSingleObject(consume, INFINITE) == WAIT_OBJECT_0)
    {
        WINE_TRACE("Got event.\n");

        if (!start_ack)
            start_ack = find_ack_event();
        if (start_ack)
            SetEvent(start_ack);
        ReleaseSemaphore(produce, 1, &prev);
        WINE_TRACE("prev %d.\n", prev);
    }

    return 0;
}

int main(int argc, char *argv[])
{
    HANDLE wait_handle = INVALID_HANDLE_VALUE;
    HANDLE event2 = INVALID_HANDLE_VALUE;
    HANDLE event = INVALID_HANDLE_VALUE;
    HANDLE child = INVALID_HANDLE_VALUE;
    BOOL game_process = FALSE;
    DWORD rc = 0;

    WINE_TRACE("\n");

    if (steam_command_handler(argc, argv))
        return 0;

    if (getenv("SteamGameId"))
    {
        /* do setup only for game process */
        event = CreateEventA(NULL, FALSE, FALSE, "Steam3Master_SharedMemLock");

        /* For 2K Launcher. */
        event2 = CreateEventA(NULL, FALSE, FALSE, "Global\\Valve_SteamIPC_Class");

        CreateThread(NULL, 0, create_steam_window, NULL, 0, NULL);

        set_active_process_pid();
        set_client_dll_paths();
        set_install_paths();

        if (steam_client_init())
        {
            setup_steam_registry();
        }
        else
        {
            WINE_ERR("steam_client_init failed\n");
        }

        setup_steam_files();

        steam_client_shutdown();

        game_process = TRUE;
    }

    if (argc > 1)
    {
        BOOL should_await;

        child = run_process(&should_await, game_process);

        if (should_await)
        {
            if (child == INVALID_HANDLE_VALUE)
                return 1;

            wait_handle = child;
        }

        if (game_process)
            CreateThread(NULL, 0, steam_drm_thread, child, 0, NULL);
    }
    else if (game_process)
    {
        CreateThread(NULL, 0, steam_drm_thread, INVALID_HANDLE_VALUE, 0, NULL);
    }

    if (game_process)
        NtSetInformationProcess( GetCurrentProcess(), (PROCESSINFOCLASS)1000 /* ProcessWineMakeProcessSystem */,
                                 &wait_handle, sizeof(HANDLE *) );

    if (game_process && wait_handle == INVALID_HANDLE_VALUE)
    {
        FreeConsole();
        for (;;)
            Sleep(INFINITE);
    }

    if(wait_handle != INVALID_HANDLE_VALUE)
    {
        HANDLE waits[2];
        DWORD ret;
        int wait_count;

        waits[0] = wait_handle;
        waits[1] = NULL;
        wait_count = 1;
        if (game_process)
        {
            if ((waits[1] = CreateEventA(NULL, FALSE, FALSE, "PROTON_STEAM_EXE_RESTART_APP")))
            {
                ++wait_count;
            }
            else
            {
                WINE_ERR("Failed to create restart event, err %lu.\n", GetLastError());
            }
        }
        FreeConsole();
        while ((ret = WaitForMultipleObjects(wait_count, waits, FALSE, INFINITE) != WAIT_OBJECT_0))
        {
            BOOL should_await;

            if (ret != WAIT_OBJECT_0 + 1)
            {
                WINE_ERR("Wait failed.\n");
                break;
            }
            if (child != INVALID_HANDLE_VALUE)
            {
                if (WaitForSingleObject(child, 0) == WAIT_TIMEOUT)
                {
                    WINE_ERR("Child is still running, not restarting.\n");
                    continue;
                }
                CloseHandle(child);
            }
            child = run_process(&should_await, game_process);
        }
        CloseHandle(waits[1]);
    }

    if (event != INVALID_HANDLE_VALUE)
        CloseHandle(event);
    if (event2 != INVALID_HANDLE_VALUE)
        CloseHandle(event2);

    if (child != INVALID_HANDLE_VALUE)
    {
        GetExitCodeProcess(child, &rc);
        CloseHandle(child);
    }

    return rc;
}
