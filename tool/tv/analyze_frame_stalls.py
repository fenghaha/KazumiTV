#!/usr/bin/env python3
"""Inspect saved frame timings offline. Adjacency is evidence, not root cause."""
import argparse
import json
from pathlib import Path

from profile_playback import summarize


def analyze(frames):
    if len(frames) < 2 or any(b['vsyncUs'] <= a['vsyncUs']
                              for a, b in zip(frames, frames[1:])):
        raise ValueError('at least two strictly increasing frame timestamps are required')
    result = summarize(frames)
    origin = frames[0]['vsyncUs']
    ui = [frame for frame in frames if frame['buildUs'] > 50000]
    raster = [frame for frame in frames if frame['rasterUs'] > 50000]
    gaps = []
    for before, after in zip(frames, frames[1:]):
        interval = (after['vsyncUs'] - before['vsyncUs']) / 1000
        if interval > 50:
            gaps.append({
                'relative_s': round((before['vsyncUs'] - origin) / 1e6, 3),
                'interval_ms': round(interval, 3),
                'before_ui_ms': before['buildUs'] / 1000,
                'after_ui_ms': after['buildUs'] / 1000,
                'before_raster_ms': before['rasterUs'] / 1000,
                'after_raster_ms': after['rasterUs'] / 1000,
            })
    result.update(
        ui_over_50ms_frames=len(ui),
        ui_over_100ms_frames=sum(frame['buildUs'] > 100000 for frame in ui),
        raster_over_50ms_frames=len(raster),
        long_intervals_adjacent_to_ui_over_33ms=sum(
            max(g['before_ui_ms'], g['after_ui_ms']) > 100 / 3 for g in gaps),
        long_intervals_adjacent_to_raster_over_33ms=sum(
            max(g['before_raster_ms'], g['after_raster_ms']) > 100 / 3 for g in gaps),
        worst_intervals=sorted(gaps, key=lambda gap: gap['interval_ms'], reverse=True)[:12],
        ui_spikes=[{'relative_s': round((frame['vsyncUs'] - origin) / 1e6, 3),
                    'ui_ms': frame['buildUs'] / 1000} for frame in ui],
        interpretation='UI values are wall time; native waits, GC and scheduling can contribute. '
                       'Adjacent slow frames do not prove text generation is the cause.',
    )
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('frames', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    value = json.loads(args.frames.read_text())
    result = analyze(value['frames'] if isinstance(value, dict) else value)
    text = json.dumps(result, ensure_ascii=False, indent=2)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text + '\n')
    print(json.dumps({key: val for key, val in result.items()
                      if key not in ('ui_spikes', 'worst_intervals')}))


if __name__ == '__main__':
    main()
