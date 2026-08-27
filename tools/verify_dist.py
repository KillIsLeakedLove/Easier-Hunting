"""Verify the Easier Hunting archive against clean archived source data."""

from __future__ import annotations

import json
import zipfile
from pathlib import Path

import build_mod


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "source"
ARCHIVE_PATH = ROOT / "dist" / build_mod.ARCHIVE_NAME


def main() -> None:
    schema = json.loads((SOURCE_DIR / "type_schema.json").read_text(encoding="utf-8"))
    expected_members = {"modinfo.ini"} | {
        relative_path.as_posix() for relative_path, _specs in build_mod.TARGETS
    }
    with zipfile.ZipFile(ARCHIVE_PATH) as archive:
        members = {entry.filename for entry in archive.infolist()}
        if members != expected_members:
            raise ValueError(f"unexpected archive members: {sorted(members)}")
        if any(entry.is_dir() for entry in archive.infolist()):
            raise ValueError("archive contains directory entries")
        manifest = archive.read("modinfo.ini").decode("ascii")
        if f"name={build_mod.MOD_NAME}" not in manifest:
            raise ValueError("archive manifest has the wrong mod name")
        for relative_path, specs in build_mod.TARGETS:
            expected_payload, _stats = build_mod.transform(
                SOURCE_DIR / relative_path,
                specs,
                build_mod.MULTIPLIER,
                schema,
            )
            if archive.read(relative_path.as_posix()) != expected_payload:
                raise ValueError(f"payload mismatch: {relative_path}")
    print(f"verified {ARCHIVE_PATH.name}: {len(expected_members) - 1} game data files")


if __name__ == "__main__":
    main()
