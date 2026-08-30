"""Verify the Easier Hunting FMM archives."""

from __future__ import annotations

import hashlib
import json
import zipfile
from pathlib import Path

import build_mod


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "source"
DIST_DIR = ROOT / "dist"


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


def verify_pack(pack: build_mod.PackSpec, schema: dict) -> None:
    archive_path = DIST_DIR / pack.archive_name
    expected = build_mod.expected_members(pack)
    with zipfile.ZipFile(archive_path) as archive:
        members = {entry.filename for entry in archive.infolist()}
        if members != expected:
            raise ValueError(f"{pack.archive_name}: unexpected members {sorted(members)}")
        if any(entry.is_dir() for entry in archive.infolist()):
            raise ValueError(f"{pack.archive_name}: contains directory entries")

        modinfo = archive.read("modinfo.ini").decode("ascii")
        if f"name={pack.mod_name}" not in modinfo:
            raise ValueError(f"{pack.archive_name}: modinfo name mismatch")
        if f"version={build_mod.MOD_VERSION}" not in modinfo:
            raise ValueError(f"{pack.archive_name}: modinfo version mismatch")

        if pack.include_retries:
            if archive.read(build_mod.RETRY_SCRIPT_ARCHIVE_PATH) != build_mod.RETRY_SCRIPT_PATH.read_bytes():
                raise ValueError(f"{pack.archive_name}: retry script mismatch")
        elif build_mod.RETRY_SCRIPT_ARCHIVE_PATH in members:
            raise ValueError(f"{pack.archive_name}: unexpected retry script")

        if pack.include_stats:
            for relative_path, specs in build_mod.TARGETS:
                source_values = field_values((SOURCE_DIR / relative_path).read_bytes(), specs, schema)
                archive_values = field_values(archive.read(relative_path.as_posix()), specs, schema)
                for spec in specs:
                    expected_vals = [expected_value(value, spec) for value in source_values[spec]]
                    if archive_values[spec] != expected_vals:
                        raise ValueError(f"{pack.archive_name}: stat verify failed {relative_path} {spec.name}")
        else:
            natives = [name for name in members if name.startswith("natives/")]
            if natives:
                raise ValueError(f"{pack.archive_name}: unexpected natives {natives}")

    print(f"verified {pack.archive_name}: {len(expected)} entries")


def main() -> None:
    schema = json.loads((SOURCE_DIR / "type_schema.json").read_text(encoding="utf-8"))
    for pack in build_mod.PACKS:
        verify_pack(pack, schema)

    expected_sums: dict[str, str] = {}
    for relative_path, _ in build_mod.TARGETS:
        path = SOURCE_DIR / relative_path
        expected_sums[path.relative_to(ROOT).as_posix()] = sha256(path)
    expected_sums[build_mod.RETRY_SCRIPT_PATH.relative_to(ROOT).as_posix()] = sha256(build_mod.RETRY_SCRIPT_PATH)
    for pack in build_mod.PACKS:
        path = DIST_DIR / pack.archive_name
        expected_sums[path.relative_to(ROOT).as_posix()] = sha256(path)

    actual_sums = {}
    for line in (ROOT / "SHA256SUMS.txt").read_text(encoding="ascii").splitlines():
        digest, relative_path = line.split("  ", maxsplit=1)
        actual_sums[relative_path] = digest
    if actual_sums != expected_sums:
        raise ValueError("SHA256SUMS.txt does not match current files")

    print(f"verified {len(build_mod.PACKS)} packs + checksums")


if __name__ == "__main__":
    main()
