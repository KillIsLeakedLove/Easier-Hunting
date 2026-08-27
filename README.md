# Easier Hunting

**Language / 语言:** [English](README.md) | [简体中文](README.zh-CN.md)

`Easier Hunting` is a Monster Hunter Wilds TU4.1 stat mod for offline or
private play. It multiplies selected equipment stats by **3x** and adds **20**
to every armor elemental resistance.

## Effects

### Armor

| Scope | Modified data | Result |
| --- | --- | --- |
| Hunter armor | Base defense | 3x |
| Hunter armor | Fire, water, thunder, ice, and dragon resistance | +20 each |
| Otomo armor | Base defense | 3x |
| Otomo armor | Elemental resistance | +20 each |
| Armor upgrades | Defense gained per upgrade level | 3x |

The upgrade increment is also multiplied, so upgraded armor receives the same
threefold treatment as its unupgraded base value. Resistance is additive:
`-20` becomes `0`, `0` becomes `20`, and `15` becomes `35`.

### Hunter Weapons

All 14 hunter weapon data files are included. For every weapon record, these
positive values are multiplied by 3:

| Field | In-game meaning |
| --- | --- |
| `_Attack` | Raw / displayed white attack |
| `_AttributeValue` | Primary innate elemental attack |
| `_SubAttributeValue` | Secondary innate elemental attack |

Zero values and sentinel values are preserved. Bowgun elemental ammunition is
not an innate weapon attribute and is intentionally not modified. Otomo weapons
are also unchanged.

Included weapon classes:

- Bow
- Charge Axe
- Gunlance
- Hammer
- Heavy Bowgun
- Lance
- Light Bowgun
- Long Sword
- Insect Glaive
- Sword and Shield
- Switch Axe
- Great Sword
- Dual Blades
- Hunting Horn

Internal file names use Capcom naming such as `Rod`, `ShortSword`, and `Tachi`.

## Requirements

- Monster Hunter Wilds TU4.1 data set used for this archive.
- Fluffy Mod Manager.
- A game restart after changing the mod state in FMM.

The archive contains ordinary `natives/STM/...` files. It does not need a
custom PAK builder, a runtime Lua stat hook, or an extra plugin.

## Installation With FMM

Use the archive at [`dist/Easier Hunting - TU4.1.zip`](dist/Easier%20Hunting%20-%20TU4.1.zip).
Copy it into your FMM game's `Mods` directory, then enable it from FMM.

Before enabling Easier Hunting:

1. Disable any older armor-defense mod, including `2x Armor Defense - Final
   TU4.1 Flat`.
2. Refresh the FMM mod list.
3. Enable `Easier Hunting`.
4. Confirm FMM reports successful copying with no file-copy errors.
5. Start the game through FMM and load the save again.

Do not enable Easier Hunting together with another mod that replaces any of the
same armor or weapon data files. The last-installed file wins and can make the
visible stats inconsistent with the intended 3x values.

## Manual Test Checklist

After loading a save, verify at least one armor piece and one weapon:

1. Open hunter armor details and compare its defense to the normal value.
2. Check the same armor after applying upgrade levels.
3. Open a hunter weapon's details and verify raw attack is 3x.
4. Verify each armor elemental resistance receives a +20 increase.
5. For a weapon with an innate element, verify its displayed element value is
   3x.
6. For a weapon without an innate element, verify the element remains zero.
7. Verify an Otomo armor piece receives the same +20 resistance behavior.

## Repository Layout

```text
easier-hunting/
  dist/                 Generated FMM archive
  source/               Clean archived TU4.1 game data snapshot
  source/SOURCE_ORIGINS.md
                        Official patch provenance for every source file
  source/type_schema.json
                        Minimal RSZ type schema needed by the builder
  tools/build_mod.py    Deterministic archive builder
  tools/extract_schema.py
                        Schema reducer for future game updates
  tools/verify_dist.py  Byte-for-byte stat and archive verifier
  SHA256SUMS.txt        Hashes for source files and generated archive
```

The source directory contains 17 original game data files:

- 3 armor and armor-upgrade files
- 14 hunter weapon files

## Build From Source

The builder uses only the Python standard library. Python 3.10 or newer is
recommended. Run it with the `python` command available in your environment:

```powershell
python tools\build_mod.py
```

If your system uses the Python launcher:

```powershell
py -3 tools\build_mod.py
```

By default it writes a deterministic archive to:

```text
dist/Easier Hunting - TU4.1.zip
```

To write elsewhere without modifying `dist/`:

```powershell
python tools\build_mod.py --output "path\to\Easier Hunting - TU4.1.zip"
```

## Validate A Build

```powershell
python tools\verify_dist.py
```

Validation checks all of the following:

- The archive contains exactly `modinfo.ini` plus 17 game data files.
- The ZIP has no directory entries, avoiding FMM directory-copy errors.
- Every RSZ instance stream reaches EOF before and after transformation.
- Every archive payload matches a fresh 3x and +20 resistance rebuild from
  `source/`.
- Positive attack and defense values are multiplied while zero and negative
  sentinel values are preserved.
- Armor resistance arrays are adjusted element-by-element by +20, including
  negative and zero values.

## Updating For A Future Game Patch

Game updates may replace armor or weapon data. Do not rebuild from this source
snapshot after a data-changing update without refreshing the source files.

1. Extract the newest version of each data file listed in
   `source/SOURCE_ORIGINS.md` from the installed official patch set.
2. Replace the corresponding file under `source/natives/`.
3. Obtain a current full `rszmhwilds.json` schema dump.
4. Regenerate the compact schema:

   ```powershell
   python tools\extract_schema.py `
     --type-db "path\to\rszmhwilds.json" `
     --source source `
     --output source\type_schema.json
   ```

5. Run `python tools\build_mod.py` and `python tools\verify_dist.py`.
6. Update `SHA256SUMS.txt` after confirming the new source and archive.

## Compatibility And Safety

This mod intentionally changes combat-relevant player stats. Use it for
offline, solo, or private sessions where all participants agree on the change.
Do not assume it is safe for public multiplayer or progression-sensitive
content.

The builder and verifier operate only on archived source files. They do not
launch FMM, start the game, edit save data, or modify the installed game
directory.

[简体中文](README.zh-CN.md)
