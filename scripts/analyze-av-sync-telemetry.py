#!/usr/bin/env python3

"""Analyze opt-in StationConnect client audio/video clock telemetry."""

from __future__ import annotations

import argparse
import math
import re
import sys
from dataclasses import dataclass


AUDIO_PATTERN = re.compile(
    r"StationConnect A/V audio clock: media=(\d+) submit=(\d+) "
    r"queue=(-?\d+) device=(-?\d+) pending=(-?\d+) frame=(\d+)"
)
VIDEO_PATTERN = re.compile(
    r"StationConnect A/V video clock: media=(\d+) render=(\d+) "
    r"queue=(\d+) renderer=(\d+)"
)
TICK_WRAP = 1 << 32


@dataclass
class Point:
    """One media-clock sample and its estimated client presentation time."""

    media_ms: int
    presentation_ms: int


def unwrap_ticks(raw_ticks: list[int]) -> list[int]:
    """Expand wrapping SDL 32-bit millisecond ticks."""

    output: list[int] = []
    epoch = 0
    previous = raw_ticks[0]
    for ticks in raw_ticks:
        if ticks < previous and previous - ticks > TICK_WRAP // 2:
            epoch += TICK_WRAP
        output.append(epoch + ticks)
        previous = ticks
    return output


def latest_segment(points: list[Point]) -> list[Point]:
    """Keep the most recent session, detected by a media-clock reset."""

    start = 0
    for index in range(1, len(points)):
        if points[index].media_ms < points[index - 1].media_ms:
            start = index
    return points[start:]


def percentile(values: list[float], percent: int) -> float:
    """Return the nearest-rank percentile."""

    if not values:
        return 0.0
    ordered = sorted(values)
    rank = max(1, math.ceil(len(ordered) * percent / 100))
    return ordered[rank - 1]


def clock_series(points: list[Point], warmup_ms: int) -> list[tuple[float, float]]:
    """Return client elapsed time and clock error after warmup."""

    initial_presentation = points[0].presentation_ms
    retained = [
        point
        for point in points
        if point.presentation_ms - initial_presentation >= warmup_ms
    ]
    if len(retained) < 2:
        raise ValueError("fewer than two telemetry samples remain after warmup")
    first = retained[0]
    return [
        (
            float(point.presentation_ms - first.presentation_ms),
            float(
                (point.presentation_ms - first.presentation_ms)
                - (point.media_ms - first.media_ms)
            ),
        )
        for point in retained
    ]


def interpolate(series: list[tuple[float, float]], elapsed_ms: float) -> float:
    """Linearly interpolate clock error at a client elapsed time."""

    for index in range(1, len(series)):
        before = series[index - 1]
        after = series[index]
        if elapsed_ms <= after[0]:
            span = after[0] - before[0]
            if span == 0:
                return after[1]
            fraction = (elapsed_ms - before[0]) / span
            return before[1] + fraction * (after[1] - before[1])
    return series[-1][1]


def linear_slope(series: list[tuple[float, float]]) -> float:
    """Return the least-squares clock-error slope in milliseconds per millisecond."""

    mean_elapsed = sum(point[0] for point in series) / len(series)
    mean_error = sum(point[1] for point in series) / len(series)
    denominator = sum((point[0] - mean_elapsed) ** 2 for point in series)
    if denominator == 0:
        return 0.0
    return sum(
        (point[0] - mean_elapsed) * (point[1] - mean_error)
        for point in series
    ) / denominator


def parse_log(lines: list[str]) -> tuple[list[Point], list[Point]]:
    """Parse audio and video samples from Moonlight log lines."""

    audio_raw: list[tuple[int, int, int]] = []
    video_raw: list[tuple[int, int]] = []
    for line in lines:
        audio = AUDIO_PATTERN.search(line)
        if audio:
            media, submit, queued, device, _pending, frame = map(int, audio.groups())
            if queued >= 0 and device >= 0:
                audio_raw.append((media, submit, max(queued - frame, 0) + device))
            continue
        video = VIDEO_PATTERN.search(line)
        if video:
            media, render, _queued, _renderer = map(int, video.groups())
            video_raw.append((media, render))

    if not audio_raw or not video_raw:
        raise ValueError("log does not contain both audio and video telemetry")

    audio_ticks = unwrap_ticks([sample[1] for sample in audio_raw])
    video_ticks = unwrap_ticks([sample[1] for sample in video_raw])
    audio_points = [
        Point(sample[0], ticks + sample[2])
        for sample, ticks in zip(audio_raw, audio_ticks)
    ]
    video_points = [
        Point(sample[0], ticks)
        for sample, ticks in zip(video_raw, video_ticks)
    ]
    return latest_segment(audio_points), latest_segment(video_points)


