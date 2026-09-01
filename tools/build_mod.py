"""Build the Easier Hunting FMM archive from clean RSZ data."""

from __future__ import annotations

import hashlib
import json
import struct
import zipfile
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "source"
SCHEMA_PATH = SOURCE_DIR / "type_schema.json"
RETRY_SCRIPT_PATH = SOURCE_DIR / "reframework" / "easier_hunting_retries.lua"
DIST_DIR = ROOT / "dist"
ARCHIVE_NAME = "Easier Hunting - TU4.1.zip"
MOD_NAME = "Easier Hunting"
MOD_VERSION = "1.7.96"
MULTIPLIER = 2
RESISTANCE_PER_PIECE = 2
WEAPON_DATA_HASH = 0x045CB10D
ZIP_TIMESTAMP = (1980, 1, 1, 0, 0, 0)
RETRY_SCRIPT_ARCHIVE_PATH = "reframework/autorun/easier_hunting_retries.lua"
RETRY_OFF_SCRIPT = b"-- Easier Hunting: quest retries disabled.\nreturn\n"

STATS_GROUP_NAME = "1. Attack / Defense / Resistance"
RETRIES_GROUP_NAME = "2. Quest Retries"
STATS_ON_NAME = "On (2x)"
STATS_OFF_NAME = "Off (vanilla)"
RETRIES_ON_NAME = "On (99)"
RETRIES_OFF_NAME = "Off (default)"


@dataclass(frozen=True)
class FieldSpec:
    type_hash: int
    name: str
    scale_with_multiplier: bool = True
    addend: int = 0
    positive_only: bool = True


@dataclass(frozen=True)
class OptionSpec:
    folder: str
    name: str
    description: str
    addon_for: str | None
    menu_priority: int
    kind: str


OPTIONS = (
    OptionSpec(
        folder="00 - Easier Hunting",
        name=MOD_NAME,
        description=(
            f"{MULTIPLIER}x hunter attack/defense, "
            f"+{RESISTANCE_PER_PIECE} resistance per armor piece, 99 quest retries. "
            "Open this menu and enable one option in each group."
        ),
        addon_for=None,
        menu_priority=50,
        kind="master",
    ),
    OptionSpec(
        folder="10 - Stats",
        name=STATS_GROUP_NAME,
        description="Enable On or Off. Do not enable both.",
        addon_for=MOD_NAME,
        menu_priority=20,
        kind="group",
    ),
    OptionSpec(
        folder="11 - Stats On",
        name=STATS_ON_NAME,
        description=(
            f"Hunter weapon attack x{MULTIPLIER}, armor defense x{MULTIPLIER}, "
            f"+{RESISTANCE_PER_PIECE} resistance per piece (~+10 full set)."
        ),
        addon_for=STATS_GROUP_NAME,
        menu_priority=2,
        kind="stats_on",
    ),
    OptionSpec(
        folder="12 - Stats Off",
        name=STATS_OFF_NAME,
        description="Restore vanilla hunter attack, defense, and resistance files.",
        addon_for=STATS_GROUP_NAME,
        menu_priority=1,
        kind="stats_off",
    ),
    OptionSpec(
        folder="20 - Retries",
        name=RETRIES_GROUP_NAME,
        description="Enable On or Off. Do not enable both. Requires REFramework.",
        addon_for=MOD_NAME,
        menu_priority=10,
        kind="group",
    ),
    OptionSpec(
        folder="21 - Retries On",
        name=RETRIES_ON_NAME,
        description="Quest faint/cart cap 99, including the quest board list. Offline / solo / private sessions only.",
        addon_for=RETRIES_GROUP_NAME,
        menu_priority=2,
        kind="retries_on",
    ),
    OptionSpec(
        folder="22 - Retries Off",
        name=RETRIES_OFF_NAME,
        description="Remove the 99-cart script (writes an idle stub over the autorun file).",
        addon_for=RETRIES_GROUP_NAME,
        menu_priority=1,
        kind="retries_off",
    ),
)


