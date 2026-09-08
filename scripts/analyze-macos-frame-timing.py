#!/usr/bin/env python3
"""Read the last complete bounded Mac frame trace; emit numeric diagnostics.

This is an offline analysis, not part of the Host. Never interprets unlogged
frames or a send/recovery result as proof of network loss.
"""
import argparse
import datetime
import json
import re
import statistics
from pathlib import Path


def summary(values):
    values = sorted(values)
    if not values:
        return {"count": 0}
    return {"count": len(values), "mean": round(statistics.mean(values), 3),
            "p50": round(values[len(values) // 2], 3),
            "p95": round(values[min(len(values) - 1, int(len(values) * .95))], 3),
            "max": round(values[-1], 3)}


def analyze(path):
    pending = None
    trace = None
    for line in Path(path).open():
        match = re.match(r"PLANK frame-timing begin wall-unix-ns=(\d+) mono-ns=(\d+) count=(\d+)", line)
        if match:
            pending = {"wall": int(match[1]), "origin": int(match[2]), "count": int(match[3]), "rows": []}
        elif pending and re.match(r"PLANK frame-timing \d+,", line):
            pending["rows"].append([int(v) for v in line.split(" ", 2)[2].split(",")])
        elif pending and line.startswith("PLANK frame-timing end"):
            trace, pending = pending, None
    if not trace or len(trace["rows"]) != trace["count"]:
        raise ValueError("No complete trace or mismatched record count")
    # index,capture,submit,complete,handled,sent,pts,number,bytes,inflight,forced,key,stage,result
    rows = trace["rows"]
    if any(len(r) != 14 or r[0] != i for i, r in enumerate(rows)):
        raise ValueError("Invalid trace columns/order")
    sent = sorted((r for r in rows if r[12] == 3), key=lambda r: r[5])
    keys = [r for r in sent if r[11]]
    drops = [r for r in sent if r[13] == 2]

    def seconds(ns):
        return round((ns - trace["origin"]) / 1e9, 6)

    def brief(r):
        return {"s": seconds(r[5]), "frame": r[7], "key": r[11], "forced": r[10],
                "bytes": r[8], "result": r[13], "encode_ms": round((r[3] - r[2]) / 1e6, 3),
                "callback_ms": round((r[4] - r[3]) / 1e6, 3),
                "send_ms": round((r[5] - r[4]) / 1e6, 3)}

    bursts = []
    for r in drops:
        if not bursts or r[5] - bursts[-1][-1][5] > 200000000:
            bursts.append([])
        bursts[-1].append(r)
    burst_details = []
    for burst in bursts[:20]:
        first = burst[0]
        preceding = [r for r in keys if r[5] < first[5]]
        key = preceding[-1] if preceding else None
        burst_details.append({"first": brief(first), "drops": len(burst),
                              "last_s": seconds(burst[-1][5]),
                              "preceding_key": brief(key) if key else None,
                              "after_key_ms": round((first[5] - key[5]) / 1e6, 3) if key else None})
    timings = {}
    for name, group in (("key", keys), ("delta", [r for r in sent if not r[11]])):
        timings[name] = {"bytes": summary([r[8] for r in group]),
                         "encode_ms": summary([(r[3] - r[2]) / 1e6 for r in group]),
                         "callback_ms": summary([(r[4] - r[3]) / 1e6 for r in group]),
                         "send_ms": summary([(r[5] - r[4]) / 1e6 for r in group])}
    natural = [r for r in keys if not r[10]]
    natural_followed_by_drop = []
    for key in natural:
        following = next((r for r in drops if key[5] < r[5] <= key[5] + 150000000), None)
        if following:
            natural_followed_by_drop.append({"key": brief(key), "first_drop": brief(following)})
    return {"start_utc": datetime.datetime.fromtimestamp(trace["wall"] / 1e9, datetime.timezone.utc).isoformat(),
            "duration_s": seconds(rows[-1][1]) if rows else 0, "capture_count": len(rows),
            "stages": {str(s): sum(r[12] == s for r in rows) for s in range(6)},
            "send_or_recovery_drops": len(drops), "drop_bursts": len(bursts),
            "key_count": len(keys), "forced_key_count": sum(r[10] for r in keys),
            "key_enqueue_evictions": sum(r[13] == 2 for r in keys),
            "natural_key_count": len(natural),
            "natural_keys_followed_by_drop_within_150ms": len(natural_followed_by_drop),
            "natural_key_drop_examples": natural_followed_by_drop[:4],
            "timings": timings,
            "capture_callback_gap_ms": summary([(b[1] - a[1]) / 1e6 for a, b in zip(rows, rows[1:])]),
            "capture_pts_gap_ms": summary([(b[6] - a[6]) / 1e6 for a, b in zip(rows, rows[1:])]),
            "largest_keys": [brief(r) for r in sorted(keys, key=lambda r: r[8], reverse=True)[:8]],
            "first_drop_bursts": burst_details}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log")
    args = parser.parse_args()
    print(json.dumps(analyze(args.log), indent=2))
