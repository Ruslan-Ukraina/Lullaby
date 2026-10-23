#!/usr/bin/env python3
"""Adds interfaces Valve's macOS steamclient serves but Proton's lsteamclient (at the
pinned commit) does not, to the tree fetch.sh assembles. Run by fetch.sh after the
authored overlay; it edits the generated files the way Proton's gen_wrapper.py lays
them out, so the additions read like the rest.

  SteamNetworkingSocketsSerialized005  Deadlock and other Source 2 games ask for it
  SteamAppDisableUpdate001             the same

Layouts (docs/DECISIONS.md P3-2):
- SteamNetworkingSocketsSerialized005: the eight methods of 003, then GetSTUNServer,
  BAllowDirectConnectToPeer, BeginAsyncRequestFakeIP (gbe_fork sdk/steam/
  isteamnetworkingsocketsserialized.h, SKYNET's InterfaceLayout for 005). The three
  new methods return int32_t here: whether the client returns bool or int, the game
  reads what its own declaration says from the same register, so a wrong guess of
  bool vs int cannot change what the game sees.
- SteamAppDisableUpdate001: SetAppUpdateDisabledSecondsRemaining(uint32) (Valve's
  public/steam/isteamappdisableupdate.h).

  add-interfaces.py <tree>
"""
import re
import sys

tree = sys.argv[1]
OLD = "SteamNetworkingSocketsSerialized003"
NEW = "SteamNetworkingSocketsSerialized005"
SER = "ISteamNetworkingSocketsSerialized"
ADU_CLASS = "ISteamAppDisableUpdate"
ADU = "SteamAppDisableUpdate001"


def read(name):
    with open(f"{tree}/{name}", encoding="utf-8") as f:
        return f.read()


def write(name, text):
    with open(f"{tree}/{name}", "w", encoding="utf-8") as f:
        f.write(text)


def once(text, old, new, where):
    if text.count(old) != 1:
        sys.exit(f"add-interfaces: {where}: expected one '{old[:60]}', found {text.count(old)}")
    return text.replace(old, new)


# A method: name, return type ('void' or a C type), [(type, wow64 type or None, name)], stack bytes on i386
SER_NEW = [
    ("GetSTUNServer", "int32_t",
     [("int32_t", None, "dont_know"), ("char *", "char *", "buf"), ("uint32_t", None, "len")], 16),
    ("BAllowDirectConnectToPeer", "int32_t",
     [("const SteamNetworkingIdentity_144 *", "const SteamNetworkingIdentity_144 *", "identity")], 8),
    ("BeginAsyncRequestFakeIP", "int32_t", [("int32_t", None, "nNumPorts")], 8),
]
ADU_METHODS = [
    ("SetAppUpdateDisabledSecondsRemaining", "void", [("uint32_t", None, "nSeconds")], 8),
]


def params_struct(cls, ver, m, wow64):
    name, ret, args, _ = m
    lines = [f"struct {'wow64_' if wow64 else ''}{cls}_{ver}_{name}_params", "{", "    struct u_iface u_iface;"]
    if ret != "void":
        lines.append(f"    {ret} _ret;")
    for t, w, a in args:
        if wow64 and w:
            lines.append(f"    W32_PTR({t}{a}, {a}, {w});")
        else:
            lines.append(f"    {t}{'' if t.endswith('*') else ' '}{a};")
    return "\n".join(lines + ["};", ""]) + "\n"


def unix_func(cls, ver, m, wow64):
    name, ret, args, _ = m
    p = f"{'wow64_' if wow64 else ''}{cls}_{ver}_{name}"
    call = f"iface->{name}( {', '.join('params->' + a for _, _, a in args)} );"
    body = [f"NTSTATUS {p}( void *args )", "{",
            f"    struct {p}_params *params = (struct {p}_params *)args;",
            f"    struct u_{cls}_{ver} *iface = (struct u_{cls}_{ver} *)params->u_iface;",
            f"    {'params->_ret = ' if ret != 'void' else ''}{call}",
            "    return 0;", "}", ""]
    text = "\n".join(body) + "\n"
    if wow64:
        text = "#if defined(__x86_64__) || defined(__aarch64__)\n" + text[:-1] + "#endif\n\n"
    return text


