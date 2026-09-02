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
MOD_VERSION = "1.7.100"
WEAPON_DATA_HASH = 0x045CB10D
ZIP_TIMESTAMP = (1980, 1, 1, 0, 0, 0)
RETRY_SCRIPT_ARCHIVE_PATH = "reframework/autorun/easier_hunting_retries.lua"
RETRY_OFF_SCRIPT = "-- Easier Hunting: quest retries disabled / 任务重试已关闭.\nreturn\n".encode("utf-8")

STATS_GROUP_NAME = "1. Attack / Defense / Resistance"
RETRIES_GROUP_NAME = "2. Quest Retries"
KNOCKDOWN_GROUP_NAME = "3. Monster Knockdown"
STATS_2X_NAME = "On (2x)"
STATS_4X_NAME = "On (4x)"
STATS_OFF_NAME = "Off (vanilla)"
RETRIES_ON_NAME = "On (99)"
RETRIES_OFF_NAME = "Off (default)"
KNOCKDOWN_ON_NAME = "On (easy)"
KNOCKDOWN_OFF_NAME = "Off (vanilla stagger)"
KNOCKDOWN_DIVISOR = 10.0
KNOCKDOWN_MIN = 0.01
DIFFICULTY_RATE_HASH = 0xEE8A3347
DIFFICULTY_MULTI_HASH = 0x16C7340F


@dataclass(frozen=True)
class FieldSpec:
    type_hash: int
    name: str
    scale_with_multiplier: bool = True
    add_resistance: bool = False
    positive_only: bool = True


@dataclass(frozen=True)
class OptionSpec:
    folder: str
    name: str
    description: str
    addon_for: str | None
    menu_priority: int
    kind: str
    multiplier: int = 1
    resistance: int = 0


