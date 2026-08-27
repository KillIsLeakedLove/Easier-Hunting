# Easier Hunting

**语言 / Language:** [简体中文](README.zh-CN.md) | [English](README.md)

`Easier Hunting` 是一个适用于《怪物猎人：荒野》TU4.1 的数值 mod，面向离线、
单人或私人联机使用。它会将猎人主体的指定装备数值变为 **2 倍**，并让一套完整
的五件猎人防具的每项属性耐性总计增加 **20**。

## 修改内容

### 猎人防具

| 修改数据 | 结果 |
| --- | --- |
| 基础防御力 | 2 倍 |
| 火、水、雷、冰、龙属性耐性 | 完整五件套总计 +20 |
| 每级防具强化提供的防御力 | 2 倍 |

游戏会将已装备的五件防具耐性相加，因此 mod 将每件防具的耐性各增加 `4`，
完整配装后正好得到预期的总计 `+20`。负数、零和正数都按加法正确处理。例如，
完整配装原本为 `-20` 时变为 `0`，原本为 `0` 时变为 `20`，原本为 `15` 时变为
`35`。

### 猎人武器

包内包含 14 类猎人武器数据。每件武器记录中的以下正数会变为 2 倍：

| 字段 | 游戏内含义 |
| --- | --- |
| `_Attack` | 白字攻击力 / 原始攻击力 |
| `_AttributeValue` | 主属性攻击力 |
| `_SubAttributeValue` | 副属性攻击力 |

零值和特殊哨兵值会保留。弩炮的属性弹药不属于武器固有属性字段，因此不会被
修改。随从装备，包括随从武器和随从防具，均保持不变。

包含的武器类别：

- 弓
- 盾斧
- 铳枪
- 大锤
- 重弩
- 长枪
- 轻弩
- 太刀
- 操虫棍
- 单手剑与盾
- 斩斧
- 大剑
- 双剑
- 狩猎笛

文件名使用卡普空内部命名，例如 `Rod`、`ShortSword` 和 `Tachi`。

## 使用要求

- 当前包对应的《怪物猎人：荒野》TU4.1 数据版本。
- Fluffy Mod Manager。
- 在 FMM 修改 mod 状态后重启游戏。

本包包含普通的 `natives/STM/...` 文件，不需要自定义 PAK 构建器、运行时 Lua
数值脚本或额外插件。

## 通过 FMM 安装

使用仓库中的 [`dist/Easier Hunting - TU4.1.zip`](dist/Easier%20Hunting%20-%20TU4.1.zip)。
将它复制到 FMM 为本游戏配置的 `Mods` 目录，然后在 FMM 中启用。

启用前请按以下顺序操作：

1. 在 FMM 中禁用所有旧的防具或武器数值 mod，包括 `2x Armor Defense - Final
   TU4.1 Flat`。
2. 刷新 FMM mod 列表。
3. 启用 `Easier Hunting`。
4. 确认 FMM 显示复制成功且没有文件复制错误。
5. 通过 FMM 启动游戏并重新读档。

不要同时启用会替换相同防具或武器数据文件的其他 mod。FMM 最后安装的文件会
覆盖前一个文件，可能导致游戏内数值与预期不一致。

## 手动测试清单

进入存档后，至少检查一件防具和一件猎人武器：

1. 打开猎人防具详情，将防御力与原版数值比较。
2. 对有强化等级的防具再次检查强化后的防御力。
3. 打开猎人武器详情，确认白字攻击力为原来的 2 倍。
4. 检查完整防具套装的属性耐性总值，确认比原版增加 20，包括原本为负数的情况。
5. 对带有固有属性的武器，确认显示的属性攻击力为原来的 2 倍。
6. 对没有固有属性的武器，确认属性值仍为 0。
7. 确认随从装备没有被修改。

## 仓库结构

```text
easier-hunting/
  dist/                 生成的 FMM 压缩包
  source/               归档的 TU4.1 原始游戏数据
  source/SOURCE_ORIGINS.md
                        每个源文件的官方 patch 来源
  source/type_schema.json
                        构建器所需的最小 RSZ 类型 schema
  tools/build_mod.py    确定性构建脚本
  tools/extract_schema.py
                        为未来游戏版本提取精简 schema
  tools/verify_dist.py  数据和压缩包校验脚本
  SHA256SUMS.txt        源文件和生成包的哈希清单
```

源目录包含 16 个原始游戏数据文件：

- 2 个猎人防具与防具强化文件
- 14 个猎人武器文件

仓库和生成包均不包含随从防具数据文件。

## 从源码构建

构建器只使用 Python 标准库，建议使用 Python 3.10 或更高版本。使用你当前环境
中可用的 `python` 命令运行：

```powershell
python tools\build_mod.py
```

如果系统使用 Python 启动器，也可以运行：

```powershell
py -3 tools\build_mod.py
```

默认输出：

```text
dist/Easier Hunting - TU4.1.zip
```

如需输出到其他位置而不修改 `dist/`：

```powershell
python tools\build_mod.py --output "path\to\Easier Hunting - TU4.1.zip"
```

## 校验构建结果

```powershell
python tools\verify_dist.py
```

校验项目包括：

- 压缩包必须正好包含 `modinfo.ini` 和 16 个游戏数据文件。
- ZIP 不包含目录条目，避免 FMM 复制目录时产生错误。
- 修改前后每个 RSZ 实例数据流都必须完整到达文件末尾。
- 每个产物文件都必须与从 `source/` 全新构建的 2 倍、每件防具 +4 耐性结果一致。
- 正数攻击力和防御力会按倍率修改，零值和负数哨兵值保持不变。
- 猎人防具耐性数组逐元素增加 4，五件已装备防具合计增加 20。
- 生成包中不存在任何随从数据文件。

## 更新到未来游戏版本

游戏更新可能替换防具或武器数据。数据更新后，不能直接基于当前快照重新构建，
必须先刷新源文件。

1. 从当前安装的官方 patch 中提取 `source/SOURCE_ORIGINS.md` 列出的最新文件。
2. 替换 `source/natives/` 下对应的文件。
3. 获取当前版本完整的 `rszmhwilds.json` schema dump。
4. 重新生成精简 schema：

   ```powershell
   python tools\extract_schema.py `
     --type-db "path\to\rszmhwilds.json" `
     --source source `
     --output source\type_schema.json
   ```

5. 运行 `python tools\build_mod.py` 和 `python tools\verify_dist.py`。
6. 确认源文件与产物无误后更新 `SHA256SUMS.txt`。

## 兼容性与安全提示

本 mod 会有意修改影响猎人主体战斗的数值。建议仅用于离线、单人或所有参与者都
同意的私人联机环境。不要默认它适用于公开多人游戏或对进度敏感的内容。

构建器和校验器只操作仓库内的归档源文件，不会启动 FMM、启动游戏、修改存档，也
不会修改游戏安装目录。

[English](README.md)
