"""Extract the minimal RSZ type schema needed by the archived source files."""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path


def type_hashes(path: Path) -> set[int]:
    data = path.read_bytes()
    if data[:4] != b"USR\x00":
        raise ValueError(f"{path} is not a USR file")
    rsz_offset = struct.unpack_from("<Q", data, 0x20)[0]
    if data[rsz_offset : rsz_offset + 4] != b"RSZ\x00":
        raise ValueError(f"{path} does not contain RSZ data")
    instance_count = struct.unpack_from("<IIiiii", data, rsz_offset)[3]
    instance_offset = struct.unpack_from("<Q", data, rsz_offset + 0x18)[0]
    table_offset = rsz_offset + instance_offset
    return {
        struct.unpack_from("<I", data, table_offset + index * 8)[0]
        for index in range(instance_count)
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--type-db", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    type_db = json.loads(args.type_db.read_text(encoding="utf-8"))
    hashes: set[int] = set()
    source_files = sorted(args.source.rglob("*.user.3"))
    if not source_files:
        raise ValueError(f"no .user.3 files found under {args.source}")
    for source_file in source_files:
        hashes.update(type_hashes(source_file))

    schema = {}
    for type_hash in sorted(hashes):
        key = f"{type_hash:x}"
        if key not in type_db:
            raise ValueError(f"type 0x{type_hash:X} is missing from the source type database")
        schema[key] = type_db[key]

    args.output.write_text(json.dumps(schema, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"Wrote {len(schema)} type definitions to {args.output}")


if __name__ == "__main__":
    main()