OPTIONS = (
    OptionSpec(
        folder="00 - Easier Hunting",
        name=MOD_NAME,
        description=(
            "Hunter attack/defense 2x or 4x, +2 or +4 resistance per armor piece, 99 quest retries, "
            "easier monster knockdown. Open this menu and enable one option in each group. "
            "Written entirely by AI; published after human verification. | "
            "猎人攻击/防御 2 倍或 4 倍，每件防具耐性 +2 或 +4，倒下上限 99，怪物更易击倒。"
            "每组只开一项。完全由 AI 编写，经人工验证后发布。"
        ),
        addon_for=None,
        menu_priority=50,
        kind="master",
    ),
    OptionSpec(
        folder="10 - Stats",
        name=STATS_GROUP_NAME,
        description="Enable exactly one option. Do not enable more than one. | 只开其中一项，不要多开。",
        addon_for=MOD_NAME,
        menu_priority=20,
        kind="group",
    ),
    OptionSpec(
        folder="11 - Stats 2x",
        name=STATS_2X_NAME,
        description=(
            "Hunter weapon attack x2, armor defense x2, "
            "+2 resistance per piece (~+10 full set). | "
            "猎人武器攻击 2 倍，防具防御 2 倍，每件耐性 +2（满装约 +10）。"
        ),
        addon_for=STATS_GROUP_NAME,
        menu_priority=3,
        kind="stats_on",
        multiplier=2,
        resistance=2,
    ),
    OptionSpec(
        folder="12 - Stats 4x",
        name=STATS_4X_NAME,
        description=(
            "Hunter weapon attack x4, armor defense x4, "
            "+4 resistance per piece (~+20 full set). | "
            "猎人武器攻击 4 倍，防具防御 4 倍，每件耐性 +4（满装约 +20）。"
        ),
        addon_for=STATS_GROUP_NAME,
        menu_priority=2,
        kind="stats_on",
        multiplier=4,
        resistance=4,
    ),
    OptionSpec(
        folder="13 - Stats Off",
        name=STATS_OFF_NAME,
        description=(
            "Restore vanilla hunter attack, defense, and resistance files. | "
            "还原原版猎人攻击、防御和耐性。"
        ),
        addon_for=STATS_GROUP_NAME,
        menu_priority=1,
        kind="stats_off",
    ),
    OptionSpec(
        folder="20 - Retries",
        name=RETRIES_GROUP_NAME,
        description=(
            "Enable On or Off. Do not enable both. Requires REFramework. | "
            "只开 On 或 Off，不要两个一起开。需要 REFramework。"
        ),
        addon_for=MOD_NAME,
        menu_priority=10,
        kind="group",
    ),
    OptionSpec(
        folder="21 - Retries On",
        name=RETRIES_ON_NAME,
        description=(
            "Quest faint/cart cap 99, including the quest board list. "
            "Offline / solo / private sessions only. | "
            "倒下上限 99（含任务列表）。仅离线 / 单人 / 私人局。"
        ),
        addon_for=RETRIES_GROUP_NAME,
        menu_priority=2,
        kind="retries_on",
    ),
    OptionSpec(
        folder="22 - Retries Off",
        name=RETRIES_OFF_NAME,
        description=(
            "Remove the 99-cart script (writes an idle stub over the autorun file). | "
            "去掉 99 次倒下脚本（用空脚本覆盖 autorun）。"
        ),
        addon_for=RETRIES_GROUP_NAME,
        menu_priority=1,
        kind="retries_off",
    ),
    OptionSpec(
        folder="30 - Knockdown",
        name=KNOCKDOWN_GROUP_NAME,
        description=(
            "Enable On or Off. Do not enable both. | "
            "只开 On 或 Off，不要两个一起开。"
        ),
        addon_for=MOD_NAME,
        menu_priority=5,
        kind="group",
    ),
    OptionSpec(
        folder="31 - Knockdown On",
        name=KNOCKDOWN_ON_NAME,
        description=(
            "Part flinch, break, sever, and wound HP about 10x easier. "
            "Monster HP and attack unchanged. Offline / solo / private sessions only. | "
            "部位怯/破坏/切断和伤口耐久约为 1/10。怪物血量和攻击不变。仅离线 / 单人 / 私人局。"
        ),
        addon_for=KNOCKDOWN_GROUP_NAME,
        menu_priority=2,
        kind="knockdown_on",
    ),
    OptionSpec(
        folder="32 - Knockdown Off",
        name=KNOCKDOWN_OFF_NAME,
        description=(
            "Restore vanilla monster part and wound difficulty rates. | "
            "还原原版怪物部位和伤口难度倍率。"
        ),
        addon_for=KNOCKDOWN_GROUP_NAME,
        menu_priority=1,
        kind="knockdown_off",
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
            FieldSpec(0x35D72ED3, "_Resistance", scale_with_multiplier=False, add_resistance=True),
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

KNOCKDOWN_PATH = Path("natives/STM/GameDesign/Enemy/CommonData/Data/EmCommonDifficulty2.user.3")
KNOCKDOWN_FIELDS = tuple(
    FieldSpec(type_hash, name)
    for type_hash in (DIFFICULTY_RATE_HASH, DIFFICULTY_MULTI_HASH)
    for name in ("_PartsVital", "_ScarNormalAndTear", "_ScarRaw")
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
    "F32": 4,
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


def load_instances(data: bytearray, schema: dict):
    data_start, records = read_rsz(data)
    instances, stream_end = walk_instances(data, records, data_start, schema)
    if stream_end != len(data):
        raise ValueError(f"RSZ stream ends at 0x{stream_end:X}, expected EOF 0x{len(data):X}")
    return instances


def read_value(data: bytearray, offset: int, field_type: str) -> int | float:
    if field_type == "F32":
        return struct.unpack_from("<f", data, offset)[0]
    fmt, _minimum, _maximum = INTEGER_LAYOUTS[field_type]
    return struct.unpack_from(fmt, data, offset)[0]


def write_value(data: bytearray, offset: int, field_type: str, value: int | float) -> None:
    if field_type == "F32":
        struct.pack_into("<f", data, offset, value)
        return
    fmt, minimum, maximum = INTEGER_LAYOUTS[field_type]
    if not minimum <= value <= maximum:
        raise ValueError(f"{field_type} overflow: {value}")
    struct.pack_into(fmt, data, offset, value)


def knockdown_scaled(value: float) -> float:
    if value <= 0:
        return value
    return max(value / KNOCKDOWN_DIVISOR, KNOCKDOWN_MIN)


def packed_float(value: float) -> float:
    return struct.unpack("<f", struct.pack("<f", value))[0]


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


def field_values(payload: bytes, specs: tuple[FieldSpec, ...], schema: dict):
    data = bytearray(payload)
    instances = load_instances(data, schema)
    definitions, specs_by_type = resolve_fields(specs, schema)
    values = {spec: [] for spec in specs}
    for type_hash, fields in instances:
        for spec in specs_by_type.get(type_hash, ()):
            field = definitions[spec]
            values[spec].extend(
                read_value(data, offset, field["type"])
                for offset in value_offsets(data, fields[spec.name], field)
            )
    return values


def transformed_value(value: int, spec: FieldSpec, multiplier: int, resistance: int) -> int:
    if spec.scale_with_multiplier and (value > 0 or not spec.positive_only):
        value *= multiplier
    if spec.add_resistance:
        value += resistance
    return value


def transform(
    source: Path,
    specs: tuple[FieldSpec, ...],
    schema: dict,
    multiplier: int = 1,
    resistance: int = 0,
    *,
    floats: bool = False,
) -> bytes:
    data = bytearray(source.read_bytes())
    instances = load_instances(data, schema)
    definitions, specs_by_type = resolve_fields(specs, schema)
    expected = {spec: [] for spec in specs}

    for type_hash, fields in instances:
        for spec in specs_by_type.get(type_hash, ()):
            field = definitions[spec]
            if floats != (field["type"] == "F32"):
                raise ValueError(f"{spec.name} is {field['type']}")
            for field_offset in value_offsets(data, fields[spec.name], field):
                original = read_value(data, field_offset, field["type"])
                replacement = (
                    knockdown_scaled(original)
                    if floats
                    else transformed_value(original, spec, multiplier, resistance)
                )
                write_value(data, field_offset, field["type"], replacement)
                expected[spec].append(read_value(data, field_offset, field["type"]))

    if any(not values for values in expected.values()):
        missing = [spec.name for spec, values in expected.items() if not values]
        raise ValueError(f"missing expected fields in {source.name}: {', '.join(missing)}")

    if field_values(bytes(data), specs, schema) != expected:
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
    return "\n".join(lines).encode("utf-8")


def option_members(option: OptionSpec) -> set[str]:
    members = {option_path(option, "modinfo.ini")}
    if option.kind in {"stats_on", "stats_off"}:
        members |= {option_path(option, relative.as_posix()) for relative, _specs in TARGETS}
    if option.kind in {"knockdown_on", "knockdown_off"}:
        members.add(option_path(option, KNOCKDOWN_PATH.as_posix()))
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
    scaled: dict[tuple[int, int], dict[str, bytes]],
    knockdown: bytes,
) -> None:
    zip_entry(archive, option_path(option, "modinfo.ini"), modinfo_bytes(option))
    if option.kind == "stats_on":
        transformed = scaled[(option.multiplier, option.resistance)]
        for relative_path, _specs in TARGETS:
            zip_entry(archive, option_path(option, relative_path.as_posix()), transformed[relative_path.as_posix()])
    elif option.kind == "stats_off":
        for relative_path, _specs in TARGETS:
            zip_entry(archive, option_path(option, relative_path.as_posix()), (SOURCE_DIR / relative_path).read_bytes())
    elif option.kind == "knockdown_on":
        zip_entry(archive, option_path(option, KNOCKDOWN_PATH.as_posix()), knockdown)
    elif option.kind == "knockdown_off":
        zip_entry(archive, option_path(option, KNOCKDOWN_PATH.as_posix()), (SOURCE_DIR / KNOCKDOWN_PATH).read_bytes())
    elif option.kind == "retries_on":
        zip_entry(archive, option_path(option, RETRY_SCRIPT_ARCHIVE_PATH), RETRY_SCRIPT_PATH.read_bytes())
    elif option.kind == "retries_off":
        zip_entry(archive, option_path(option, RETRY_SCRIPT_ARCHIVE_PATH), RETRY_OFF_SCRIPT)


def write_checksums(archive: Path) -> None:
    paths = [SOURCE_DIR / relative_path for relative_path, _ in TARGETS]
    paths.append(SOURCE_DIR / KNOCKDOWN_PATH)
    paths.append(RETRY_SCRIPT_PATH)
    paths.append(archive)
    lines = [f"{sha256(path)}  {path.relative_to(ROOT).as_posix()}" for path in paths]
    (ROOT / "SHA256SUMS.txt").write_text("\n".join(lines) + "\n", encoding="ascii")


def build() -> Path:
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    scaled: dict[tuple[int, int], dict[str, bytes]] = {}
    for option in OPTIONS:
        if option.kind != "stats_on":
            continue
        key = (option.multiplier, option.resistance)
        if key in scaled:
            continue
        scaled[key] = {
            relative_path.as_posix(): transform(
                SOURCE_DIR / relative_path, specs, schema, option.multiplier, option.resistance
            )
            for relative_path, specs in TARGETS
        }
    knockdown = transform(SOURCE_DIR / KNOCKDOWN_PATH, KNOCKDOWN_FIELDS, schema, floats=True)
    output = DIST_DIR / ARCHIVE_NAME
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for option in OPTIONS:
            write_option(archive, option, scaled, knockdown)
    write_checksums(output)
    return output


def main() -> None:
    print(build())


if __name__ == "__main__":
    main()
