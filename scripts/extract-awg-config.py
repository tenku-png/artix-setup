#!/usr/bin/env python3
"""Extract an AmneziaWG .conf from a config file or Amnezia backup safely."""
from __future__ import annotations

import json
import os
import pathlib
import re
import sys


def valid_config(value: str) -> bool:
    return (
        "[Interface]" in value
        and re.search(r"(?m)^\s*PrivateKey\s*=\s*\S+", value) is not None
        and re.search(r"(?m)^\s*\[Peer\]\s*$", value) is not None
    )


def find_configs(value: object) -> list[str]:
    found: list[str] = []
    if isinstance(value, dict):
        last = value.get("last_config")
        if isinstance(last, str):
            try:
                config = json.loads(last).get("config", "")
            except (json.JSONDecodeError, AttributeError):
                config = ""
            if isinstance(config, str) and valid_config(config):
                found.append(config.strip() + "\n")
        for child in value.values():
            found.extend(find_configs(child))
    elif isinstance(value, list):
        for child in value:
            found.extend(find_configs(child))
    elif isinstance(value, str) and value.lstrip().startswith(("{", "[")):
        try:
            found.extend(find_configs(json.loads(value)))
        except json.JSONDecodeError:
            pass
    return found


def main() -> int:
    if len(sys.argv) != 3:
        print("profile extraction failed: expected input and private output paths", file=sys.stderr)
        return 2
    source, destination = map(pathlib.Path, sys.argv[1:])
    try:
        raw = source.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        print("profile extraction failed: input is unavailable or unreadable", file=sys.stderr)
        return 1

    config = raw if valid_config(raw) else ""
    if not config:
        try:
            candidates = find_configs(json.loads(raw))
        except json.JSONDecodeError:
            candidates = []
        if candidates:
            config = candidates[0]
    if not config:
        print("profile extraction failed: no valid AmneziaWG profile found", file=sys.stderr)
        return 1

    try:
        fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            output.write(config.strip() + "\n")
        os.chmod(destination, 0o600)
    except OSError:
        print("profile extraction failed: could not write protected temporary file", file=sys.stderr)
        return 1
    print("AmneziaWG profile validated; contents hidden")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
