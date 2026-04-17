#!/usr/bin/env python3
"""Generate a PEP 503 "simple" package index from a JSON-lines manifest.

Each input line is a JSON object with at least ``filename`` and ``url``.
The index is written to ``<out>/simple/{name}/index.html``, with a root
listing at ``<out>/simple/index.html`` and a ``.nojekyll`` marker at
``<out>/.nojekyll`` so GitHub Pages serves the tree verbatim.

Usage: build-pypi-index.py <packages.jsonl> <output-dir>

We roll this ourselves (rather than using dumb-pypi) because dumb-pypi
assumes every wheel for a package lives under a single URL prefix. Our
wheels are release assets scattered across per-tag URLs, so each entry
needs its own URL.
"""
from __future__ import annotations

import html
import json
import re
import sys
from collections import defaultdict
from pathlib import Path


def canonical_name(filename: str) -> str:
    # PEP 503 normalisation: lowercase, runs of -_. collapsed to -.
    # Wheel filename format: {distribution}-{version}(-{build})?-{python}-{abi}-{platform}.whl
    dist = filename.split("-", 1)[0]
    return re.sub(r"[-_.]+", "-", dist).lower()


def write_page(path: Path, title: str, links: list[tuple[str, str]]) -> None:
    body = "\n".join(
        f'    <a href="{html.escape(href, quote=True)}">{html.escape(text)}</a><br/>'
        for href, text in links
    )
    path.write_text(
        f"<!DOCTYPE html>\n"
        f"<html><head><title>{html.escape(title)}</title></head>\n"
        f"<body>\n{body}\n</body></html>\n"
    )


def main(manifest_path: str, out_dir: str) -> int:
    packages: dict[str, list[tuple[str, str]]] = defaultdict(list)
    with open(manifest_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rec = json.loads(line)
            filename = rec["filename"]
            url = rec["url"]
            packages[canonical_name(filename)].append((filename, url))

    out = Path(out_dir)
    simple = out / "simple"
    simple.mkdir(parents=True, exist_ok=True)

    write_page(
        simple / "index.html",
        "Simple index",
        [(f"{name}/", name) for name in sorted(packages)],
    )

    for name, items in packages.items():
        pdir = simple / name
        pdir.mkdir(exist_ok=True)
        write_page(
            pdir / "index.html",
            f"Links for {name}",
            sorted((url, filename) for filename, url in items),
        )

    (out / ".nojekyll").touch()

    total = sum(len(items) for items in packages.values())
    print(f"indexed {total} wheel(s) across {len(packages)} package(s) into {out}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <packages.jsonl> <output-dir>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
