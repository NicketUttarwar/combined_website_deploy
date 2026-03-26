#!/usr/bin/env python3
"""Quick sanity check: all pages and main assets return 200."""
import os
import urllib.request
import sys

BASE = os.environ.get("BASE", "http://127.0.0.1:8080")
PAGES = [
    "/",
    "/about/",
    "/experience/",
    "/life/",
    "/art/",
    "/contact/",
    "/uttarwarart/",
    "/404.html",
    "/robots.txt",
    "/sitemap.xml",
    "/llms.txt",
]
ASSETS = ["/css/style.css", "/images/logo.png", "/uttarwarart/data/art-index.json"]

def main():
    ok = True
    for path in PAGES + ASSETS:
        url = BASE + path
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "test"})
            with urllib.request.urlopen(req, timeout=5) as r:
                if r.status != 200:
                    print(f"FAIL {r.status} {path}")
                    ok = False
                else:
                    print(f"OK   200 {path}")
        except Exception as e:
            print(f"FAIL {path}: {e}")
            ok = False
    if not ok:
        sys.exit(1)
    print("All checks passed.")

if __name__ == "__main__":
    main()
