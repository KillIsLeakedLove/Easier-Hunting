# Easier Hunting

`Easier Hunting` is a Monster Hunter Wilds TU4.1 stat mod for offline or
private play. It multiplies the selected equipment stats by **3x** while
adding **20** to each armor elemental resistance, while leaving unrelated
systems untouched.

## Effects

### Armor

| Scope | Modified data | Result |
| --- | --- | --- |
| Hunter armor | Base defense | 3x |
| Hunter armor | Fire, water, thunder, ice, and dragon resistance | +20 each |
| Otomo armor | Base defense | 3x |
| Otomo armor | Elemental resistance | +20 each |
| Armor upgrades | Defense gained per upgrade level | 3x |

Including the upgrade increment means fully upgraded armor receives the same
threefold treatment instead of only multiplying its unupgraded base value.
The resistance bonus is additive, so a resistance of `-20` becomes `0`, a
resistance of `0` becomes `20`, and a resistance of `15` becomes `35`.

### Hunter Weapons

All 14 hunter weapon data files are included. For every weapon record, the
following positive values are multiplied by 3:

| Field | In-game meaning |
| --- | --- |
| `_Attack` | Raw / displayed white attack |
| `_AttributeValue` | Primary innate elemental attack |
| `_SubAttributeValue` | Secondary innate elemental attack |

Zero values and sentinel values are preserved. This matters for weapons with
no innate element. Bowgun elemental ammunition is not an innate weapon
attribute and is intentionally not modified. Otomo weapons are also unchanged.

The included weapon classes are Bow, Charge Axe, Gunlance, Hammer, Heavy
Bowgun, Lance, Light Bowgun, Long Sword, Insect Glaive, Sword and Shield,
Switch Axe, Great Sword, Dual Blades, and Hunting Horn. Internal file names
use Capcom naming such as `Rod`, `ShortSword`, and `Tachi`.

## Requirements

- Monster Hunter Wilds TU4.1 data set used for this archive.
- Fluffy Mod Manager.
- A restart after changing the mod state in FMM.

The archive contains ordinary `natives/STM/...` files. It does not need a
custom PAK builder, a runtime Lua stat hook, or any extra plugin.

## Installation With FMM

The FMM-ready artifact is:

```text
dist/Easier Hunting - TU4.1.zip
```

It is also copied to the configured FMM Mods directory:

```text
D:\apps\Fluffy Mod Manager 818 3.081 2026-08-06T20-58Z xP2UbCJPm\Games\MonsterHunterWilds\Mods\Easier Hunting - TU4.1.zip
```

Before enabling Easier Hunting:

1. Disable `2x Armor Defense - Final TU4.1 Flat` in FMM.
2. Refresh the FMM mod list.
3. Enable `Easier Hunting`.
4. Confirm FMM reports successful copying with no file-copy errors.
5. Start the game through FMM and load the save again.

Do not enable Easier Hunting together with another mod that replaces any of
these same armor or weapon data files. The last-installed file wins, which can
make the visible stats inconsistent with the intended 3x values.

## Manual Test Checklist

After loading a save, verify at least one armor piece and one weapon:

1. Open equipment details for a hunter armor piece and compare its defense to
   its normal value.
2. Check the same armor after upgrades if it has upgrade levels applied.
3. Open a hunter weapon's detail page and verify raw attack is 3x.
4. Verify each listed elemental resistance receives a +20 increase.
5. For a weapon with innate fire, water, thunder, ice, or dragon, verify its
   displayed element value is 3x.
6. For a weapon without innate element, element should remain zero.

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
  tools/verify_dist.py  Byte-for-byte archive verifier
  SHA256SUMS.txt        Hashes for source files and generated archive
```

The source directory contains 17 original game data files:

- 3 armor and armor-upgrade files
- 14 hunter weapon files

## Build From Source

The builder uses only the Python standard library. Python 3.10 or newer is
recommended.

```powershell
& "C:\Users\Leon\AppData\Local\Python\bin\python.exe" tools\build_mod.py
```

By default it writes a deterministic archive to:

```text
dist/Easier Hunting - TU4.1.zip
```

To write elsewhere without modifying `dist/`:

```powershell
& "C:\Users\Leon\AppData\Local\Python\bin\python.exe" tools\build_mod.py --output "D:\output\Easier Hunting - TU4.1.zip"
```

## Validate A Build

```powershell
& "C:\Users\Leon\AppData\Local\Python\bin\python.exe" tools\verify_dist.py
```

Validation checks all of the following:

- The archive contains exactly `modinfo.ini` plus 17 game data files.
- The ZIP has no directory entries, avoiding FMM directory-copy errors.
- Every RSZ instance stream reaches EOF before and after transformation.
- Every changed payload exactly matches a fresh 3x and +20 resistance rebuild
  from `source/`.
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
   & "C:\Users\Leon\AppData\Local\Python\bin\python.exe" tools\extract_schema.py `
     --type-db "C:\path\to\rszmhwilds.json" `
     --source source `
     --output source\type_schema.json
   ```

5. Run `tools\build_mod.py` and `tools\verify_dist.py`.
6. Update `SHA256SUMS.txt` after confirming the new source and archive.

## Compatibility And Safety

This mod intentionally changes combat-relevant player stats. Use it for
offline, solo, or private sessions where all participants agree on the change.
Do not assume it is safe for public multiplayer or progression-sensitive
content.

The builder and verifier operate only on archived source files. They do not
launch FMM, start the game, edit save data, or modify the installed game
directory.
