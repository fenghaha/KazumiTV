#!/usr/bin/env python3
"""Capture full-screen TV frame cadence through a local profile VM service.

The authenticated service URI is read from a private file, never printed. This
tool does not seek, change settings, fetch media or operate the remote control.
"""
import argparse
from collections import defaultdict
import json
import math
import os
from pathlib import Path
import time
import urllib.parse
import urllib.request


def percentile(values, fraction):
    return sorted(values)[max(0, math.ceil(len(values) * fraction) - 1)]


def summarize(frames):
    if len(frames) < 2:
        return {"frames": len(frames), "error": "insufficient_frames"}
    intervals = [(b["vsyncUs"] - a["vsyncUs"]) / 1000
                 for a, b in zip(frames, frames[1:])]
    span = (frames[-1]["vsyncUs"] - frames[0]["vsyncUs"]) / 1e6
    return {
        "frames": len(frames), "span_s": round(span, 3),
        "fps": round((len(frames) - 1) / span, 2),
        "interval_p50_ms": round(percentile(intervals, .5), 2),
        "interval_p95_ms": round(percentile(intervals, .95), 2),
        "interval_p99_ms": round(percentile(intervals, .99), 2),
        "interval_over_35ms_percent": round(
            sum(v > 35 for v in intervals) * 100 / len(intervals), 2),
        "interval_over_50ms_count": sum(v > 50 for v in intervals),
        "ui_p95_ms": round(percentile([f["buildUs"] for f in frames], .95) / 1000, 2),
        "raster_p95_ms": round(percentile([f["rasterUs"] for f in frames], .95) / 1000, 2),
    }


def private_json(path, value):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w") as output:
        json.dump(value, output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--uri-file", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--seconds", type=float, default=30)
    parser.add_argument("--timeline", action="store_true")
    parser.add_argument("--cpu", action="store_true")
    args = parser.parse_args()
    if not 1 <= args.seconds <= 45:
        parser.error("capture must be 1 to 45 seconds")
    uri = args.uri_file.read_text().strip()
    parsed = urllib.parse.urlparse(uri)
    if parsed.scheme != "http" or parsed.hostname not in ("127.0.0.1", "localhost"):
        parser.error("only an adb-forwarded loopback VM service is allowed")
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def rpc(method, **parameters):
        url = uri.rstrip("/") + "/" + method + "?" + urllib.parse.urlencode(parameters)
        try:
            with opener.open(url, timeout=15) as response:
                message = json.load(response)
        except Exception as error:
            # An HTTP error can contain the private authentication URI.
            raise RuntimeError(f"VM request failed: {method} ({type(error).__name__})") from None
        if "error" in message:
            raise RuntimeError(f"VM method failed: {method}, code={message['error'].get('code')}")
        return message.get("result", message)

    vm = rpc("getVM")
    isolate = next(i["id"] for i in vm["isolates"] if i["name"] == "main")
    flags = rpc("getVMTimelineFlags") if args.timeline else None
    profiler = next(flag["valueAsString"] for flag in rpc("getFlagList")["flags"]
                    if flag["name"] == "profiler") if args.cpu else None
    if args.cpu and profiler != "true":
        rpc("setFlag", name="profiler", value="true")
    origin = rpc("getVMTimelineMicros")["timestamp"] if args.cpu else 0
    # The VM's HTTP interface accepts a bracketed comma list, not JSON strings.
    if args.timeline:
        rpc("setVMTimelineFlags", recordedStreams="[Dart,Embedder,GC]")
        rpc("clearVMTimeline")
    try:
        rpc("ext.kazumi.tv.frames", isolateId=isolate, reset="true")
        print(json.dumps({"event": "capture_started", "seconds": args.seconds}), flush=True)
        time.sleep(args.seconds)
        samples = rpc("ext.kazumi.tv.frames", isolateId=isolate)
        timeline = rpc("getVMTimeline") if args.timeline else {}
        cpu = {}
        if args.cpu:
            end = rpc("getVMTimelineMicros")["timestamp"]
            try:
                cpu = rpc("getCpuSamples", isolateId=isolate,
                          timeOriginMicros=origin, timeExtentMicros=end - origin)
            except RuntimeError:
                cpu = {"error": "cpu_profiler_unavailable"}
    finally:
        if args.timeline:
            rpc("setVMTimelineFlags", recordedStreams="[" + ",".join(flags["recordedStreams"]) + "]")
        if args.cpu and profiler != "true":
            rpc("setFlag", name="profiler", value=profiler)
    args.output.mkdir(parents=True, exist_ok=True)
    private_json(args.output / "frames.json", samples)
    private_json(args.output / "timeline.json", timeline)
    private_json(args.output / "cpu.json", cpu)
    result = summarize(samples["frames"])
    result.update(timeline_requested=args.timeline, cpu_requested=args.cpu)
    durations = defaultdict(list)
    stacks = defaultdict(list)
    for event in sorted(timeline.get("traceEvents", []), key=lambda event: event.get("ts", 0)):
        stack = stacks[(event.get("pid"), event.get("tid"))]
        if event.get("ph") == "X" and isinstance(event.get("dur"), (int, float)):
            durations[event.get("name", "unknown")].append(event["dur"] / 1000)
        elif event.get("ph") == "B":
            stack.append(event)
        elif event.get("ph") == "E" and stack:
            begin = stack.pop()
            durations[begin.get("name", "unknown")].append((event["ts"] - begin["ts"]) / 1000)
    result["timeline_durations"] = sorted(
        [{"name": name, "count": len(values), "total_ms": round(sum(values), 2),
          "p95_ms": round(percentile(values, .95), 2)} for name, values in durations.items()],
        key=lambda row: row["total_ms"], reverse=True)[:20]
    result["cpu_sample_count"] = cpu.get("sampleCount", 0)
    result["cpu_top_exclusive"] = [
        {"name": function.get("function", {}).get("name", "unknown"),
         "ticks": function.get("exclusiveTicks", 0)}
        for function in sorted(cpu.get("functions", []),
                               key=lambda function: function.get("exclusiveTicks", 0),
                               reverse=True)[:20]
    ]
    private_json(args.output / "summary.json", result)
    print(json.dumps(result, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