def main() -> int:
    """Run the command-line telemetry analysis."""

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", help="Moonlight log file, or - for standard input")
    parser.add_argument("--warmup-seconds", type=float, default=10.0)
    parser.add_argument("--min-duration-seconds", type=float, default=0.0)
    parser.add_argument("--max-relative-drift-ms", type=float)
    parser.add_argument("--max-projected-relative-drift-ms-per-hour", type=float)
    args = parser.parse_args()

    if args.warmup_seconds < 0 or args.min_duration_seconds < 0:
        parser.error("durations cannot be negative")
    if args.max_relative_drift_ms is not None and args.max_relative_drift_ms < 0:
        parser.error("relative drift limit cannot be negative")
    if (
        args.max_projected_relative_drift_ms_per_hour is not None
        and args.max_projected_relative_drift_ms_per_hour < 0
    ):
        parser.error("projected relative drift limit cannot be negative")
    try:
        if args.log == "-":
            lines = sys.stdin.readlines()
        else:
            with open(args.log, encoding="utf-8", errors="replace") as log_file:
                lines = log_file.readlines()
        audio_points, video_points = parse_log(lines)
        audio_clock = clock_series(audio_points, round(args.warmup_seconds * 1000))
        video_clock = clock_series(video_points, round(args.warmup_seconds * 1000))
    except (OSError, ValueError) as error:
        print(f"telemetry analysis failed: {error}", file=sys.stderr)
        return 1

    duration_ms = min(audio_clock[-1][0], video_clock[-1][0])
    audio_error = interpolate(audio_clock, duration_ms)
    video_error = interpolate(video_clock, duration_ms)
    relative_drift_ms = audio_error - video_error
    endpoint_projection = (
        relative_drift_ms * 3_600_000 / duration_ms if duration_ms else 0.0
    )
    audio_fit = [point for point in audio_clock if point[0] <= duration_ms]
    video_fit = [point for point in video_clock if point[0] <= duration_ms]
    relative_slope = linear_slope(audio_fit) - linear_slope(video_fit)
    fitted_relative_drift_ms = relative_slope * duration_ms
    projected_drift = relative_slope * 3_600_000
    audio_jitter = [
        abs(audio_clock[index][1] - audio_clock[index - 1][1])
        for index in range(1, len(audio_clock))
    ]
    video_jitter = [
        abs(video_clock[index][1] - video_clock[index - 1][1])
        for index in range(1, len(video_clock))
    ]

    print(f"audio_samples={len(audio_clock)}")
    print(f"video_samples={len(video_clock)}")
    print(f"measurement_duration_seconds={duration_ms / 1000:.3f}")
    print(f"audio_clock_jitter_p95_ms={percentile(audio_jitter, 95):.3f}")
    print(f"video_clock_jitter_p95_ms={percentile(video_jitter, 95):.3f}")
    print(f"relative_av_drift_ms={relative_drift_ms:.3f}")
    print(f"fitted_relative_av_drift_ms={fitted_relative_drift_ms:.3f}")
    print(f"projected_relative_av_drift_ms_per_hour={projected_drift:.3f}")
    print(
        "endpoint_projected_relative_av_drift_ms_per_hour="
        f"{endpoint_projection:.3f}"
    )
    print("absolute_av_offset=not_measured")

    if duration_ms < args.min_duration_seconds * 1000:
        print("av_sync_gate=fail (insufficient duration)")
        return 1
    if (
        args.max_relative_drift_ms is not None
        and abs(relative_drift_ms) > args.max_relative_drift_ms
    ):
        print("av_sync_gate=fail (relative drift)")
        return 1
    if (
        args.max_projected_relative_drift_ms_per_hour is not None
        and abs(projected_drift) > args.max_projected_relative_drift_ms_per_hour
    ):
        print("av_sync_gate=fail (projected relative drift)")
        return 1
    print("av_sync_gate=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
