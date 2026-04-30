#!/usr/bin/env python3
"""
parse_release.py — GitHub Release JSON Parser
your-local-agent | github.com/noelps-git/your-local-agent

Parses the GitHub releases API JSON safely, stripping control
characters that break Python 3.14's strict JSON parser.

Usage:
  python3 parse_release.py <json_file> <asset_pattern>

Prints:
  Line 1: download URL
  Line 2: release tag

Exit codes:
  0 = success
  1 = no matching asset found or parse error
"""

import json
import re
import sys


def main():
    if len(sys.argv) < 3:
        print("Usage: parse_release.py <json_file> <asset_pattern>", file=sys.stderr)
        sys.exit(1)

    json_file = sys.argv[1]
    asset_pattern = sys.argv[2]

    try:
        with open(json_file, "r", errors="replace") as f:
            raw = f.read()
    except OSError as e:
        print(f"Could not read file: {e}", file=sys.stderr)
        sys.exit(1)

    # Strip control characters that break strict JSON parsers (Python 3.14+)
    # Keeps: \t (0x09), \n (0x0a), \r (0x0d) — valid JSON whitespace
    raw = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", raw)

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"JSON parse error: {e}", file=sys.stderr)
        sys.exit(1)

    tag = data.get("tag_name", "")
    assets = data.get("assets", [])

    for asset in assets:
        name = asset.get("name", "")
        url = asset.get("browser_download_url", "")
        # Match .tar.gz for macOS/Linux, .zip for Windows
        # Skip kleidiai variant — use standard build
        if (
            asset_pattern in name
            and (name.endswith(".tar.gz") or name.endswith(".zip"))
            and "llama" in name.lower()
            and "kleidiai" not in name.lower()
            and url
        ):
            print(url)
            print(tag)
            sys.exit(0)

    print(f"No asset matching '{asset_pattern}' found in release '{tag}'", file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
