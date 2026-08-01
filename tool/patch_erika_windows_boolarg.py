"""Patch the Erika v0.1.4 Windows debug-HUD argument regression."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
from typing import Mapping


BROKEN_CALL = (
    'PlayerFromArgs(args).SetDebugHudEnabled(BoolArg(args, "enabled", false));'
)
FIXED_CALL = (
    "PlayerFromArgs(args).SetDebugHudEnabled(\n"
    '          BoolValue(FindArg(args, "enabled")).value_or(false));'
)
RELATIVE_SOURCE = Path(
    "packages/erika_flutter/windows/erika_flutter_plugin.cpp"
)


def resolve_source(erika_sha: str, environment: Mapping[str, str]) -> Path:
    pub_cache = environment.get("PUB_CACHE", "").strip()
    if pub_cache:
        source = Path(pub_cache) / "git" / f"Erika-{erika_sha}" / RELATIVE_SOURCE
        if source.is_file():
            return source
        raise RuntimeError(f"Erika Windows source not found in PUB_CACHE: {source}")

    roots = [
        Path(environment["LOCALAPPDATA"]) / "Pub" / "Cache",
        Path(environment["USERPROFILE"]) / ".pub-cache",
    ]
    candidates = [root / "git" / f"Erika-{erika_sha}" / RELATIVE_SOURCE for root in roots]
    sources = list(dict.fromkeys(path for path in candidates if path.is_file()))
    if len(sources) != 1:
        raise RuntimeError(
            f"Expected one Erika Windows source for {erika_sha}, found: {sources}"
        )
    return sources[0]


def patch_source(source: Path) -> bool:
    with source.open("r", encoding="utf-8", newline="") as source_file:
        contents = source_file.read()

    broken_count = contents.count(BROKEN_CALL)
    fixed_count = contents.count(FIXED_CALL)
    if (broken_count, fixed_count) == (0, 1):
        return False
    if (broken_count, fixed_count) != (1, 0):
        raise RuntimeError(
            "Erika Windows source is in an unexpected state: "
            f"broken={broken_count}, fixed={fixed_count}, source={source}"
        )

    with source.open("w", encoding="utf-8", newline="") as source_file:
        source_file.write(contents.replace(BROKEN_CALL, FIXED_CALL))
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path)
    parser.add_argument("--erika-sha")
    arguments = parser.parse_args()

    if arguments.source is not None:
        source = arguments.source
    else:
        erika_sha = (arguments.erika_sha or os.environ.get("ERIKA_SHA", "")).strip()
        if not erika_sha:
            parser.error("--erika-sha or ERIKA_SHA is required without --source")
        source = resolve_source(erika_sha, os.environ)

    changed = patch_source(source)
    state = "Patched" if changed else "Already patched"
    print(f"{state} Erika Windows BoolArg regression: {source}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as error:
        raise SystemExit(str(error)) from error
