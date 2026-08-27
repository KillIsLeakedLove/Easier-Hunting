# Easier Hunting

**Language / 语言:** [English](#english) | [简体中文](#zh-cn)

<a id="english"></a>

## English

`Easier Hunting` is a Monster Hunter Wilds TU4.1 stat mod for offline or
private play. It multiplies selected equipment stats by **3x** and adds **20**
to every armor elemental resistance.

### Effects

#### Armor

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

#### Hunter Weapons

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

### Requirements

- Monster Hunter Wilds TU4.1 data set used for this archive.
- Fluffy Mod Manager.
- A game restart after changing the mod state in FMM.

The archive contains ordinary `natives/STM/...` files. It does not need a
custom PAK builder, a runtime Lua stat hook, or an extra plugin.

### Installation With FMM

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

Do not enable Easier Hunting together with another mod that replaces any of the
same armor or weapon data files. The last-installed file wins and can make the
visible stats inconsistent with the intended 3x values.

### Manual Test Checklist

After loading a save, verify at least one armor piece and one weapon:

1. Open hunter armor details and compare its defense to the normal value.
2. Check the same armor after applying upgrade levels.
3. Open a hunter weapon's details and verify raw attack is 3x.
4. Verify each armor elemental resistance receives a +20 increase.
5. For a weapon with an innate element, verify its displayed element value is
   3x.
6. For a weapon without an innate element, verify the element remains zero.
7. Verify an Otomo armor piece receives the same +20 resistance behavior.

### Repository Layout

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

### Build From Source

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

### Validate A Build

```powershell
& "C:\Users\Leon\AppData\Local\Python\bin\python.exe" tools\verify_dist.py
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

### Updating For A Future Game Patch

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

### Compatibility And Safety

This mod intentionally changes combat-relevant player stats. Use it for
offline, solo, or private sessions where all participants agree on the change.
Do not assume it is safe for public multiplayer or progression-sensitive
content.

The builder and verifier operate only on archived source files. They do not
launch FMM, start the game, edit save data, or modify the installed game
directory.

[Back to language selection](#easier-hunting)

<a id="zh-cn"></a>

## 简体中文

`Easier Hunting` 是一个适用于《怪物猎人：荒野》TU4.1 的数值 mod，面向
离线、单人或私人联机使用。它会将指定装备数值变为 **3 倍**，并为所有防具
的每项属性耐性增加 **20**。

### 修改内容

#### 防具

| 范围 | 修改数据 | 结果 |
| --- | --- | --- |
| 猎人防具 | 基础防御力 | 3 倍 |
| 猎人防具 | 火、水、雷、冰、龙属性耐性 | 每项 +20 |
| 随从防具 | 基础防御力 | 3 倍 |
| 随从防具 | 属性耐性 | 每项 +20 |
| 防具强化 | 每级强化提供的防御力 | 3 倍 |

强化增量也会被一起处理，因此已经强化过的防具与未强化基础值保持相同的
三倍规则。耐性是加法修改：`-20` 变为 `0`，`0` 变为 `20`，`15` 变为
`35`。

#### 猎人武器

包内包含 14 类猎人武器数据。每件武器记录中的以下正数会变为 3 倍：

| 字段 | 游戏内含义 |
| --- | --- |
| `_Attack` | 白字攻击力 / 原始攻击力 |
| `_AttributeValue` | 主属性攻击力 |
| `_SubAttributeValue` | 副属性攻击力 |

零值和特殊哨兵值会保留。弩炮的属性弹药不属于武器固有属性字段，因此不会被
修改；随从武器也不会被修改。

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

### 使用要求

- 当前包对应的《怪物猎人：荒野》TU4.1 数据版本。
- Fluffy Mod Manager。
- 在 FMM 修改 mod 状态后重启游戏。

本包包含普通的 `natives/STM/...` 文件，不需要自定义 PAK 构建器、运行时 Lua
数值脚本或额外插件。

### 通过 FMM 安装

FMM 产物为：

```text
dist/Easier Hunting - TU4.1.zip
```

它也已复制到当前配置的 FMM Mods 目录：

```text
D:\apps\Fluffy Mod Manager 818 3.081 2026-08-06T20-58Z xP2UbCJPm\Games\MonsterHunterWilds\Mods\Easier Hunting - TU4.1.zip
```

启用前请按以下顺序操作：

1. 在 FMM 中禁用 `2x Armor Defense - Final TU4.1 Flat`。
2. 刷新 FMM mod 列表。
3. 启用 `Easier Hunting`。
4. 确认 FMM 显示复制成功且没有文件复制错误。
5. 通过 FMM 启动游戏并重新读档。

不要同时启用会替换相同防具或武器数据文件的其他 mod。FMM 最后安装的文件
会覆盖前一个文件，可能导致游戏内数值与预期的 3 倍不一致。

### 手动测试清单

进入存档后，至少检查一件防具和一件武器：

1. 打开猎人防具详情，将防御力与原版数值比较。
2. 对有强化等级的防具再次检查强化后的防御力。
3. 打开猎人武器详情，确认白字攻击力为原来的 3 倍。
4. 检查防具的每一项属性耐性是否增加 20。
5. 对带有固有属性的武器，确认显示的属性攻击力为原来的 3 倍。
6. 对没有固有属性的武器，确认属性值仍为 0。
7. 检查一件随从防具是否同样获得每项 +20 的耐性加成。

### 仓库结构

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

源目录包含 17 个原始游戏数据文件：

- 3 个防具与防具强化文件
- 14 个猎人武器文件

### 从源码构建

构建器只使用 Python 标准库，建议使用 Python 3.10 或更高版本。

```powershell
& "C:\Users\Leon\AppData\Local\Python\bin\python.exe" tools\build_mod.py
```

默认输出：

```text
dist/Easier Hunting - TU4.1.zip
```

如需输出到其他位置而不修改 `dist/`：

```powershell
& "C:\Users\Leon\AppData\Local\Python\bin\python.exe" tools\build_mod.py --output "D:\output\Easier Hunting - TU4.1.zip"
```

### 校验构建结果

```powershell
& "C:\Users\Leon\AppData\Local\Python\bin\python.exe" tools\verify_dist.py
```

校验项目包括：

- 压缩包必须正好包含 `modinfo.ini` 和 17 个游戏数据文件。
- ZIP 不包含目录条目，避免 FMM 复制目录时产生错误。
- 修改前后每个 RSZ 实例数据流都必须完整到达文件末尾。
- 每个产物文件都必须与从 `source/` 全新构建的 3 倍、耐性 +20 结果一致。
- 正数攻击力和防御力会按倍率修改，零值和负数哨兵值保持不变。
- 防具耐性数组会逐元素增加 20，包括原本为负数或零的耐性。

### 更新到未来游戏版本

游戏更新可能替换防具或武器数据。数据更新后，不能直接基于当前快照重新构建，
必须先刷新源文件。

1. 从当前安装的官方 patch 中提取 `source/SOURCE_ORIGINS.md` 列出的最新文件。
2. 替换 `source/natives/` 下对应的文件。
3. 获取当前版本完整的 `rszmhwilds.json` schema dump。
4. 重新生成精简 schema：

   ```powershell
   & "C:\Users\Leon\AppData\Local\Python\bin\python.exe" tools\extract_schema.py `
     --type-db "C:\path\to\rszmhwilds.json" `
     --source source `
     --output source\type_schema.json
   ```

5. 运行 `tools\build_mod.py` 和 `tools\verify_dist.py`。
6. 确认源文件与产物无误后更新 `SHA256SUMS.txt`。

### 兼容性与安全提示

本 mod 会有意修改影响战斗的玩家数值。建议仅用于离线、单人或所有参与者都
同意的私人联机环境。不要默认它适用于公开多人游戏或对进度敏感的内容。

构建器和校验器只操作仓库内的归档源文件，不会启动 FMM、启动游戏、修改存档，
也不会修改游戏安装目录。

[返回语言选择](#easier-hunting)
