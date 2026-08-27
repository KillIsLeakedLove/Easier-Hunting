"""Verify the Easier Hunting archive against clean archived source data."""

from __future__ import annotations

import json
import zipfile
from pathlib import Path

import build_mod


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "source"
ARCHIVE_PATH = ROOT / "dist" / build_mod.ARCHIVE_NAME


def field_values(payload: bytes, specs: tuple[build_mod.FieldSpec, ...], schema: dict) -> dict[build_mod.FieldSpec, list[int]]:
    data = bytearray(payload)
    data_start, records = build_mod.read_rsz(data)
    instances, stream_end = build_mod.walk_instances(data, records, data_start, schema)
    if stream_end != len(data):
        raise ValueError(f"RSZ stream ends at 0x{stream_end:X}, expected EOF 0x{len(data):X}")
    definitions, specs_by_type = build_mod.resolve_fields(specs, schema)
    values = {spec: [] for spec in specs}
    for type_hash, fields in instances:
        for spec in specs_by_type.get(type_hash, ()):
            field = definitions[spec]
            values[spec].extend(
                build_mod.integer_value(data, offset, field["type"])
                for offset in build_mod.value_offsets(data, fields[spec.name], field)
            )
    return values


def expected_value(value: int, spec: build_mod.FieldSpec) -> int:
    if spec.scale_with_multiplier and (value > 0 or not spec.positive_only):
        value *= build_mod.MULTIPLIER
    return value + spec.addend


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
            source_values = field_values((SOURCE_DIR / relative_path).read_bytes(), specs, schema)
            archive_values = field_values(archive.read(relative_path.as_posix()), specs, schema)
            for spec in specs:
                expected_values = [expected_value(value, spec) for value in source_values[spec]]
                if archive_values[spec] != expected_values:
                    raise ValueError(f"stat verification failed: {relative_path} {spec.name}")
    print(f"verified {ARCHIVE_PATH.name}: {len(expected_members) - 1} game data files")


if __name__ == "__main__":
    main()
