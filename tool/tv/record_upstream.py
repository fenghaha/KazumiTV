#!/usr/bin/env python3
"""Record an already-merged upstream revision, without editing its version."""
import argparse
import json
import pathlib
import re
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--ref", default="upstream/main")
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[2]


def git(*argv):
    return subprocess.check_output(["git", *argv], cwd=root, text=True).strip()


commit = git("rev-parse", args.ref + "^{commit}")
subprocess.run(["git", "merge-base", "--is-ancestor", commit, "HEAD"],
               cwd=root, check=True)
pubspec = git("show", commit + ":pubspec.yaml")
endpoints = git("show", commit + ":lib/request/config/api_endpoints.dart")
record_path = root / "tool/tv/upstream.json"
record = json.loads(record_path.read_text())
record.update(
    commit=commit,
    version=re.search(r"^version:\s*(\S+)", pubspec, re.M).group(1),
    apiLevel=int(re.search(r"apiLevel\s*=\s*(\d+)", endpoints).group(1)),
)
record_path.write_text(json.dumps(record, indent=2) + "\n")
print(f"Recorded merged upstream {commit}; run check_upstream.py and regressions.")
