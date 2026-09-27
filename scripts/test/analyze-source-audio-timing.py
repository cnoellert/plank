#!/usr/bin/env python3
"""Summarize timestamp-aware enqueue estimates, not acoustic lip-sync acceptance."""
import argparse
import json
import re
import statistics


def latest_samples(lines):
    segments = [[]]
    for line in lines:
        if "PLANK A/V source timing begin:" in line:
            segments.append([])
        if "PLANK A/V source timing:" not in line:
            continue
        fields = dict((key, int(value)) for key, value in
                      re.findall(r"([a-z_]+)=(-?\d+)", line.split("source timing:", 1)[1]))
        if not {"observe_ms", "common", "valid", "estimated_lead_us", "queue_ms",
                "device_ms", "resampler_us", "gaps", "correction_ppm"} <= fields.keys():
            raise ValueError("incomplete source timing sample")
        if segments[-1] and fields["observe_ms"] <= segments[-1][-1]["observe_ms"]:
            segments.append([])
        segments[-1].append(fields)
    return next((segment for segment in reversed(segments) if segment), [])


def summarize(samples, warmup_seconds=10):
    if not samples:
        raise ValueError("no source timing samples")
    cutoff = samples[0]["observe_ms"] + warmup_seconds * 1000
    retained = [s for s in samples if s["observe_ms"] >= cutoff]
    valid = [s for s in retained if s["common"] == 1 and s["valid"] == 1]
    if len(valid) < 2:
        raise ValueError("need at least two valid common-clock samples after warmup")
    seconds = [(s["observe_ms"] - valid[0]["observe_ms"]) / 1000 for s in valid]
    lead = [s["estimated_lead_us"] / 1000 for s in valid]
    mean_t, mean_lead = statistics.mean(seconds), statistics.mean(lead)
    denominator = sum((t - mean_t) ** 2 for t in seconds)
    if denominator == 0:
        raise ValueError("zero observation duration")
    slope = sum((t - mean_t) * (value - mean_lead) for t, value in zip(seconds, lead)) / denominator
    return {
        "measurement": "estimated enqueue-to-output alignment; not acoustic lip sync",
        "positive_lead_means": "audio ahead of video",
        "duration_seconds": seconds[-1],
        "valid_samples": len(valid), "invalid_samples": len(retained) - len(valid),
        "estimated_lead_ms_median": statistics.median(lead),
        "estimated_lead_ms_min": min(lead), "estimated_lead_ms_max": max(lead),
        "estimated_lead_change_ms": lead[-1] - lead[0],
        "fitted_estimated_lead_change_ms_per_hour": slope * 3600,
        "queue_ms_max": max(s["queue_ms"] for s in valid),
        "device_ms_range": [min(s["device_ms"] for s in valid), max(s["device_ms"] for s in valid)],
        "source_gap_count": valid[-1]["gaps"] - valid[0]["gaps"],
        "correction_ppm_range": [min(s["correction_ppm"] for s in valid), max(s["correction_ppm"] for s in valid)],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log")
    parser.add_argument("--warmup-seconds", type=float, default=10)
    args = parser.parse_args()
    if args.warmup_seconds < 0:
        parser.error("warmup must be nonnegative")
    try:
        with open(args.log, encoding="utf-8", errors="replace") as log:
            result = summarize(latest_samples(log), args.warmup_seconds)
    except (ValueError, OSError) as error:
        parser.exit(1, f"source timing analysis failed: {error}\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
