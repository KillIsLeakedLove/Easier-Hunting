# Easier Hunting

**语言 / Language:** [简体中文](README.zh-CN.md) | [English](README.md)

《怪物猎人：荒野》TU4.1 用的 FMM 数值包，面向离线 / 单人 / 私人联机。

| 项目 | 效果 |
| --- | --- |
| 猎人武器攻击 | 2 倍（白字 + 固有属性） |
| 猎人防具防御 | 2 倍（基础 + 强化） |
| 属性耐性 | 每件防具火/水/雷/冰/龙各 +2（满装约 +10） |
| 任务重试 | 上限 99（需已安装 REFramework） |

随从装备不改。零值和负数哨兵不放大。

## 分包（v1.7.93）

一个压缩包：[`Easier Hunting - TU4.1.zip`](dist/Easier%20Hunting%20-%20TU4.1.zip)

在 FMM 里点开 **Easier Hunting**。两组功能互相独立，**每组只开其中一个**：

| 分组 | On | Off |
| --- | --- | --- |
| **1. Attack / Defense / Resistance** | 攻击/防御 2 倍，每件耐性 +2 | 还原原版猎人数值 |
| **2. Quest Retries** | 倒下上限 99 | 游戏默认倒下次数 |

四种组合都可以：只开数值、只开重试、两个都开、两个都关。

## 安装

1. 在 FMM 里关掉并移除旧版 Easier Hunting（包括 v1.6 拆开的 Stats / Retries 包）。
2. 把 `Easier Hunting - TU4.1.zip` 放进 FMM 的 Wilds `Mods` 目录。
3. 刷新，打开 **Easier Hunting**，每组选 On 或 Off，再用 FMM 启动游戏。

重试只建议离线 / 单人 / 私人局使用。

## 构建

```powershell
py -3 tools\build_mod.py
py -3 tools\verify_dist.py
```

[English](README.md)
