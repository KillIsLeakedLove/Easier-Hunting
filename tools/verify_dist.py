"""Verify the Easier Hunting FMM options bundle."""

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


def verify_modinfo(archive: zipfile.ZipFile, option: build_mod.OptionSpec) -> None:
    text = archive.read(build_mod.option_path(option, "modinfo.ini")).decode("utf-8")
    if f"name={option.name}" not in text:
        raise ValueError(f"{option.folder}: modinfo name mismatch")
    if f"version={build_mod.MOD_VERSION}" not in text:
        raise ValueError(f"{option.folder}: modinfo version mismatch")
    if option.addon_for:
        if f"AddonFor={option.addon_for}" not in text:
            raise ValueError(f"{option.folder}: AddonFor mismatch")
    elif "AddonFor=" in text:
        raise ValueError(f"{option.folder}: unexpected AddonFor")


def verify_scaled(
    archive: zipfile.ZipFile,
    option: build_mod.OptionSpec,
    schema: dict,
    relative: str,
    source: bytes,
    specs: tuple[build_mod.FieldSpec, ...],
    *,
    scaled: bool,
) -> None:
    payload = archive.read(build_mod.option_path(option, relative))
    if not scaled:
        if payload != source:
            raise ValueError(f"{option.folder}: vanilla restore mismatch {relative}")
        return
    source_values = build_mod.field_values(source, specs, schema)
    archive_values = build_mod.field_values(payload, specs, schema)
    for spec in specs:
        if option.kind == "knockdown_on":
            expected = [build_mod.packed_float(build_mod.knockdown_scaled(value)) for value in source_values[spec]]
        else:
            expected = [
                build_mod.transformed_value(value, spec, option.multiplier, option.resistance)
                for value in source_values[spec]
            ]
        if archive_values[spec] != expected:
            raise ValueError(f"{option.folder}: verify failed {relative} {spec.name}")


def verify_archive(schema: dict) -> None:
    expected = build_mod.expected_members()
    knockdown_source = (SOURCE_DIR / build_mod.KNOCKDOWN_PATH).read_bytes()
    with zipfile.ZipFile(ARCHIVE_PATH) as archive:
        members = {entry.filename for entry in archive.infolist()}
        if members != expected:
            raise ValueError(f"unexpected members {sorted(members ^ expected)}")
        if any(entry.is_dir() for entry in archive.infolist()):
            raise ValueError("archive contains directory entries")

        names = [option.name for option in build_mod.OPTIONS]
        if len(names) != len(set(names)):
            raise ValueError(f"duplicate option names: {names}")

        for option in build_mod.OPTIONS:
            verify_modinfo(archive, option)
            option_files = {name for name in members if name.startswith(option.folder + "/")}
            if option_files != build_mod.option_members(option):
                raise ValueError(f"{option.folder}: unexpected files {sorted(option_files)}")
            if option.kind in {"stats_on", "stats_off"}:
                scaled = option.kind == "stats_on"
                for relative_path, specs in build_mod.TARGETS:
                    verify_scaled(
                        archive,
                        option,
                        schema,
                        relative_path.as_posix(),
                        (SOURCE_DIR / relative_path).read_bytes(),
                        specs,
                        scaled=scaled,
                    )
            elif option.kind in {"knockdown_on", "knockdown_off"}:
                verify_scaled(
                    archive,
                    option,
                    schema,
                    build_mod.KNOCKDOWN_PATH.as_posix(),
                    knockdown_source,
                    build_mod.KNOCKDOWN_FIELDS,
                    scaled=option.kind == "knockdown_on",
                )
            elif option.kind == "retries_on":
                payload = archive.read(build_mod.option_path(option, build_mod.RETRY_SCRIPT_ARCHIVE_PATH))
                if payload != build_mod.RETRY_SCRIPT_PATH.read_bytes():
                    raise ValueError(f"{option.folder}: retry script mismatch")
            elif option.kind == "retries_off":
                payload = archive.read(build_mod.option_path(option, build_mod.RETRY_SCRIPT_ARCHIVE_PATH))
                if payload != build_mod.RETRY_OFF_SCRIPT:
                    raise ValueError(f"{option.folder}: retry-off stub mismatch")

    print(f"verified {ARCHIVE_PATH.name}: {len(expected)} entries, {len(build_mod.OPTIONS)} options")


def verify_checksums() -> None:
    expected_sums: dict[str, str] = {}
    for relative_path, _ in build_mod.TARGETS:
        path = SOURCE_DIR / relative_path
        expected_sums[path.relative_to(ROOT).as_posix()] = sha256(path)
    expected_sums[(SOURCE_DIR / build_mod.KNOCKDOWN_PATH).relative_to(ROOT).as_posix()] = sha256(
        SOURCE_DIR / build_mod.KNOCKDOWN_PATH
    )
    expected_sums[build_mod.RETRY_SCRIPT_PATH.relative_to(ROOT).as_posix()] = sha256(build_mod.RETRY_SCRIPT_PATH)
    expected_sums[ARCHIVE_PATH.relative_to(ROOT).as_posix()] = sha256(ARCHIVE_PATH)

    actual_sums = {}
    for line in (ROOT / "SHA256SUMS.txt").read_text(encoding="ascii").splitlines():
        digest, relative_path = line.split("  ", maxsplit=1)
        actual_sums[relative_path] = digest
    if actual_sums != expected_sums:
        raise ValueError("SHA256SUMS.txt does not match current files")


def main() -> None:
    schema = json.loads((SOURCE_DIR / "type_schema.json").read_text(encoding="utf-8"))
    verify_archive(schema)
    verify_checksums()
    print("verified checksums")


if __name__ == "__main__":
    main()
