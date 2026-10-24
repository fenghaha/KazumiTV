#!/usr/bin/env python3
"""Read whitelisted player counters or apply the profile-only 60/36000s trial."""
import argparse
import json
from pathlib import Path
import urllib.parse
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--uri-file", type=Path, required=True)
    parser.add_argument("--seconds", choices=("60", "36000"))
    args = parser.parse_args()
    uri = args.uri_file.read_text().strip()
    parsed = urllib.parse.urlparse(uri)
    if parsed.scheme != "http" or parsed.hostname not in ("localhost", "127.0.0.1"):
        parser.error("only the adb-forwarded loopback VM service is allowed")
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def rpc(method, **parameters):
        try:
            with opener.open(uri.rstrip("/") + "/" + method + "?" +
                             urllib.parse.urlencode(parameters), timeout=10) as response:
                message = json.load(response)
        except Exception as error:
            raise RuntimeError(f"VM request failed: {method} ({type(error).__name__})") from None
        if "error" in message:
            raise RuntimeError(f"VM method failed: {method}, code={message['error'].get('code')}")
        return message.get("result", message)

    vm = rpc("getVM")
    isolate = next(item["id"] for item in vm["isolates"] if item["name"] == "main")
    parameters = {"isolateId": isolate}
    if args.seconds is not None:
        parameters["seconds"] = args.seconds
    print(json.dumps(rpc("ext.kazumi.tv.prefetchTrial", **parameters)))


if __name__ == "__main__":
    main()
