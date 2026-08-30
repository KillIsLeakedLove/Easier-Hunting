"""Verify the Easier Hunting archive."""

from __future__ import annotations

import hashlib
import json
import zipfile
from pathlib import Path

import build_mod


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "source"
ARCHIVE_PATH = ROOT / "dist" / build_mod.ARCHIVE_NAME


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def field_values(payload: bytes, specs: tuple[build_mod.FieldSpec, ...], schema: dict):
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
    expected_members = {"modinfo.ini", build_mod.RETRY_SCRIPT_ARCHIVE_PATH} | {
        relative_path.as_posix() for relative_path, _specs in build_mod.TARGETS
    }
    with zipfile.ZipFile(ARCHIVE_PATH) as archive:
        members = {entry.filename for entry in archive.infolist()}
        if members != expected_members:
            raise ValueError(f"unexpected archive members: {sorted(members)}")
        if any(entry.is_dir() for entry in archive.infolist()):
            raise ValueError("archive contains directory entries")
        if archive.read(build_mod.RETRY_SCRIPT_ARCHIVE_PATH) != build_mod.RETRY_SCRIPT_PATH.read_bytes():
            raise ValueError("retry script mismatch")
        for relative_path, specs in build_mod.TARGETS:
            source_values = field_values((SOURCE_DIR / relative_path).read_bytes(), specs, schema)
            archive_values = field_values(archive.read(relative_path.as_posix()), specs, schema)
            for spec in specs:
                expected = [expected_value(value, spec) for value in source_values[spec]]
                if archive_values[spec] != expected:
                    raise ValueError(f"stat verification failed: {relative_path} {spec.name}")

    expected_sums = {}
    for relative_path, _ in build_mod.TARGETS:
        path = SOURCE_DIR / relative_path
        expected_sums[path.relative_to(ROOT).as_posix()] = sha256(path)
    expected_sums[build_mod.RETRY_SCRIPT_PATH.relative_to(ROOT).as_posix()] = sha256(build_mod.RETRY_SCRIPT_PATH)
    expected_sums[ARCHIVE_PATH.relative_to(ROOT).as_posix()] = sha256(ARCHIVE_PATH)
    actual_sums = {}
    for line in (ROOT / "SHA256SUMS.txt").read_text(encoding="ascii").splitlines():
        digest, relative_path = line.split("  ", maxsplit=1)
        actual_sums[relative_path] = digest
    if actual_sums != expected_sums:
        raise ValueError("SHA256SUMS.txt does not match current files")

    print(f"verified {ARCHIVE_PATH.name}: {len(expected_members)} entries")


if __name__ == "__main__":
    main()
