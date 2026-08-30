# Easier Hunting

**Language / 语言:** [English](README.md) | [简体中文](README.zh-CN.md)

Monster Hunter Wilds TU4.1 FMM packs for offline / solo / private play.

| Feature | Effect |
| --- | --- |
| Hunter weapon attack | 2x (raw + innate element) |
| Hunter armor defense | 2x (base + upgrades) |
| Elemental resistance | +2 per armor piece per element (~+10 full set) |
| Quest retries | Cap 99 (requires REFramework) |

Otomo gear is unchanged. Zeros and negative sentinels are left alone.

## Packages (v1.6.0)

| Zip | Contents |
| --- | --- |
| [`Easier Hunting - TU4.1.zip`](dist/Easier%20Hunting%20-%20TU4.1.zip) | Full: stats + 99 retries |
| [`Easier Hunting Stats - TU4.1.zip`](dist/Easier%20Hunting%20Stats%20-%20TU4.1.zip) | Stats only (no retry script) |
| [`Easier Hunting Retries - TU4.1.zip`](dist/Easier%20Hunting%20Retries%20-%20TU4.1.zip) | 99 retries only (no stat files) |

Do **not** enable the full pack together with Stats (double stats) or together with Retries (duplicate script). Stats + Retries as two separate packs is fine.

## Install

1. Disable old Easier Hunting packs in FMM.
2. Copy the zip(s) you want into FMM's Wilds `Mods` folder.
3. Refresh, enable, restart the game.

Only use retries offline / solo / in private sessions.

## Build

```powershell
py -3 tools\build_mod.py
py -3 tools\verify_dist.py
```

[简体中文](README.zh-CN.md)
