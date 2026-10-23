#!/usr/bin/env python3
"""Frame rate of a running game from outside, through Dormison's present counter.

Dormison keeps a page per drawing process at <prefix>/.sevo/run/<pid>.stats
(dlls/winemac.drv/sevo_stats.h): a frame counter and the times of the newest 994
frames. This samples it for a while and prints the average rate, the 1 % low and
frame time percentiles. Nothing touches the game.

    perf/frames.py <compatdata dir or prefix> [--seconds 20] [--label NAME] [--csv FILE]
"""
import argparse
import glob
import os
import struct
import sys
import time

MAGIC = 0x5345564F53545331
HEAD = struct.Struct("<QQQQQQIIII32sQQII")  # up to ring[] (120 bytes)
CAP = 994


def read(path):
    with open(path, "rb") as f:
        data = f.read(4096)
    (magic, frames, drawables, last_ns, start_ns, window, version, pid, source, appid,
     exe, beat, ring_head, ring_cap, _res) = HEAD.unpack_from(data, 0)
    if magic != MAGIC:
        return None
    ring = struct.unpack_from(f"<{CAP}I", data, HEAD.size)
    return dict(frames=frames, drawables=drawables, start_ns=start_ns, pid=pid, source=source,
                appid=appid, exe=exe.split(b"\0")[0].decode(errors="replace"), ring_head=ring_head,
                ring_cap=ring_cap, ring=ring, last_ns=last_ns)


def count(p):
    # The rate to read: the presenter's frames, else D3DMetal's drawables, else presents.
    return p["drawables"] if p["drawables"] and p["source"] != 2 else p["frames"]


def pages(prefix):
    run = os.path.join(prefix, ".sevo", "run")
    out = []
    for path in glob.glob(os.path.join(run, "*.stats")):
        p = read(path)
        if p and count(p) > 0:
            out.append((path, p))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("prefix")
    ap.add_argument("--seconds", type=float, default=20)
    ap.add_argument("--label", default="")
    ap.add_argument("--csv")
    a = ap.parse_args()
    prefix = a.prefix if os.path.isdir(os.path.join(a.prefix, ".sevo")) else os.path.join(a.prefix, "pfx")
    found = pages(prefix)
    if not found:
        sys.exit(f"no drawing process in {prefix}")
    path, p0 = max(found, key=lambda item: count(item[1]))
    t0 = time.clock_gettime_ns(time.CLOCK_UPTIME_RAW)
    time.sleep(a.seconds)
    p1 = read(path)
    t1 = time.clock_gettime_ns(time.CLOCK_UPTIME_RAW)
    if not p1:
        sys.exit("the game's page went away")
    fps = (count(p1) - count(p0)) / ((t1 - t0) / 1e9)
    # Frame times from the ring, only frames inside the sample window, one short of the head.
    head = p1["ring_head"] - 1
    first = max(p0["ring_head"], head - CAP + 1)
    stamps = [p1["ring"][i % CAP] for i in range(first, head)]
    times = sorted((b - a) / 1000 for a, b in zip(stamps, stamps[1:]) if b >= a)
    def pct(q):
        return times[min(len(times) - 1, int(q * len(times)))] if times else 0
    low = 1000 / (sum(times[int(0.99 * len(times)):]) / max(1, len(times) - int(0.99 * len(times)))) if times else 0
    row = dict(label=a.label, exe=p1["exe"], source={0: "none", 1: "surface", 2: "presenter"}.get(p1["source"], "?"),
               drawables=int(p1["drawables"] > 0), fps=round(fps, 1), low1=round(low, 1),
               p50_ms=round(pct(0.5), 2), p95_ms=round(pct(0.95), 2), p99_ms=round(pct(0.99), 2),
               frames=len(times) + 1, seconds=a.seconds)
    print(" ".join(f"{k}={v}" for k, v in row.items()))
    if a.csv:
        new = not os.path.exists(a.csv)
        with open(a.csv, "a") as f:
            if new:
                f.write(",".join(row) + "\n")
            f.write(",".join(str(v) for v in row.values()) + "\n")


if __name__ == "__main__":
    main()