WEAPON_FILES = (
    "Bow",
    "ChargeAxe",
    "GunLance",
    "Hammer",
    "HeavyBowgun",
    "Lance",
    "LightBowgun",
    "LongSword",
    "Rod",
    "ShortSword",
    "SlashAxe",
    "Tachi",
    "TwinSword",
    "Whistle",
)

WEAPON_FIELDS = (
    FieldSpec(WEAPON_DATA_HASH, "_Attack"),
    FieldSpec(WEAPON_DATA_HASH, "_AttributeValue"),
    FieldSpec(WEAPON_DATA_HASH, "_SubAttributeValue"),
)

TARGETS = (
    (
        Path("natives/STM/GameDesign/Common/Equip/ArmorData.user.3"),
        (
            FieldSpec(0x35D72ED3, "_Defense"),
            FieldSpec(0x35D72ED3, "_Resistance", scale_with_multiplier=False, addend=RESISTANCE_PER_PIECE),
        ),
    ),
    (
        Path("natives/STM/GameDesign/Common/Equip/ArmorUpgradeData.user.3"),
        (FieldSpec(0x246C95D9, "_DefUpValue"),),
    ),
) + tuple(
    (Path(f"natives/STM/GameDesign/Common/Weapon/{weapon}.user.3"), WEAPON_FIELDS)
    for weapon in WEAPON_FILES
)

VALUE_WIDTHS = {
    "S8": 1,
    "U8": 1,
    "Bool": 1,
    "bool": 1,
    "S16": 2,
    "U16": 2,
    "S32": 4,
    "U32": 4,
    "Object": 4,
    "Resource": 4,
    "UserData": 4,
    "Data": 4,
    "S64": 8,
    "U64": 8,
    "DateTime": 8,
    "Guid": 16,
}

INTEGER_LAYOUTS = {
    "S8": ("<b", -0x80, 0x7F),
    "U8": ("<B", 0, 0xFF),
    "S16": ("<h", -0x8000, 0x7FFF),
    "U16": ("<H", 0, 0xFFFF),
    "S32": ("<i", -0x80000000, 0x7FFFFFFF),
    "U32": ("<I", 0, 0xFFFFFFFF),
}


def align(offset: int, alignment: int) -> int:
    return offset if alignment <= 1 else (offset + alignment - 1) & ~(alignment - 1)


def value_end(data: bytearray, offset: int, field: dict) -> int:
    field_type = field["type"]
    if field_type in ("String", "C8", "C16"):
        offset = align(offset, 4)
        count = struct.unpack_from("<I", data, offset)[0]
        return offset + 4 + count * (1 if field_type == "C8" else 2)
    return offset + VALUE_WIDTHS.get(field_type, field["size"])


def parse_instance(data: bytearray, offset: int, definition: dict) -> tuple[int, dict[str, int | tuple[int, int]]]:
    fields: dict[str, int | tuple[int, int]] = {}
    for field in definition.get("fields") or []:
        if field["array"]:
            array_offset = align(offset, 4)
            count = struct.unpack_from("<I", data, array_offset)[0]
            if count > 200_000:
                raise ValueError(f"invalid array count {count} at 0x{array_offset:X}")
            fields[field["name"]] = (array_offset, count)
            offset = array_offset + 4
            for _ in range(count):
                offset = value_end(data, align(offset, field["align"]), field)
        else:
            offset = align(offset, field["align"])
            fields[field["name"]] = offset
            offset = value_end(data, offset, field)
    return offset, fields