def win_func(cls, ver, m):
    name, ret, args, _ = m
    sig = ", ".join(["struct w_iface *_this"] + [f"{t}{'' if t.endswith('*') else ' '}{a}" for t, _, a in args])
    lines = [f"{ret} __thiscall win{cls}_{ver}_{name}({sig})", "{",
             f"    struct {cls}_{ver}_{name}_params params =", "    {", "        .u_iface = _this->u_iface,"]
    lines += [f"        .{a} = {a}," for _, _, a in args]
    lines += ["    };", '    TRACE("%p\\n", _this);', f"    STEAMCLIENT_CALL( {cls}_{ver}_{name}, &params );"]
    if ret != "void":
        lines.append("    return params._ret;")
    return "\n".join(lines + ["}", ""]) + "\n"


def u_decl(m):
    name, ret, args, _ = m
    return f"    virtual {ret} {name}( {', '.join(t for t, _, _ in args)} ) = 0;\n"


def unix_decls(cls, ver, methods):
    return "".join(f"NTSTATUS {cls}_{ver}_{m[0]}( void * );\nNTSTATUS wow64_{cls}_{ver}_{m[0]}( void * );\n"
                   for m in methods)


# --- SteamNetworkingSocketsSerialized005 -------------------------------------------------

old_names = re.findall(rf"NTSTATUS {SER}_{OLD}_(\w+)\( void \*args \)", read(f"cpp{SER}_{OLD}.cpp"))
if len(old_names) != 8:
    sys.exit(f"add-interfaces: expected the eight methods of {OLD}, found {len(old_names)}")

cpp = read(f"cpp{SER}_{OLD}.cpp").replace(OLD, NEW)
cpp += "".join(unix_func(SER, NEW, m, False) + unix_func(SER, NEW, m, True) for m in SER_NEW)
write(f"cpp{SER}_{NEW}.cpp", cpp)

h = read("unixlib_generated.h")
blocks = re.findall(rf"(struct (?:wow64_)?{SER}_{OLD}_\w+_params\n\{{.*?\n\}};\n\n)", h, re.S)
if len(blocks) != 16:
    sys.exit(f"add-interfaces: expected 16 param structs for {OLD}, found {len(blocks)}")
new_structs = "".join(b.replace(OLD, NEW) for b in blocks)
new_structs += "".join(params_struct(SER, NEW, m, False) + params_struct(SER, NEW, m, True) for m in SER_NEW)
new_structs += "".join(params_struct(ADU_CLASS, ADU, m, False) + params_struct(ADU_CLASS, ADU, m, True)
                       for m in ADU_METHODS)
h = once(h, blocks[-1], blocks[-1] + new_structs, "unixlib_generated.h structs")
enum_add = "".join(f"    unix_{SER}_{NEW}_{n},\n" for n in old_names + [m[0] for m in SER_NEW])
enum_add += "".join(f"    unix_{ADU_CLASS}_{ADU}_{m[0]},\n" for m in ADU_METHODS)
h = once(h, "    unix_ISteamUtils_SteamUtils011_IsRunningUnderProton,\n};",
         "    unix_ISteamUtils_SteamUtils011_IsRunningUnderProton,\n" + enum_add + "};", "enum unix_funcs")
write("unixlib_generated.h", h)

cpp_tab = read("unixlib_generated.cpp")
names = [f"{SER}_{NEW}_{n}" for n in old_names + [m[0] for m in SER_NEW]] + \
        [f"{ADU_CLASS}_{ADU}_{m[0]}" for m in ADU_METHODS]
