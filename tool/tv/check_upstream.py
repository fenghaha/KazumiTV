#!/usr/bin/env python3
"""Ensure the TV presentation hasn't silently forked Kazumi's rule contract."""
import hashlib
import json
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[2]
base = json.loads((root / "tool/tv/upstream.json").read_text(encoding="utf-8"))
protected = [
    "lib/plugins", "lib/services/plugin", "lib/services/video_source",
    "lib/modules", "lib/repositories", "lib/request", "lib/webview",
    "lib/services/storage", "lib/services/player", "lib/utils/version.dart",
    "lib/utils/episode_url.dart",
]
diff = subprocess.check_output(
    ["git", "diff", "--name-only", base["commit"], "--", *protected],
    cwd=root, encoding="utf-8",
).splitlines()
version = re.search(r"^version:\s*(\S+)",
                    (root / "pubspec.yaml").read_text(encoding="utf-8"), re.M).group(1)
api = int(re.search(r"apiLevel\s*=\s*(\d+)",
                   (root / "lib/request/config/api_endpoints.dart").read_text(encoding="utf-8")).group(1))
errors = []
exceptions = base.get("reviewedExtensions", {})
unexpected = []
for path in diff:
    reviewed = exceptions.get(path, {})
    actual = hashlib.sha256((root / path).read_bytes()).hexdigest() if (root / path).is_file() else None
    if not reviewed.get("reason") or reviewed.get("sha256") != actual:
        unexpected.append(path)
if unexpected:
    errors.append("Unreviewed upstream contract changes: " + ", ".join(unexpected))
if version != base["version"]:
    errors.append(f"Version {version} differs from recorded upstream {base['version']}")
if api != base["apiLevel"]:
    errors.append(f"API {api} differs from recorded upstream {base['apiLevel']}")
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print(f"Upstream contract intact: {version}, API {api}, base {base['commit'][:12]}")
if diff:
    print("Explicit downstream extensions (exact hashes checked): " + ", ".join(diff))
