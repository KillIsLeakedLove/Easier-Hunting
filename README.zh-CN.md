# Easier Hunting

**语言 / Language:** [简体中文](README.zh-CN.md) | [English](README.md)

本模组完全由 AI 编写，且经由人工验证完成后发布。  
This mod was written entirely by AI and published after human verification.

《怪物猎人：荒野》TU4.1 用的 FMM 数值包，面向离线 / 单人 / 私人联机。  
Monster Hunter Wilds TU4.1 FMM pack for offline / solo / private play.

| 功能 / Feature | 效果 / Effect |
| --- | --- |
| 猎人武器攻击 / Hunter weapon attack | 2 倍或 4 倍（白字 + 固有属性） / 2x or 4x (raw + innate element) |
| 猎人防具防御 / Hunter armor defense | 2 倍或 4 倍（基础 + 强化） / 2x or 4x (base + upgrades) |
| 属性耐性 / Elemental resistance | 每件防具火/水/雷/冰/龙各 +2 或 +4 / +2 or +4 per armor piece per element |
| 怪物击倒 / Monster knockdown | 部位与伤口耐久约为 1/10 / part/wound thresholds about 1/10 |
| 任务重试 / Quest retries | 上限 99（需已安装 REFramework） / Cap 99 (requires REFramework) |

随从装备不改。零值和负数哨兵不放大。易击倒档不改怪物血量和攻击。  
Otomo gear is unchanged. Zeros and negative sentinels are left alone. Monster HP and attack are not changed by the knockdown option.

## 分包 / Package（v1.7.100）

一个压缩包：[`Easier Hunting - TU4.1.zip`](dist/Easier%20Hunting%20-%20TU4.1.zip)  
One zip: same file.

在 FMM 里点开 **Easier Hunting**。三组功能互相独立，**每组只开其中一个**。  
In FMM, open **Easier Hunting**. There are three independent groups. Enable **exactly one** option in each group.

| 分组 / Group | 选项 / Options |
| --- | --- |
| **1. Attack / Defense / Resistance** | **On (2x)**：攻击/防御 2 倍，每件耐性 +2 / 2x attack/defense, +2 resistance per piece · **On (4x)**：攻击/防御 4 倍，每件耐性 +4 / 4x attack/defense, +4 resistance per piece · **Off (vanilla)**：还原原版猎人数值 / vanilla hunter stats |
| **2. Quest Retries** | **On (99)**：倒下上限 99 / faint/cart cap 99 · **Off (default)**：游戏默认倒下次数 / default retry cap |
| **3. Monster Knockdown** | **On (easy)**：部位与伤口更容易击倒约 10 倍 / part/wound stagger about 10x easier · **Off (vanilla stagger)**：还原原版部位与伤口倍率 / vanilla part/wound rates |

三组可以任意组合。  
Pick any combination across the three groups.

## 安装 / Install

1. 在 FMM 里关掉并移除旧版 Easier Hunting（包括 v1.6 拆开的 Stats / Retries 包）。  
   In FMM, disable and remove older Easier Hunting zips (including the v1.6 split Stats / Retries packs).
2. 把 `Easier Hunting - TU4.1.zip` 放进 FMM 的 Wilds `Mods` 目录。  
   Copy `Easier Hunting - TU4.1.zip` into FMM's Wilds `Mods` folder.
3. 刷新，打开 **Easier Hunting**，每组只选一项，再用 FMM 启动游戏。  
   Refresh, open **Easier Hunting**, pick one option in each group, then start the game from FMM.

重试和易击倒只建议离线 / 单人 / 私人局使用。  
Only use retries and easier knockdown offline / solo / in private sessions.

## 构建 / Build

```powershell
py -3 tools\build_mod.py
py -3 tools\verify_dist.py
```
