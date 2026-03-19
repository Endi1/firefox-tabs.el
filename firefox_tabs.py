#!/usr/bin/env python3
"""Extract URLs of all open Firefox tabs from the session recovery file."""

import glob
import json
import sys


def find_recovery_file():
    patterns = [
        "~/Library/Application Support/Firefox/Profiles/*/sessionstore-backups/recovery.jsonlz4",  # macOS
    ]
    for pattern in patterns:
        files = glob.glob(os.path.expanduser(pattern))
        if files:
            # Pick the most recently modified one if multiple profiles exist
            return max(files, key=os.path.getmtime)
    return None


def read_jsonlz4(path):
    """Read Mozilla's jsonlz4 format (custom 8-byte header + lz4 block)."""
    import lz4.block

    with open(path, "rb") as f:
        magic = f.read(8)
        if magic[:8] != b"mozLz40\0":
            raise ValueError(f"Not a valid mozLz4 file (header: {magic!r})")
        return json.loads(lz4.block.decompress(f.read()))


def extract_tabs(session_data):
    """Yield (window_index, tab_index, title, url) for each open tab."""
    for wi, window in enumerate(session_data.get("windows", []), 1):
        for ti, tab in enumerate(window.get("tabs", []), 1):
            entries = tab.get("entries", [])
            if entries:
                entry = entries[-1]  # current page in tab history
                yield wi, ti, entry.get("title", ""), entry.get("url", "")


if __name__ == "__main__":
    import os

    recovery = find_recovery_file()
    if not recovery:
        print("Error: No Firefox recovery file found. Is Firefox running?", file=sys.stderr)
        sys.exit(1)

    try:
        data = read_jsonlz4(recovery)
    except ImportError:
        print("Error: 'lz4' package is required. Install it with:\n  pip3 install lz4", file=sys.stderr)
        sys.exit(1)

    tabs = list(extract_tabs(data))
    if not tabs:
        print("No open tabs found.")
        sys.exit(0)

    for wi, ti, title, url in tabs:
        print(f"[Window {wi}, Tab {ti}] {title}")
        print(f"  {url}")