def read_rsz(data: bytearray) -> tuple[int, list[tuple[int, int]]]:
    if data[:4] != b"USR\x00":
        raise ValueError("expected a USR container")
    rsz_offset = struct.unpack_from("<Q", data, 0x20)[0]
    if rsz_offset + 0x30 > len(data) or data[rsz_offset : rsz_offset + 4] != b"RSZ\x00":
        raise ValueError("expected an RSZ payload")
    instance_count = struct.unpack_from("<IIiiii", data, rsz_offset)[3]
    instance_offset, data_offset, _ = struct.unpack_from("<QQQ", data, rsz_offset + 0x18)
    table_offset = rsz_offset + instance_offset
    data_start = rsz_offset + data_offset
    if table_offset + instance_count * 8 > len(data) or data_start > len(data):
        raise ValueError("invalid RSZ table or data offset")
    records = [struct.unpack_from("<II", data, table_offset + index * 8) for index in range(instance_count)]
    return data_start, records


def walk_instances(data: bytearray, records: list[tuple[int, int]], data_start: int, schema: dict):
    instances = []
    offset = data_start
    for index, (type_hash, _crc) in enumerate(records):
        definition = schema.get(f"{type_hash:x}")
        if definition is None:
            raise ValueError(f"unknown class 0x{type_hash:X} at instance {index}")
        start = offset
        try:
            offset, fields = parse_instance(data, offset, definition)
        except (IndexError, struct.error, ValueError) as error:
            raise ValueError(f"failed to parse instance {index} at 0x{start:X}") from error
        if offset > len(data):
            raise ValueError(f"instance {index} extends past EOF")
        instances.append((type_hash, fields))
    return instances, offset


def integer_value(data: bytearray, offset: int, field_type: str) -> int:
    fmt, _minimum, _maximum = INTEGER_LAYOUTS[field_type]
    return struct.unpack_from(fmt, data, offset)[0]


def write_integer(data: bytearray, offset: int, field_type: str, value: int) -> None:
    fmt, minimum, maximum = INTEGER_LAYOUTS[field_type]
    if not minimum <= value <= maximum:
        raise ValueError(f"{field_type} overflow: {value}")
    struct.pack_into(fmt, data, offset, value)


def resolve_fields(specs: tuple[FieldSpec, ...], schema: dict):
    definitions: dict[FieldSpec, dict] = {}
    grouped: dict[int, list[FieldSpec]] = defaultdict(list)
    for spec in specs:
        definition = schema[f"{spec.type_hash:x}"]
        field = next((item for item in definition["fields"] if item["name"] == spec.name), None)
        if field is None:
            raise ValueError(f"field {spec.name} missing from type 0x{spec.type_hash:X}")
        definitions[spec] = field
        grouped[spec.type_hash].append(spec)
    return definitions, {type_hash: tuple(items) for type_hash, items in grouped.items()}


def value_offsets(data: bytearray, location: int | tuple[int, int], field: dict) -> tuple[int, ...]:
    if isinstance(location, int):
        return (location,)
    array_offset, count = location
    offset = array_offset + 4
    offsets = []
    for _ in range(count):
        offset = align(offset, field["align"])
        offsets.append(offset)
        offset = value_end(data, offset, field)
    return tuple(offsets)


def transformed_value(value: int, spec: FieldSpec) -> int:
    if spec.scale_with_multiplier and (value > 0 or not spec.positive_only):
        value *= MULTIPLIER
    return value + spec.addend


def transform(source: Path, specs: tuple[FieldSpec, ...], schema: dict) -> bytes:
    data = bytearray(source.read_bytes())
    data_start, records = read_rsz(data)
    instances, stream_end = walk_instances(data, records, data_start, schema)
    if stream_end != len(data):
        raise ValueError(f"RSZ stream ends at 0x{stream_end:X}, expected EOF 0x{len(data):X}")

    definitions, specs_by_type = resolve_fields(specs, schema)
    expected = {spec: [] for spec in specs}

    for type_hash, fields in instances:
        for spec in specs_by_type.get(type_hash, ()):
            field = definitions[spec]
            for field_offset in value_offsets(data, fields[spec.name], field):
                original = integer_value(data, field_offset, field["type"])
                replacement = transformed_value(original, spec)
                write_integer(data, field_offset, field["type"], replacement)
                expected[spec].append(replacement)

    if any(not values for values in expected.values()):
        missing = [spec.name for spec, values in expected.items() if not values]
        raise ValueError(f"missing expected fields in {source.name}: {', '.join(missing)}")

    verify_start, verify_records = read_rsz(data)
    verify_instances, verify_end = walk_instances(data, verify_records, verify_start, schema)
    if verify_end != len(data):
        raise ValueError(f"post-edit RSZ stream does not reach EOF for {source.name}")
    actual = {spec: [] for spec in specs}
    for type_hash, fields in verify_instances:
        for spec in specs_by_type.get(type_hash, ()):
            field = definitions[spec]
            actual[spec].extend(
                integer_value(data, field_offset, field["type"])
                for field_offset in value_offsets(data, fields[spec.name], field)
            )
    if actual != expected:
        raise ValueError(f"post-edit value verification failed for {source.name}")

    return bytes(data)


