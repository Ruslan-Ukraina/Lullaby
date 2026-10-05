#!/usr/bin/env python3
# Static check of a patched ntdll.dll against the clean one it was made from.
#
#   verify.py <clean ntdll.dll> <patched ntdll.dll> <payload.bin>
#
# Passes only when the two files differ in exactly two places, both where the
# patch is meant to write:
#   - the hook site, now a jmp rel32 to the payload, padded with int3;
#   - the code cave, now holding the payload byte for byte;
# and when the payload, disassembled in place, does what the shim promises:
# reads load_path from the frame slot resolve.py found, calls the detour with
# the MODREF register, replays the stolen instruction, and jumps back to the
# instruction after it. Exits 1 on any mismatch.
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import capstone  # noqa: E402
from resolve import PE, resolve, shell_vars  # noqa: E402


def fail(msg):
    raise SystemExit(f"FAIL: {msg}")


def main():
    if len(sys.argv) != 4:
        raise SystemExit(f"usage: {sys.argv[0]} <clean ntdll.dll> <patched ntdll.dll> <payload.bin>")
    clean_path, patched_path, payload_path = sys.argv[1:]
    clean = open(clean_path, 'rb').read()
    patched = open(patched_path, 'rb').read()
    payload = open(payload_path, 'rb').read()

    r = resolve(clean_path)
    v = shell_vars(clean_path)
    if r['machine'] != 0x8664:
        fail(f"{clean_path} is machine {r['machine']:#x}, this check covers x86_64 only")
    pe = PE(clean_path)
    base = r['imageBase']
    hook_rva, stolen = r['hookRVA'], bytes.fromhex(r['stolen'])
    payload_rva = int(v['NP_PAYLOAD_RVA'], 16)
    hook_off, cave_off = pe.off(hook_rva), pe.off(payload_rva)

    if len(clean) != len(patched):
        fail(f"sizes differ: {len(clean)} vs {len(patched)}")

    # 1. Only the hook site and the cave changed.
    changed = [i for i in range(len(clean)) if clean[i] != patched[i]]
    allowed = set(range(hook_off, hook_off + len(stolen))) | \
        set(range(cave_off, cave_off + len(payload)))
    stray = [i for i in changed if i not in allowed]
    if stray:
        fail(f"{len(stray)} bytes changed outside the hook and the cave, first at {stray[0]:#x}")
    print(f"ok  {len(changed)} bytes differ, all inside the hook site ({len(stolen)} bytes "
          f"at {hook_rva:#x}) and the cave ({len(payload)} bytes at {payload_rva:#x})")

    # 2. The cave was padding, sits inside .text's mapped page, and now holds the payload.
    if any(b != r['fill'] for b in clean[cave_off:cave_off + len(payload)]):
        fail("the clean cave is not padding")
    if patched[cave_off:cave_off + len(payload)] != payload:
        fail("the cave does not hold the payload")
    _, tvrva, tvsize, _, trsize = pe.sec('.text')
    page_end = (tvrva + tvsize + 0xfff) & ~0xfff
    if not (tvrva + tvsize <= payload_rva and payload_rva + len(payload) <= min(page_end, tvrva + trsize)):
        fail(f"payload {payload_rva:#x}+{len(payload)} is not inside .text's last mapped page "
             f"(virtual end {tvrva + tvsize:#x}, page end {page_end:#x}, raw end {tvrva + trsize:#x})")
    print(f"ok  payload is in .text padding: virtual end {tvrva + tvsize:#x}, "
          f"payload end {payload_rva + len(payload):#x}, page end {page_end:#x}")

    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    md.detail = True

    # 3. The hook site jumps to the payload.
    hook = list(md.disasm(patched[hook_off:hook_off + len(stolen)], base + hook_rva))
    if hook[0].mnemonic != 'jmp' or int(hook[0].op_str, 16) != base + payload_rva:
        fail(f"hook site is '{hook[0].mnemonic} {hook[0].op_str}', not a jmp to {base + payload_rva:#x}")
    if any(i.mnemonic != 'int3' for i in hook[1:]):
        fail("the hook site padding is not int3")
    print(f"ok  hook {base + hook_rva:#x}: jmp {base + payload_rva:#x}, "
          f"{len(stolen) - 5} bytes of int3 padding")

    # 4. The shim, disassembled where it will run.
    shim = []
    for i in md.disasm(payload, base + payload_rva):
        shim.append(i)
        if i.mnemonic == 'jmp':
            break
    text = [f"{i.mnemonic} {i.op_str}".strip() for i in shim]
    load_path = r['load_path']
    want_slot = f"qword ptr [rsp + {load_path + 8:#x}]"
    if not any(t.endswith(want_slot) and t.startswith('mov ') for t in text[:3]):
        fail(f"the shim does not read load_path from {want_slot}: {text[:3]}")

    def rip_target(i):
        for op in i.operands:
            if op.type == capstone.x86.X86_OP_MEM and op.mem.base == capstone.x86.X86_REG_RIP:
                return i.address + i.size + op.mem.disp
        return None

    leas = [rip_target(i) for i in shim if i.mnemonic == 'lea' and rip_target(i) is not None]
    want = [r['exports'][n] for n in ('LdrGetDllHandle', 'LdrLoadDll', 'NtProtectVirtualMemory')]
    if leas[:3] != want:
        fail(f"ctx table addresses {[hex(x) for x in leas[:3]]}, expected {[hex(x) for x in want]}")
    calls = [i for i in shim if i.mnemonic == 'call']
    if len(calls) != 1 or not (base + payload_rva <= int(calls[0].op_str, 16) < base + payload_rva + len(payload)):
        fail(f"the shim does not call into the payload: {[c.op_str for c in calls]}")
    if f"mov rdx, {r['wm']}" not in text:
        fail(f"the shim does not hand {r['wm']} to the detour as the MODREF")
    tail = shim[-1]
    if int(tail.op_str, 16) != base + r['resume']:
        fail(f"the shim returns to {tail.op_str}, expected {base + r['resume']:#x}")
    replay = b''.join(i.bytes for i in shim[-2:-1])
    if replay != stolen:
        fail(f"the shim replays {replay.hex()}, expected the stolen {stolen.hex()}")
    print(f"ok  shim: load_path from {want_slot}, MODREF from {r['wm']}, "
          f"ctx {{LdrGetDllHandle {want[0]:#x}, LdrLoadDll {want[1]:#x}, "
          f"NtProtectVirtualMemory {want[2]:#x}}}, detour at {calls[0].op_str}, "
          f"replays '{text[-2]}', resumes at {base + r['resume']:#x}")
    print(f"PASS {os.path.basename(patched_path)}: hook {hook_rva:#x}, payload {payload_rva:#x}")


if __name__ == '__main__':
    main()
