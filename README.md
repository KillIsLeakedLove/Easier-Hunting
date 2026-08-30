# Easier Hunting

**Language / 语言:** [English](README.md) | [简体中文](README.zh-CN.md)

Monster Hunter Wilds TU4.1 FMM pack for offline / solo / private play. Fixed values:

| Feature | Effect |
| --- | --- |
| Hunter weapon attack | 2x (raw + innate element) |
| Hunter armor defense | 2x (base + upgrades) |
| Elemental resistance | +2 per armor piece per element (~+10 full set) |
| Quest retries | Cap 99 (requires REFramework) |

Otomo gear is unchanged. Zeros and negative sentinels are left alone.

## Install

1. Disable old Easier Hunting and any separate retry mod in FMM.
2. Copy [`dist/Easier Hunting - TU4.1.zip`](dist/Easier%20Hunting%20-%20TU4.1.zip) into FMM's Wilds `Mods` folder.
3. Refresh, enable, restart the game.

Only use retries offline / solo / in private sessions.

## Build

```powershell
py -3 tools\build_mod.py
py -3 tools\verify_dist.py
```

[简体中文](README.zh-CN.md)
