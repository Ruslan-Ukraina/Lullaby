#!/usr/bin/env python3
"""A table from the stand's CSV files: median of the rounds, and how far the rounds stray.

    perf/report.py syncbench scratch/perf/syncbench.csv [--baseline MODE] [--limit 3]

syncbench: one row per (engine, mode, case): the median of the rounds for the rate and for
the latencies, the spread (the largest distance of a round from the median, in per cent),
and, with --baseline, the ratio to that mode's median. A spread over --limit per cent is
marked "noisy": a difference smaller than it is not a result.

The exit status is 1 when any row is noisy, so a script can refuse to draw conclusions.
"""
import argparse
import csv
import statistics
import sys
from collections import defaultdict


def spread(values):
    """Largest distance of a value from the median, in per cent of the median."""
    med = statistics.median(values)
    if not med:
        return 0.0
    return max(abs(v - med) for v in values) / med * 100


def syncbench(path, baseline, limit, keep_warmup=False):
    groups = defaultdict(lambda: defaultdict(list))
    by_round = {}  # (engine, mode, case, round) -> ops per second, for the paired ratios
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            if row.get("round") == "0" and not keep_warmup:
                continue
            key = (row["engine"], row["mode"], row["case"])
            for col in ("ops_per_s", "p50_us", "p99_us", "p999_us"):
                try:
                    groups[key][col].append(float(row[col]))
                except (KeyError, ValueError):
                    pass
            try:
                by_round[key + (row["round"],)] = float(row["ops_per_s"])
            except (KeyError, ValueError):
                pass
    if not groups:
        sys.exit(f"report: no rows in {path}")

    def paired(engine, mode, case):
        """Ratios of this mode to the baseline within each round: drift in the Mac's load
        moves both of a round's runs alike, so these stray less than the raw rates do."""
        out = []
        for (e, m, c, r), v in by_round.items():
            if (e, m, c) == (engine, mode, case) and by_round.get((engine, baseline, case, r)):
                out.append(v / by_round[(engine, baseline, case, r)])
        return out

    noisy = 0
    print("| engine | case | mode | rounds | ops/s | min-max | p50 us (min-max) | p99 us | spread % | vs baseline, paired (min-max) |")
    print("|---|---|---|---:|---:|---:|---:|---:|---:|---:|")
    for (engine, mode, case), cols in sorted(groups.items(), key=lambda kv: (kv[0][0], kv[0][2], kv[0][1])):
        ops = cols["ops_per_s"]
        sp = spread(ops)
        flag = ""
        if len(ops) > 1 and sp > limit:
            flag = " noisy"
            noisy += 1
        ratio = ""
        if baseline and mode != baseline:
            pr = paired(engine, mode, case)
            if pr:
                ratio = f"{statistics.median(pr):.2f}x ({min(pr):.2f}-{max(pr):.2f})"
        elif baseline:
            ratio = "1.00x"
        p50 = statistics.median(cols["p50_us"]) if cols["p50_us"] else 0
        p99 = statistics.median(cols["p99_us"]) if cols["p99_us"] else 0
        p50s = cols["p50_us"] or [0]
        print(f"| {engine} | {case} | {mode} | {len(ops)} | {statistics.median(ops):,.0f} | "
              f"{min(ops):,.0f}-{max(ops):,.0f} | {p50:.1f} ({min(p50s):.1f}-{max(p50s):.1f}) | {p99:.1f} | {sp:.1f}{flag} | {ratio} |")
    if noisy:
        print(f"\n{noisy} row(s) noisy (spread over {limit} %): more rounds, or a quieter Mac.", file=sys.stderr)
    return 1 if noisy else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("kind", choices=["syncbench"])
    ap.add_argument("csv")
    ap.add_argument("--baseline", default="")
    ap.add_argument("--limit", type=float, default=3.0)
    ap.add_argument("--with-warmup", action="store_true", help="count round 0 too")
    a = ap.parse_args()
    sys.exit(syncbench(a.csv, a.baseline, a.limit, a.with_warmup))


if __name__ == "__main__":
    main()
