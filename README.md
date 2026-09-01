# Easier Hunting

**Language / 语言:** [English](README.md) | [简体中文](README.zh-CN.md)

Monster Hunter Wilds TU4.1 FMM pack for offline / solo / private play.

| Feature | Effect |
| --- | --- |
| Hunter weapon attack | 2x (raw + innate element) |
| Hunter armor defense | 2x (base + upgrades) |
| Elemental resistance | +2 per armor piece per element (~+10 full set) |
| Quest retries | Cap 99 (requires REFramework) |

Otomo gear is unchanged. Zeros and negative sentinels are left alone.

## Package (v1.7.93)

One zip: [`Easier Hunting - TU4.1.zip`](dist/Easier%20Hunting%20-%20TU4.1.zip)

In FMM, open **Easier Hunting**. There are two independent groups. Enable **exactly one** option in each group:

| Group | On | Off |
| --- | --- | --- |
| **1. Attack / Defense / Resistance** | 2x attack/defense, +2 resistance per piece | Vanilla hunter stats |
| **2. Quest Retries** | Faint/cart cap 99 | Default retry cap |

The four combinations are: stats only, retries only, both, or neither.

## Install

1. In FMM, disable and remove older Easier Hunting zips (including the v1.6 split Stats / Retries packs).
2. Copy `Easier Hunting - TU4.1.zip` into FMM's Wilds `Mods` folder.
3. Refresh, open **Easier Hunting**, pick On or Off in each group, then start the game from FMM.

Only use retries offline / solo / in private sessions.

## Build

```powershell
py -3 tools\build_mod.py
py -3 tools\verify_dist.py
```

[简体中文](README.zh-CN.md)