def zip_entry(archive: zipfile.ZipFile, name: str, payload: bytes) -> None:
    info = zipfile.ZipInfo(name, date_time=ZIP_TIMESTAMP)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o100644 << 16
    archive.writestr(info, payload, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def option_path(option: OptionSpec, relative: str) -> str:
    return f"{option.folder}/{relative}"


def modinfo_bytes(option: OptionSpec) -> bytes:
    lines = [
        f"name={option.name}",
        f"version={MOD_VERSION}",
        f"description={option.description}",
        "author=OpenCode",
        "category=Gameplay",
    ]
    if option.addon_for:
        lines.append(f"AddonFor={option.addon_for}")
    lines.append(f"MenuPriority={option.menu_priority}")
    lines.append("")
    return "\n".join(lines).encode("ascii")


def option_members(option: OptionSpec) -> set[str]:
    members = {option_path(option, "modinfo.ini")}
    if option.kind in {"stats_on", "stats_off"}:
        members |= {option_path(option, relative.as_posix()) for relative, _specs in TARGETS}
    if option.kind in {"retries_on", "retries_off"}:
        members.add(option_path(option, RETRY_SCRIPT_ARCHIVE_PATH))
    return members


def expected_members() -> set[str]:
    members: set[str] = set()
    for option in OPTIONS:
        members |= option_members(option)
    return members


def write_option(
    archive: zipfile.ZipFile,
    option: OptionSpec,
    transformed: dict[str, bytes],
) -> None:
    zip_entry(archive, option_path(option, "modinfo.ini"), modinfo_bytes(option))
    if option.kind == "stats_on":
        for relative_path, _specs in TARGETS:
            zip_entry(archive, option_path(option, relative_path.as_posix()), transformed[relative_path.as_posix()])
    elif option.kind == "stats_off":
        for relative_path, _specs in TARGETS:
            zip_entry(archive, option_path(option, relative_path.as_posix()), (SOURCE_DIR / relative_path).read_bytes())
    elif option.kind == "retries_on":
        zip_entry(archive, option_path(option, RETRY_SCRIPT_ARCHIVE_PATH), RETRY_SCRIPT_PATH.read_bytes())
    elif option.kind == "retries_off":
        zip_entry(archive, option_path(option, RETRY_SCRIPT_ARCHIVE_PATH), RETRY_OFF_SCRIPT)


def write_checksums(archive: Path) -> None:
    paths = [SOURCE_DIR / relative_path for relative_path, _ in TARGETS]
    paths.append(RETRY_SCRIPT_PATH)
    paths.append(archive)
    lines = [f"{sha256(path)}  {path.relative_to(ROOT).as_posix()}" for path in paths]
    (ROOT / "SHA256SUMS.txt").write_text("\n".join(lines) + "\n", encoding="ascii")


def build() -> Path:
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    transformed = {
        relative_path.as_posix(): transform(SOURCE_DIR / relative_path, specs, schema)
        for relative_path, specs in TARGETS
    }
    output = DIST_DIR / ARCHIVE_NAME
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for option in OPTIONS:
            write_option(archive, option, transformed)
    write_checksums(output)
    return output


def main() -> None:
    print(build())


if __name__ == "__main__":
    main()
