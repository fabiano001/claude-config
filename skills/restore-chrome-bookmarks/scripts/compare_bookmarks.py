#!/usr/bin/env python3
"""Compare one Chrome profile's live `Bookmarks` file against its `Bookmarks.bak`.

Usage: compare_bookmarks.py <profile_dir>

Prints one JSON object to stdout (pretty-printed) and exits 0 as long as it could
at least attempt the comparison (missing files are reported in the JSON, not via
a non-zero exit). Exit 1 only on bad usage.
"""
import json
import os
import sys


def collect_urls(node, out):
    if node.get("type") == "url":
        out[node.get("url")] = node.get("date_added")
    for child in node.get("children", []):
        collect_urls(child, out)


def load_urls(path):
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    urls = {}
    for root in data.get("roots", {}).values():
        if isinstance(root, dict):
            collect_urls(root, urls)
    return urls


def main():
    if len(sys.argv) != 2:
        print(json.dumps({"error": "usage: compare_bookmarks.py <profile_dir>"}))
        sys.exit(1)

    profile_dir = sys.argv[1]
    live_path = os.path.join(profile_dir, "Bookmarks")
    bak_path = os.path.join(profile_dir, "Bookmarks.bak")

    result = {
        "profile_dir": profile_dir,
        "live_path": live_path,
        "live_exists": os.path.isfile(live_path),
        "bak_path": bak_path,
        "bak_exists": os.path.isfile(bak_path),
        "live_count": None,
        "bak_count": None,
        "live_only_urls": [],
        "error": None,
    }

    try:
        live_urls = load_urls(live_path) if result["live_exists"] else {}
        bak_urls = load_urls(bak_path) if result["bak_exists"] else {}
        if result["live_exists"]:
            result["live_count"] = len(live_urls)
        if result["bak_exists"]:
            result["bak_count"] = len(bak_urls)
        result["live_only_urls"] = sorted(set(live_urls) - set(bak_urls))
    except Exception as e:
        result["error"] = f"{type(e).__name__}: {e}"

    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
