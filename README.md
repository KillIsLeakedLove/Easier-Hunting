# Easier Hunting

**Language / 语言:** [English](README.md) | [简体中文](README.zh-CN.md)

This mod was written entirely by AI and published after human verification.  
本模组完全由 AI 编写，且经由人工验证完成后发布。

Monster Hunter Wilds TU4.1 FMM pack for offline / solo / private play.  
《怪物猎人：荒野》TU4.1 用的 FMM 数值包，面向离线 / 单人 / 私人联机。

| Feature / 功能 | Effect / 效果 |
| --- | --- |
| Hunter weapon attack / 猎人武器攻击 | 2x or 4x (raw + innate element) / 2 倍或 4 倍（白字 + 固有属性） |
| Hunter armor defense / 猎人防具防御 | 2x or 4x (base + upgrades) / 2 倍或 4 倍（基础 + 强化） |
| Elemental resistance / 属性耐性 | +2 or +4 per armor piece per element / 每件防具各元素 +2 或 +4 |
| Monster knockdown / 怪物击倒 | Part/wound thresholds about 1/10 / 部位与伤口耐久约为 1/10 |
| Quest retries / 任务重试 | Cap 99 (requires REFramework) / 上限 99（需已安装 REFramework） |

Otomo gear is unchanged. Zeros and negative sentinels are left alone. Monster HP and attack are not changed by the knockdown option.  
随从装备不改。零值和负数哨兵不放大。易击倒档不改怪物血量和攻击。

## Package / 分包（v1.7.100）

One zip: [`Easier Hunting - TU4.1.zip`](dist/Easier%20Hunting%20-%20TU4.1.zip)  
一个压缩包：同上。

In FMM, open **Easier Hunting**. There are three independent groups. Enable **exactly one** option in each group.  
在 FMM 里点开 **Easier Hunting**。三组功能互相独立，**每组只开其中一个**。

| Group / 分组 | Options / 选项 |
| --- | --- |
| **1. Attack / Defense / Resistance** | **On (2x)**: 2x attack/defense, +2 resistance per piece / 攻击/防御 2 倍，每件耐性 +2 · **On (4x)**: 4x attack/defense, +4 resistance per piece / 攻击/防御 4 倍，每件耐性 +4 · **Off (vanilla)**: vanilla hunter stats / 还原原版猎人数值 |
| **2. Quest Retries** | **On (99)**: faint/cart cap 99 / 倒下上限 99 · **Off (default)**: default retry cap / 游戏默认倒下次数 |
| **3. Monster Knockdown** | **On (easy)**: part/wound stagger about 10x easier / 部位与伤口更容易击倒约 10 倍 · **Off (vanilla stagger)**: vanilla part/wound rates / 还原原版部位与伤口倍率 |

Pick any combination across the three groups.  
三组可以任意组合。

## Install / 安装

1. In FMM, disable and remove older Easier Hunting zips (including the v1.6 split Stats / Retries packs).  
   在 FMM 里关掉并移除旧版 Easier Hunting（包括 v1.6 拆开的 Stats / Retries 包）。
2. Copy `Easier Hunting - TU4.1.zip` into FMM's Wilds `Mods` folder.  
   把 `Easier Hunting - TU4.1.zip` 放进 FMM 的 Wilds `Mods` 目录。
3. Refresh, open **Easier Hunting**, pick one option in each group, then start the game from FMM.  
   刷新，打开 **Easier Hunting**，每组只选一项，再用 FMM 启动游戏。

Only use retries and easier knockdown offline / solo / in private sessions.  
重试和易击倒只建议离线 / 单人 / 私人局使用。

## Build / 构建

```powershell
py -3 tools\build_mod.py
py -3 tools\verify_dist.py
```