cpp_tab = once(cpp_tab, "    ISteamUtils_SteamUtils011_IsRunningUnderProton,\n};",
               "    ISteamUtils_SteamUtils011_IsRunningUnderProton,\n" + "".join(f"    {n},\n" for n in names) + "};",
               "unix call table")
cpp_tab = once(cpp_tab, "    wow64_ISteamUtils_SteamUtils011_IsRunningUnderProton,\n};",
               "    wow64_ISteamUtils_SteamUtils011_IsRunningUnderProton,\n" +
               "".join(f"    wow64_{n},\n" for n in names) + "};", "wow64 call table")
write("unixlib_generated.cpp", cpp_tab)

p = read("unix_private_generated.h")
m = re.search(rf"struct u_{SER}_{OLD}\n\{{\n#ifdef __cplusplus\n(.*?)#endif /\* __cplusplus \*/\n\}};\n\n", p, re.S)
if not m:
    sys.exit(f"add-interfaces: no u_{SER}_{OLD}")
u_struct = (f"struct u_{SER}_{NEW}\n{{\n#ifdef __cplusplus\n{m.group(1)}" + "".join(u_decl(x) for x in SER_NEW) +
            "#endif /* __cplusplus */\n};\n\n")
u_struct += (f"struct u_{ADU_CLASS}_{ADU}\n{{\n#ifdef __cplusplus\n" + "".join(u_decl(x) for x in ADU_METHODS) +
             "#endif /* __cplusplus */\n};\n\n")
p = once(p, m.group(0), m.group(0) + u_struct, "u_ struct")
decl_old = unix_decls(SER, OLD, [(n,) for n in old_names])
p = once(p, decl_old, decl_old + unix_decls(SER, NEW, [(n,) for n in old_names] + SER_NEW) +
         unix_decls(ADU_CLASS, ADU, ADU_METHODS), "unix declarations")
write("unix_private_generated.h", p)

w = read(f"win{SER}.c")
start = w.index(f"DEFINE_THISCALL_WRAPPER(win{SER}_{OLD}_{old_names[0]}")
end = w.index(f"void init_win{SER}_rtti( char *base )")
block = w[start:end].replace(OLD, NEW)
wrappers = "".join(f"DEFINE_THISCALL_WRAPPER(win{SER}_{NEW}_{x[0]}, {x[3]})\n" for x in SER_NEW)
last_wrapper = f"DEFINE_THISCALL_WRAPPER(win{SER}_{NEW}_{old_names[-1]}, "
i = block.index(last_wrapper)
i = block.index("\n", i) + 1
block = block[:i] + wrappers + block[i:]
i = block.index(f"extern vtable_ptr win{SER}_{NEW}_vtable;")
block = block[:i] + "".join(win_func(SER, NEW, x) for x in SER_NEW) + block[i:]
last_vt = f"        VTABLE_ADD_FUNC(win{SER}_{NEW}_{old_names[-1]})\n"
block = once(block, last_vt, last_vt + "".join(f"        VTABLE_ADD_FUNC(win{SER}_{NEW}_{x[0]})\n" for x in SER_NEW),
             "005 vtable")
block = once(block, f'_vtable, 8, "{NEW}");', f'_vtable, 11, "{NEW}");', "005 method count")
w = w[:end] + block + w[end:]
w = once(w, f"    init_win{SER}_{OLD}_rtti( base );\n",
         f"    init_win{SER}_{OLD}_rtti( base );\n    init_win{SER}_{NEW}_rtti( base );\n", "005 rtti")
write(f"win{SER}.c", w)

# --- SteamAppDisableUpdate001 ------------------------------------------------------------

write(f"cpp{ADU_CLASS}_{ADU}.cpp",
      '/* This file is auto-generated, do not edit. */\n#include "unix_private.h"\n\n#if 0\n#pragma makedep unix\n#endif\n\n' +
      "".join(unix_func(ADU_CLASS, ADU, x, False) + unix_func(ADU_CLASS, ADU, x, True) for x in ADU_METHODS))
