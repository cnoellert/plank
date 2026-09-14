#!/usr/bin/env python3
"""Join bounded, numeric Client traces by media PTS using one monotonic clock."""
import argparse
import json
import re
from collections import Counter, defaultdict
from pathlib import Path

COLUMNS = 'time_ns pts_us frame stage key bytes depth duration_ns'.split()


def read_traces(text):
    active, complete = {}, []
    for line in text.splitlines():
        match = re.search(r'PLANK frame-flow begin lane=(\w+) id=(\d+) rows=(\d+)', line)
        if match:
            key = (match[1], int(match[2]))
            if key in active:
                raise ValueError('Duplicate trace header')
            active[key] = {'lane': key[0], 'id': key[1], 'count': int(match[3]), 'rows': []}
            continue
        match = re.search(r'PLANK frame-flow row lane=(\w+) id=(\d+) data=([-\d,]+)', line)
        if match:
            key = (match[1], int(match[2]))
            if key not in active:
                raise ValueError('Row without trace header')
            values = list(map(int, match[3].split(',')))
            if len(values) != len(COLUMNS):
                raise ValueError('Wrong column count')
            active[key]['rows'].append(dict(zip(COLUMNS, values)))
            continue
        match = re.search(r'PLANK frame-flow end lane=(\w+) id=(\d+)', line)
        if match:
            key = (match[1], int(match[2]))
            if key not in active:
                raise ValueError('End without trace header')
            trace = active.pop(key)
            if trace['count'] != len(trace['rows']):
                raise ValueError('Incomplete trace row count')
            complete.append(trace)
    if active:
        raise ValueError('Unflushed trace: wait until disconnect cleanup completes')
    return complete


def summarize(traces):
    receives = [t for t in traces if t['lane'] == 'receive' and t['rows']]
    if not receives:
        raise ValueError('No complete receive trace')
    receive = max(receives, key=lambda t: t['id'])
    start = min(r['time_ns'] for r in receive['rows'])
    end = max(r['time_ns'] for r in receive['rows'])
    # Include delayed decode/render and pre-receive GPU waits. PTS matching
    # remains necessary: wall/monotonic range alone is not frame identity.
    lanes = {receive['lane']: receive['rows']}
    for lane in ('decode', 'render'):
        lanes[lane] = sorted([r for t in traces if t['lane'] == lane
                              for r in t['rows']
                              if start - 1000000000 <= r['time_ns'] <= end + 1000000000],
                             key=lambda r: r['time_ns'])
        if not lanes[lane]:
            raise ValueError('Missing matching ' + lane + ' trace')
    by_pts = defaultdict(list)
    for lane, rows in lanes.items():
        for row in rows:
            if row['pts_us'] >= 0:
                by_pts[row['pts_us'] // 1000].append((lane, row))
    incoming = sorted(receive['rows'], key=lambda r: r['time_ns'])
    ambiguous = [pts for pts, entries in by_pts.items()
                 if sum(lane == 'receive' for lane, _ in entries) > 1]
    examples = []
    for index, key in enumerate(incoming):
        if key['key'] != 1:
            continue
        frames = []
        for source in incoming[index:index + 6]:
            pts = source['pts_us'] // 1000
            if pts in ambiguous:
                continue
            events = sorted(by_pts[pts], key=lambda pair: pair[1]['time_ns'])
            frames.append({'frame': source['frame'], 'key': source['key'],
                           'bytes': source['bytes'], 'pts_us': source['pts_us'],
                           'receive_from_key_ms': round((source['time_ns'] - key['time_ns']) / 1e6, 3),
                           'events': [{'lane': lane, 'stage': r['stage'],
                                       'from_receive_ms': round((r['time_ns'] - source['time_ns']) / 1e6, 3),
                                       'depth': r['depth'], 'duration_ms': round(r['duration_ns'] / 1e6, 3)}
                                      for lane, r in events]})
        waits = [r['duration_ns'] / 1e6 for r in lanes['render'] if r['stage'] == 4
                 and key['time_ns'] - 100000000 <= r['time_ns'] <= key['time_ns'] + 200000000]
        examples.append({'key_frame': key['frame'],
                         'key_receive_gap_ms': round((key['time_ns'] - incoming[index-1]['time_ns']) / 1e6, 3) if index else None,
                         'max_nearby_gpu_wait_ms': round(max(waits, default=0), 3),
                         'frames': frames})
    return {'receive_frames': len(incoming), 'duration_s': round((end-start)/1e9, 3),
            'stage_counts': {lane: dict(Counter(r['stage'] for r in rows)) for lane, rows in lanes.items()},
            'ambiguous_pts_ms': ambiguous, 'keyframe_windows': examples,
            'notes': ['Stages: 1 receive, 2 decode, 3 enqueue, 4 GPU wait, 5 render begin, 6 render end, 7 drop.',
                      'PTS joins use milliseconds because existing rendered AVFrame PTS has millisecond precision.',
                      'Receive is after complete KyProto reconstruction; wire arrival and FEC duration are not measured.',
                      'GPU-wait duration ends before a frame is chosen; nearby association is not frame ownership.',
                      'No payload, input events, credentials, or addresses are recorded.',
                      'Elapsed CPU-side render completion is not a compositor presentation timestamp.']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', type=Path)
    args = parser.parse_args()
    print(json.dumps(summarize(read_traces(args.log.read_text())), indent=2))
