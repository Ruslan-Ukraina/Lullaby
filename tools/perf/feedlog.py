#!/usr/bin/env python3 -I
"""Records, all the time a game presents, the on-screen frame intervals of every 10 s (from the present feed, ENG-07)
beside the latest Reflex line (game fps, frames shown per game frame, GPU and CPU ms, latency, held ms).
One CSV row per window in scratch/perf/feedlog.csv: time, shown fps, p50, p95, p99, max, std, within 1 ms of the
median, game fps, shown each, gpu ms, cpu ms, latency ms, held ms. Read with: tail -f scratch/perf/feedlog.csv
"""
import glob, os, re, statistics as st, struct, subprocess, sys, time

RUN = os.path.expanduser("~/Library/Application Support/Steam/steamapps/compatdata/4022369388/pfx/.sevo/run")
NV = os.path.expanduser("~/Library/Application Support/lullaby/launchers/app-4022369388/lullaby-nvapi.log")
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "scratch/perf/feedlog.csv")
RING = 256
HEAD, ENTRY = struct.Struct("<QQQQ"), struct.Struct("<QQ")
MAGIC = 0x544E45535250424C


def read(path):
    try:
        data = open(path, "rb").read(HEAD.size + RING * ENTRY.size)
    except OSError:
        return None
    if len(data) < HEAD.size + RING * ENTRY.size or HEAD.unpack_from(data, 0)[0] != MAGIC:
        return None
    return HEAD.unpack_from(data, 0)[3], [ENTRY.unpack_from(data, HEAD.size + i * ENTRY.size)[1] for i in range(RING)]


def memory():
    """vm_stat counters (pages) and the swap in use (MB): the paging that a game with ~20 GB on a 24 GB Mac may cause."""
    try:
        out = subprocess.run(["vm_stat"], capture_output=True, text=True, timeout=5).stdout
        v = {k.strip(): int(x.strip().rstrip(".")) for k, x in (l.split(":", 1) for l in out.splitlines() if ":" in l and l.split(":", 1)[1].strip().rstrip(".").isdigit())}
        sw = subprocess.run(["sysctl", "-n", "vm.swapusage"], capture_output=True, text=True, timeout=5).stdout
        used = re.search(r"used = ([0-9.,]+)M", sw)
        return v.get("Swapins", 0), v.get("Swapouts", 0), v.get("Pageouts", 0), v.get("Pages occupied by compressor", 0), v.get("Pages free", 0), float(used.group(1).replace(",", ".")) if used else 0
    except Exception:
        return 0, 0, 0, 0, 0, 0


def last_reflex():
    try:
        with open(NV, "rb") as f:
            f.seek(0, 2); f.seek(max(0, f.tell() - 4000))
            lines = f.read().decode(errors="replace").splitlines()
    except OSError:
        return ""
    for l in reversed(lines):
        m = re.search(r"([0-9.]+) fps \(game frames, ([0-9.]+) shown each\), held ([0-9.]+) ms a frame, PC latency ([0-9.]+) ms, GPU ([0-9.]+) ms, CPU ([0-9.]+) ms", l)
        if m:
            fps, shown, held, lat, gpu, cpu = m.groups()
            return f"{fps},{shown},{gpu},{cpu},{lat},{held}"
    return ",,,,,"


os.makedirs(os.path.dirname(OUT), exist_ok=True)
if not os.path.exists(OUT):
    open(OUT, "w").write("time,shown_fps,p50,p95,p99,max,std,within1ms,game_fps,shown_each,gpu_ms,cpu_ms,latency_ms,held_ms,swapins_s,swapouts_s,pageouts_s,compressor_pages,free_pages,swap_used_mb\n")
seen, times, window_start, path = set(), [], time.time(), None
mem0, mem_t0 = memory(), time.time()
while True:
    best = None
    for p in glob.glob(os.path.join(RUN, "*.present")):
        r = read(p)
        if r and (best is None or r[0] > best[1]):
            best = (p, r[0])
    if best and best[1] > 20:
        if best[0] != path:
            path, seen, times = best[0], set(), []
        r = read(path)
        if r:
            for t in r[1]:
                if t and t not in seen:
                    seen.add(t); times.append(t)
    if time.time() - window_start >= 10:
        window_start = time.time()
        if len(times) > 20:
            ts = sorted(times); iv = [(b - a) / 1e6 for a, b in zip(ts, ts[1:]) if b - a < 5e8]
            if len(iv) > 20:
                s = sorted(iv); n = len(s); med = s[n // 2]
                row = (f"{time.strftime('%H:%M:%S')},{1000 / st.mean(iv):.1f},{med:.2f},{s[int(n * .95)]:.2f},{s[int(n * .99)]:.2f},"
                       f"{s[-1]:.1f},{st.pstdev(iv):.2f},{sum(1 for x in iv if abs(x - med) <= 1) / n:.2f},{last_reflex()}")
                m, dt = memory(), max(1.0, time.time() - mem_t0)
                row += f",{(m[0] - mem0[0]) / dt:.0f},{(m[1] - mem0[1]) / dt:.0f},{(m[2] - mem0[2]) / dt:.0f},{m[3]},{m[4]},{m[5]:.0f}"
                open(OUT, "a").write(row + "\n")
        times = []
        seen = set(list(seen)[-RING:])
        mem0, mem_t0 = memory(), time.time()
    time.sleep(0.5)
