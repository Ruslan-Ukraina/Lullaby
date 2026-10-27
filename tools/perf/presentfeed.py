#!/usr/bin/env python3 -I
"""On-screen frame intervals of a game from Lullaby's present feed (ENG-07, LULLABY_PRESENT_FEED=1).

The feed (<prefix>/.sevo/run/<Windows pid>.present) holds, for each of the last 256 drawables, the moment it reached
the screen (addPresentedHandler). Unlike tools/perf/frames.py (the moments of the present call) these are what the player
sees. Waits for a feed that starts presenting, lets the game settle, then reads the ring for a while.

  [PRESENT_FEED_APP=<app id>] tools/perf/presentfeed.py [--settle 45] [--seconds 30] [--label NAME] [--csv FILE] [--timeout 240]
prints: label shown fps p50 p95 p99 max std, and the share of intervals within 1 ms of the median.
"""
import argparse, glob, mmap, os, statistics as st, struct, sys, time

APP = os.environ.get("PRESENT_FEED_APP", "4022369388")  # the Steam app id whose prefix holds the feed (default RE9)
RUN = os.path.expanduser(f"~/Library/Application Support/Steam/steamapps/compatdata/{APP}/pfx/.sevo/run")
RING = 256
HEAD = struct.Struct("<QQQQ")  # magic, version, acquired, presented
ENTRY = struct.Struct("<QQ")   # acquire_ns, present_ns
MAGIC = 0x544E45535250424C


def read(path):
    try:
        with open(path, "rb") as f:
            data = f.read(HEAD.size + RING * ENTRY.size)
    except OSError:
        return None
    if len(data) < HEAD.size + RING * ENTRY.size:
        return None
    magic, _, acquired, presented = HEAD.unpack_from(data, 0)
    if magic != MAGIC:
        return None
    return presented, [ENTRY.unpack_from(data, HEAD.size + i * ENTRY.size)[1] for i in range(RING)]


def busiest():
    best = None
    for p in glob.glob(os.path.join(RUN, "*.present")):
        r = read(p)
        if r and (best is None or r[0] > best[1]):
            best = (p, r[0])
    return best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--settle", type=float, default=45)
    ap.add_argument("--seconds", type=float, default=30)
    ap.add_argument("--label", default="feed")
    ap.add_argument("--csv")
    ap.add_argument("--timeout", type=float, default=240)
    a = ap.parse_args()
    t0 = time.time()
    path = None
    while time.time() - t0 < a.timeout:
        b = busiest()
        if b and b[1] > 20:
            first = b
            time.sleep(1.5)
            c = busiest()
            if c and c[0] == first[0] and c[1] > first[1]:
                path = c[0]
                break
        time.sleep(1)
    if not path:
        print(f"{a.label}: no present feed"); return 1
    time.sleep(a.settle)
    seen = set(); times = []
    end = time.time() + a.seconds
    while time.time() < end:
        r = read(path)
        if r:
            for t in r[1]:
                if t and t not in seen:
                    seen.add(t); times.append(t)
        time.sleep(0.5)
    times.sort()
    iv = [(b - a_) / 1e6 for a_, b in zip(times, times[1:])]
    iv = [x for x in iv if x < 500]
    if len(iv) < 20:
        print(f"{a.label}: too few frames ({len(iv)})"); return 1
    s = sorted(iv); n = len(s)
    q = lambda p: s[min(n - 1, int(n * p))]
    med = q(0.5)
    flat = sum(1 for x in iv if abs(x - med) <= 1.0) / n
    line = f"{a.label}: shown={n + 1} fps={1000 / st.mean(iv):.1f} p50={med:.2f} p95={q(0.95):.2f} p99={q(0.99):.2f} max={s[-1]:.2f} std={st.pstdev(iv):.2f} within1ms={flat:.0%}"
    print(line)
    if a.csv:
        with open(a.csv, "a") as f:
            f.write(f"{a.label},{n + 1},{1000 / st.mean(iv):.2f},{med:.2f},{q(0.95):.2f},{q(0.99):.2f},{s[-1]:.2f},{st.pstdev(iv):.2f},{flat:.3f}\n")
    return 0


sys.exit(main())
