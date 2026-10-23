#!/usr/bin/env python3
"""Frame statistics from a frametap CSV (see tools/perf/frametap.m).

    tools/perf/frametap-stats.py FILE... [--skip SECONDS]

One line of key=value pairs for the file with the most shown frames (the game's process; the
others, if any, are processes that drew a few things). The frame times are the intervals
between the presented times of consecutive drawables, after --skip seconds from the first
one (warm-up). 1 % and 0.1 % lows are the frame rate of the slowest 1 % and 0.1 % of frames.
"""
import argparse
import sys


def load(path):
    shown, acquired, dropped = [], [], 0
    with open(path) as f:
        for line in f:
            if line.startswith("#") or line.startswith("kind"):
                continue
            kind, _, ns = line.strip().partition(",")
            if not ns:
                continue
            if kind == "P":
                shown.append(int(ns))
            elif kind == "A":
                acquired.append(int(ns))
            elif kind == "D":
                dropped += 1
    shown.sort()
    return shown, acquired, dropped


def pct(sorted_values, q):
    return sorted_values[min(len(sorted_values) - 1, int(q * len(sorted_values)))]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--skip", type=float, default=0.0)
    a = ap.parse_args()
    best = max((load(p) + (p,) for p in a.files), key=lambda t: len(t[0]))
    shown, acquired, dropped, _ = best
    if len(shown) < 20:
        print("tap_frames=0")
        return 1
    cut = shown[0] + int(a.skip * 1e9)
    window = [t for t in shown if t >= cut]
    if len(window) < 20:
        print("tap_frames=0")
        return 1
    deltas = sorted((b - x) / 1e6 for x, b in zip(window, window[1:]) if b > x)
    n1 = max(1, len(deltas) // 100)
    n01 = max(1, len(deltas) // 1000)
    low1 = 1000.0 / (sum(deltas[-n1:]) / n1)
    low01 = 1000.0 / (sum(deltas[-n01:]) / n01)
    secs = (window[-1] - window[0]) / 1e9
    print(f"tap_frames={len(window)} tap_fps={(len(window) - 1) / secs:.1f} tap_p50_ms={pct(deltas, .5):.3f} "
          f"tap_p95_ms={pct(deltas, .95):.3f} tap_p99_ms={pct(deltas, .99):.3f} tap_p999_ms={pct(deltas, .999):.3f} "
          f"tap_low1_fps={low1:.1f} tap_low01_fps={low01:.1f} tap_dropped={dropped} tap_seconds={secs:.1f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
