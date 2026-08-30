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

## 分包（v1.6.0）

| 压缩包 | 内容 |
| --- | --- |
| [`Easier Hunting - TU4.1.zip`](dist/Easier%20Hunting%20-%20TU4.1.zip) | 完整：数值 + 99 倒下 |
| [`Easier Hunting Stats - TU4.1.zip`](dist/Easier%20Hunting%20Stats%20-%20TU4.1.zip) | 仅数值（无重试脚本） |
| [`Easier Hunting Retries - TU4.1.zip`](dist/Easier%20Hunting%20Retries%20-%20TU4.1.zip) | 仅 99 倒下（无数值文件） |

不要同时启用完整包与 Stats（数值会叠），也不要完整包与 Retries 一起开（脚本重复）。Stats + Retries 两个分包可以一起用。

## 安装

1. 在 FMM 里卸掉旧版 Easier Hunting 相关包。
2. 把需要的 zip 放进 FMM 的 Wilds `Mods` 目录。
3. 刷新并启用，重启游戏。

重试只建议离线 / 单人 / 私人局使用。

## 构建

```powershell
py -3 tools\build_mod.py
py -3 tools\verify_dist.py
```

[English](README.md)