win = ['/* This file is auto-generated, do not edit. */', '#include "steamclient_private.h"', '',
       'WINE_DEFAULT_DEBUG_CHANNEL(steamclient);', '']
win += [f"DEFINE_THISCALL_WRAPPER(win{ADU_CLASS}_{ADU}_{x[0]}, {x[3]})" for x in ADU_METHODS] + [""]
text = "\n".join(win) + "\n" + "".join(win_func(ADU_CLASS, ADU, x) for x in ADU_METHODS)
text += (f"extern vtable_ptr win{ADU_CLASS}_{ADU}_vtable;\n\n"
         f'DEFINE_RTTI_DATA0(win{ADU_CLASS}_{ADU}, 0, ".?AV{ADU_CLASS}@@")\n\n'
         f"__ASM_BLOCK_BEGIN(win{ADU_CLASS}_{ADU}_vtables)\n    __ASM_VTABLE(win{ADU_CLASS}_{ADU},\n" +
         "".join(f"        VTABLE_ADD_FUNC(win{ADU_CLASS}_{ADU}_{x[0]})\n" for x in ADU_METHODS) +
         "    );\n__ASM_BLOCK_END\n\n"
         f"struct w_iface *create_win{ADU_CLASS}_{ADU}( struct u_iface u_iface )\n{{\n"
         f'    struct w_iface *r = alloc_mem_for_iface(sizeof(struct w_iface), "{ADU}");\n'
         '    TRACE("-> %p\\n", r);\n'
         f'    r->vtable = alloc_vtable(&win{ADU_CLASS}_{ADU}_vtable, {len(ADU_METHODS)}, "{ADU}");\n'
         "    r->u_iface = u_iface;\n    return r;\n}\n\n"
         f"void init_win{ADU_CLASS}_rtti( char *base )\n{{\n#if defined(__x86_64__) || defined(__aarch64__)\n"
         f"    init_win{ADU_CLASS}_{ADU}_rtti( base );\n#endif /* defined(__x86_64__) || defined(__aarch64__) */\n}}\n")
write(f"win{ADU_CLASS}.c", text)

# --- tables, headers, Makefile -----------------------------------------------------------

g = read("steamclient_generated.c")
entry = f'    {{"{OLD}", &create_win{SER}_{OLD}}},\n'
g = once(g, entry, entry + f'    {{"{NEW}", &create_win{SER}_{NEW}}},\n'
         f'    {{"{ADU}", &create_win{ADU_CLASS}_{ADU}}},\n', "constructors")
g = once(g, "extern void init_winISteamAppList_rtti( char * );\n",
         f"extern void init_win{ADU_CLASS}_rtti( char * );\nextern void init_winISteamAppList_rtti( char * );\n", "rtti externs")
g = once(g, "    init_winISteamAppList_rtti( base );\n",
         f"    init_win{ADU_CLASS}_rtti( base );\n    init_winISteamAppList_rtti( base );\n", "rtti calls")
write("steamclient_generated.c", g)

gh = read("steamclient_generated.h")
ext = f"extern struct w_iface *create_win{SER}_{OLD}( struct u_iface );\n"
gh = once(gh, ext, ext + f"extern struct w_iface *create_win{SER}_{NEW}( struct u_iface );\n"
          f"extern struct w_iface *create_win{ADU_CLASS}_{ADU}( struct u_iface );\n", "create externs")
write("steamclient_generated.h", gh)

mk = read("Makefile.in")
mk = once(mk, f"\tcpp{SER}_{OLD}.cpp \\\n",
          f"\tcpp{SER}_{OLD}.cpp \\\n\tcpp{SER}_{NEW}.cpp \\\n\tcpp{ADU_CLASS}_{ADU}.cpp \\\n", "Makefile cpp")
mk = once(mk, f"\twin{SER}.c \\\n", f"\twin{SER}.c \\\n\twin{ADU_CLASS}.c \\\n", "Makefile win")
write("Makefile.in", mk)
print(f"==> added {NEW} (11 methods) and {ADU} (1 method)")
