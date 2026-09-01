# 调查任务「力尽倒下」次数：失败记录

给后续改 `easier_hunting_retries.lua` 用。自由任务 PAK `_QuestLife=99` 已经会显示 99；这里只记**调查 / KeepQuest 柜台文案仍显示 3** 这条线。

写新代码前先搜本文件。已经标了「禁止」的做法不要再试。

## 硬性禁止

| 禁止 | 原因 | 版本 |
| --- | --- | --- |
| 把 `via.gui.message.get` 的返回值换成 `sdk.create_managed_string(...)` | 立刻 `c0000005`。游戏要用字串表里的常驻指针 | 1.7.38 |
| 启动时遍历 `ParamData` 的 methods 并 hook | 进柜台 AV / 卡死 | 1.7.20 |
| 启动时 hook `via.gui.message.get` 做重活 | 黑屏 | 1.7.15 |
| `fail_life_post` 里对可能为 nil 的 typedef 链式 `:get_method` | 启动黑屏 | 1.7.36 |
| hook `getQuestLife` **返回值** 改成 99 | 除零崩溃 | 更早 |
| 把 `ParamUnion` 整段指针写成整数 99 | 界面变成 **0**（把 union 当成 int 覆盖了） | 1.7.23 |
| `SKIP_ORIGINAL` 掉 `addParam(3)` 却没有成功再 `addParam(99)` | 界面变成 **0** | 1.7.27 |
| 改 `ace.cGUIMessageInfo.Msg` / `set_Msg` | `after=99`、`rewrote msg 力尽倒下99次`，界面仍是 3。UI 不读这个字段 | 1.7.35–37 |
| hook `via.gui.Text.set_Message(System.String)` 指望改到这句 | 从未打到「力尽倒下3次」，`set_Text` 日志为 0 | 1.7.29–30 |
| hook `System.String.Format` 指望改到这句 | `Fmt str=0`，柜台不用它排这句 | 1.7.26+ |
| 在 `getFailConditionText_Life` **返回之后** 再改 `ParamValue` | `wrote=true after=99`，界面仍是 3。排版发生在原函数内部 | 1.7.21–41 |
| `addParam` 进函数前改参数槽（`to_int64(99)` 或 `to_ptr(99)`） | 原函数读到的是 0，界面「力尽倒下**0**次」。`before=0`。不能这样改 addParam 参数 | 1.7.42、1.7.23/27 同类 |
| overlay `after=99` 当成功 | 界面仍是 3。成功只看游戏正文 | 全程 |
| 在 `fail_life_pre` 里遍历并调用含 life/die 的方法 | `c0000005`（含递归调用 `getFailConditionText_Life`） | 1.7.43 |
| 在已 hook 的 `get_QuestLife` 里再 `call get_QuestLife` | Recursive hook，进任务列表卡死 | 1.7.44 |
| 改 `get_QuestLife` Byte **返回值**（`to_int64(99)` 或 Lua `99`） | 1.7.46 列表未进 post。1.7.65 `life-get orig=3` 后进任务立刻失败，20s 后 `c0000094` 除零（RDX=0）。禁止改这个返回值 | 1.7.46、1.7.65 |
| 仅在 `in_fail_life>0` 时就地改 `message.get` 返回的 string | hook 装上了（`String layout len=16 chars=20`），**没有** `mutate-in-place`。排版用的 get 不在 fail_life 窗口内，或 String 返回值 `to_managed_object` 失败 | 1.7.50 |
| 在 `fail_life_pre` 里才 `sdk.hook(message.get)` | Lua 打了 `hook via.gui.message.get`，但 HookManager 在 fail_life **返回后** 才真正装上（本局差 17ms）。原函数里的 get 捕不到；之后 UI 也不再 get。零条 `get-hit` | 1.7.51 |
| 只在 `in_fail_life` / `board_open` 时处理 `message.get` | 原生钩子提前 40s 就活着，仍零条 `get-hit`。get 发生在打开列表、fail-life **之前**，被门控丢掉 | 1.7.52 |
| 等游戏自己调用 managed `via.gui.message.get` 来改调查失败文案 | 1.7.53 无门控、钩子已活、每次 get 读 wchar，仍零条 `get-hit`。这条 UI 不走 managed get | 1.7.53 |
| 就地改 `message.get` 返回的 interned string 当文案源 | `mutate-in-place` 后 36s 再 get 仍是 `力尽倒下{0}次`。get 每次从字串表拷贝，改返回值拷贝无效 | 1.7.54 |
| 对 `makeParamData` 返回值直接 `sdk.to_managed_object` | ScriptRunner：`sol_lua_push: … is not a managed object`（1.7.54 第 880 行）。返回值不是托管对象 | 1.7.54 |
| 就地 `write_short` 改 `message.get` 返回的 string | `readback` 仍是 `力尽倒下{0}次`。UTF-16 写入不进 ToString 用的缓冲区 | 1.7.55 |
| 对没有该字段的对象 `set_field("<QuestLife>k__BackingField")` | ScriptRunner：`Attempted to set invalid REManagedObject field`。pcall 也挡不住这条报错 | 1.7.55 |
| 给 `makeParamData` 的 Int32 槽赋 `sdk.create_int32(99)` / 托管对象 | 原函数把对象指针当 int，界面「力尽倒下**-1235256888**次」。`before=-1235256888 wrote=true after=99` | 1.7.58 |
| 给 `makeParamData` 的 Int32 槽赋裸 Lua 数字 `99` | `make-box ok=true after=0`，界面「力尽倒下**0**次」。`before=0 wrote=true after=99`。数字写入槽会变成 0 | 1.7.59 |
| 改 `makeParamData` / `addParam` 的裸 int 参数槽（任意写法） | 托管对象→乱码，数字/`to_int64`/`to_ptr`→0。写不进 99 | 1.7.42、1.7.58、1.7.59 |
| 对 decode=0 / 未确认的对象写 `MaxDeaths@0xA0`（含 fallback `current_quest_information`） | 柜台文案已是 99。接任务进场景 `c0000005`。日志 `MaxDeaths@0xA0 (was 0)` 后 4s 闪退。0 不是次数，写 99 会破坏加载中的对象 | 1.7.60 |
| 对 KeepQuest / ActiveQuestData `call set_QuestLife` | KeepQuest **没有** setter（`life-api` 只有 `get_QuestLife`）。空调用。HUD 仍 3 | 1.7.70 |
| 主脚本再堆 `local`（含 do 块里的）超过 200 | 启动 `too many local variables (limit is 200)`，脚本不加载 | 1.7.71 |
| 进任务后只靠 `on_pre_gui_draw_element` 的 `get_Message`/`get_Text` 字符串改「倒下次数 0/3」 | `_CurFlow=cQuestPlaying` 时仍无 `draw-hud`。这句 HUD 不是这两个 getter 上的字 | 1.7.73 |
| 进任务后靠 `on_pre_gui_draw_element` 认 `cGUIMessageInfo` 或把 `/3` 换成 `/99` | 1.7.74 无 `draw-msginfo`、无 `draw-hud`。这条回调看不到任务内「倒下次数」 | 1.7.74 |
| 对 `cQuestPlaying` 非托管指针 `sdk.to_managed_object` 再当对象读 A0 | 仍是 `28/30/38=raw`，包出来是 nil。`GUI050100QuestDetail` 这局不存在（`gui-m` 空）。`_QuestBeforeStage` nil | 1.7.75 |
| 用 `cQuestPlaying` 基址相对偏移读 0x28/0x30/0x38 当 MaxDeaths | `rel a0=nil t=0 m=0`。不是 CurrentQuestInformation。开任务信息没有 `pstr`（这次只有 `life-get orig=3`） | 1.7.76 |
| `create_instance` 出 `QuestData` 再 `set_field("_QuestData")` | 进任务后 `fill-qd-after life=99`，13ms 后 `c0000005` RIP `143b6eb47` RCX=0。空壳 QuestData 不能赋给调查任务 | 1.7.77 |
| `REField:set_data(nil, 99)` 写 KeepQuest 静态 `QUEST_LIFE` | Lua 的 REField **没有** `set_data`。`static-life 3->3`，`get_QuestLife` 仍是 3，HUD 仍「倒下次数 0/3」。要用 `sdk.set_native_field` | 1.7.78 |
| 写 KeepQuest 静态 `QUEST_LIFE`（含 `set_native_field`） | `lit=true`，编译期常量。getter 不读可变静态。写它没用；TDB 只读会闪 | 1.7.79 |
| 任何方式改 `get_QuestLife` 返回值（含类型门控、`to_ptr(99)`） | 1.7.80 `life-get orig=3 rw=true` 后立刻任务失败，`QuestFailedType=2`（团灭），再 `c0000094`。Lua 钩子返回的 Byte 游戏当 0 用 | 1.7.65、1.7.80 |
| 对 Playing raw 指针 `to_valuetype` Mandrake 当 MaxDeaths | `abs-qinfo 28/30/38 a0=nil t=nil`。不是 CurrentQuestInformation，或 valuetype 看不了这块内存 | 1.7.81 |
| 在 director/Playing/FlowParam/ActiveQuestData 上扫加密 3 | 无加密 3。`scan3 flow none sz=80`，`dir 38=1,40=1`，`active 30=4`。MaxDeaths 不在这些托管对象里 | 1.7.82 |
| 用 `Marshal.ReadInt64` 读 Playing 堆指针上的 MaxDeaths | 类型在，方法不在。`marshal r64=false`，无 `heap-qinfo`。HUD 仍「倒下次数 0/3」 | 1.7.83 |
| Playing 时 `create_instance(System.Byte)` 再 `to_ptr` 当 get_QuestLife 返回值 | 真实上限 99。任务内信息 **0/224**（对象指针低 8 位） | 1.7.87 |
| Playing 时 `return sdk.to_int64(99)` 改 get_QuestLife | 任务内「倒下次数 **0/0**」。`life-i64 orig=3` 随后 `orig=0` | 1.7.88 |
| 对 get_QuestLife 的 Byte retval 做 `to_valuetype` + `set_field("m_value")` | `life-inpl orig=3 after=3`。valuetype 是拷贝，写不回游戏。HUD 仍 0/3。不要再就地改这个 Byte | 1.7.84 |
| 指望 `getKeepQuestText` / fail-life MessageInfo 改任务内「倒下次数」 | 开任务信息只打 `life-get orig=3`，从不调 `getFailConditionText_Life`。`getKeepQuestText` 不是这句 HUD | 1.7.85 |
| 对 hook 的 Byte retval `to_valuetype` 再 `to_ptr(vt)` | `play=true` 但无 `life-vt`。valuetype 写不成 99，没返回新指针。HUD 仍 0/3 | 1.7.86 |
| 对 get_QuestLife 的 Byte 槽 `write_byte` / ffi poke | retval 是 `userdata: 0000000000000003`。`life-poke how=far after=3`。HUD 仍 0/3 | 1.7.89 |
| 指望 `GUI080000` / `_Contexts` / `onOpenApp` 改任务内「倒下次数」 | GUI080000 是装备/猎人信息。开任务信息走 `getKeepQuestText` + `getFailConditionText_TimeLimit`，**不走** `getFailConditionText_Life`。随后 `life-get orig=3`。`_Contexts` 有 311 个池项。0/3 就是 get_QuestLife | 1.7.92 |

Steam / 游戏目录 / 存档：只读。zip 只进 FMM `Mods`。

## 已坐实

- 文案模板：`力尽倒下{0}次`（英文侧同结构）。GUID：`0df6a924-2f62-4443-9dc9-d0641a007beb`
- 生成函数：`app.QuestUtil.getKeepQuestFailConditionText_Life` → `ace.cGUIMessageInfo`；另有 `cActiveQuestData` / `cGUIQuestViewData.getFailConditionText_Life`
- 排版发生在**原函数内部**的 `addParam`。`SKIP_ORIGINAL` → 显示 0，说明 `{0}` 就是这个参数
- 一次 dump：`int32-args 4=3/nil` → 第 4 槽是**裸整数 3**，不是 `Int32.m_value` 指针
- `ParamType=2`（INT），`ParamInt` 事后能写成 99，对已画出来的字没用
- `app.cGUIQuestViewData` 等柜台对象上 `_QuestLife` / `QuestLife` 经常是 **nil**，不能当调查任务的数据源
- `app.cKeepQuestData.get_QuestLife` 返回 **`System.Byte`**。Lua 里 `type(value)=="number"` 会当成没有，所以 board 日志一直是 `QuestLife=nil`，`patch_life_field` 从未写上调查任务的生命次数
- `cActiveQuestData.getQuestLife()` 返回 **0**，不是界面上的 3。3 不从 ActiveQuestData 的这个 getter 来
- 在已 hook 的 `get_QuestLife` 里再 `call get_QuestLife` 会 Recursive hook，进任务列表卡死（1.7.44）
- `cKeepQuestData` 实例字段没有 `_QuestLife` / `<QuestLife>k__BackingField`（1.7.45 dump 到 `_QuestLv` 为止）。`cGUIQuestViewData` 只有 `ActiveQuestData`、`QuestCategory`、`Session`。对字段 `set_field` 改不了调查生命次数
- `addParam` 槽 4 仍是裸整数 **3**。overlay `before=3 wrote=true after=99` 仍是事后改 ParamInt，界面仍是 3
- 进调查列表时 **不会调用** `get_QuestLife`（1.7.46 已 hook 且 post 会打 `orig=`，日志里一行都没有）。改 getter 返回值改不到这句文案
- `SKIP_ORIGINAL` 掉 `makeParamData`/`addParam`（1–30）会在进列表时 `c0000005` 闪退（1.7.48）。1.7.27 只 skip addParam 显示 0，也不再试
- 1.7.50 在 fail_life_pre 里 hook 了 `via.gui.message.get`，布局 `len=16 chars=20`，但进列表期间 **零次** `mutate-in-place`。不能只在 `in_fail_life>0` 时改 get 返回值
- `sdk.hook` 不是同步的。1.7.51 在 fail_life_pre 里调用 hook，fail-life 日志 `21:03:00.366`，HookManager `Adding hook for get` 在 `21:03:00.379`。必须在打开调查列表**之前**就把 get 钩上（游戏循环开始后，不要在脚本加载瞬间，避免 1.7.15 黑屏）
- 1.7.52：原生 `get` 钩子 `21:08:22.570` 已装上，fail-life `21:09:03`，仍零条 `get-hit`。不能用 `in_fail_life`/`board_open` 当门。post 必须对每次 get 做廉价探测（先读 wchar，禁止每次 ToString）
- 1.7.53：钩子 `21:13:22.525` 已活，fail-life `21:14:00`，仍零条 `get-hit`。调查失败文案不经过 managed `via.gui.message.get`。不要再把「等游戏 get」当主路径
- 1.7.54：Lua `get(GUID)` 能拿到 `力尽倒下{0}次` 并打了 `mutate-in-place`，但随后再 get 仍是 `{0}`。字串表才是源。同局 `makeParamData` post 对非托管 retval 调 `to_managed_object` 报错，addParam-post 没跑成
- 1.7.55：`readback` 仍是 `{0}`， interned string 写不进去。`getData` 类型是 `via.gui.MessageAccessData`，没有托管字段日志。`write_quest_life` 对 ViewData/KeepQuest 盲写 `k__BackingField` 会在 ScriptRunner 报 invalid field
- 1.7.56：MessageAccessData.`get_Message()`=`力尽倒下{0}次`，资源 `GameDesign/Text/Mission/Mission.msg`。托管字段 0 个。界面 3 仍是 addParam 填 `{0}`
- 1.7.57：无 `skip-add`。`int32-args 4=3` 后立刻 fail-life。3 在 `makeParamData`，不在 `addParam(Int32)`
- 1.7.58–59：改 `makeParamData` 槽做不到 99（对象指针→乱码，Lua 数字→0）
- 1.7.60：`make-post how=raw type=2 before=3 wrote=true after=99` 柜台文案变成「力尽倒下**99**次」。`this=false`。接任务后 `PlDieCountMax@0xB8 (was 3)` 正常，随后 `MaxDeaths@0xA0 (was 0)`，4s 后 `c0000005`（加载场景）
- 1.7.61：柜台 99、进场景不闪。任务内 HUD「倒下次数 **0/3**」。只写了 `PlDieCountMax@0xB8`。`info=nil`，没写 0xA0。接任务时 `app.user_data.QuestData QuestLife=3`
- 1.7.63：`accept_pre` 因 `managed_arg` 在后面定义而变成全局 nil，接任务钩子报错，QuestLife 没写上
- 1.7.64：无红字。无 `accept-life`（树上没有 QuestLife=1–30）。`skip-a0 no-info`。overlay B8=99，任务内仍「倒下次数 0/3」
- 1.7.65：`life-get orig=3` 并返回 99。进任务立刻失败，随后 `c0000094` 除零
- 1.7.66：进任务不闪。HUD 仍 0/3。`life-get orig=3 keep`。无 `qinfo` 日志（`local info` 挡住了 `info()`）。`skip-a0 no-info`。B8=99 仍不是 HUD
- 1.7.67：`life-this app.cActiveQuestData life=nil`，字段只有 `_MissionType=4,_IsRecommended=0`。`get_QuestLife` 仍返回 3。`qinfo nil`。director+0x38→+0x18 拿不到 CurrentQuestInformation
- 1.7.68：ScriptRunner `line 757 attempt to compare nil with number`（`life_get_logs` 已删，post 还在用）。HUD 仍 0/3。`life-all` 有 `_QuestData:app.user_data.QuestData` 但接任务时实例是 nil。`_KeepQuestData` 无 LIFE 字段。`qinfo nil`。`update()` 一旦 `in_quest` 就不再 `maintain()`，场景加载后的 CurrentQuestInformation / `_QuestData` 不会再写
- 1.7.69：无红字。HUD 仍 0/3。`keep-all` 到 `_QuestLv` 为止，没有 QuestLife。`active-qd nil`。无 `late-qd`。`life-get orig=3`（接任务 + 开任务信息）。`qinfo nil`。Writes=1 仍是 B8。overlay OK 不能当成功。玩家找不到 `late-qd`：那些字在 `re2_framework_log.txt`，不在 ScriptRunner 面板
- 1.7.70：`life-api app.cKeepQuestData` **只有** `get_QuestLife`，没有 setter。`set-life` 是空调用。HUD 仍 0/3。`get_QuestLife=3 qinfo=nil`。无 `late-dir`（B8 写成功后 `raise` 提前 return）
- 1.7.71：启动 ScriptRunner `too many local variables (limit is 200)` 第 3034 行。脚本没加载。主函数 local 不能超过 200
- 1.7.72：能加载。HUD 仍 0/3。`get_QuestLife=3 qinfo=nil`。`late-dir` 打在 `_CurFlow=app.cQuestSceneLoading`（还在加载）。director 字段有 `QuestPlDieCount` Mandrake，**没有** CurrentQuestInformation。无 `draw-hud`（过滤了非 Text 控件）。`remain 3000.0`。无 `late-a0`
- 1.7.73：加载后 dump 在 `app.cQuestPlaying`，`remain≈2999`。仍无 `late-a0` / `draw-hud` / `late-qd`。`die-now nil`。开任务信息只打 `life-get orig=3 keep`，**没有**新的 `make-post`/`fail-life`。任务内「倒下次数 0/3」不走柜台那条 ParamData
- 1.7.74：`late-qd app.cActiveQuestData cat=nil life=nil`（进任务后仍没有 `user_data.QuestData`）。`flow-nest` 在 `cQuestPlaying` 上 `10=cQuestDirector a0=0`、`18=cQuestFlowParam`、`28/30/38=raw`（非托管指针）。无 `draw-hud` / `draw-msginfo`。开任务信息仍 `life-get orig=3 keep`
- 1.7.75：`to_managed_object` 仍包不住 raw。`before-stage nil`。`gui-m` 空。开任务信息有 `fail-life type=1 before=0 wrote=false` 然后 `type=2 after=99`，再 `life-get orig=3`。HUD 仍 0/3
- 1.7.76：`flow-nest 28/30/38:rel a0=nil t=0 m=0`。无 `blob-hit`/`pstr`。开任务信息只 `life-get orig=3 keep`。HUD 仍 0/3。任务内「倒下次数」跟 `get_QuestLife=3` 走，不跟 B8、不跟 fail-life 字符串
- 1.7.77：`static-wrote app.cKeepQuestData QUEST_LIFE`（静态默认就是 3）。随后 `fill-qd` 赋了 `QuestData life=99`，立刻 `c0000005` RCX=0。进任务闪退
- 1.7.82：进任务不闪。HUD 仍 0/3。无 `scan-md`。`scan3 flow none sz=80`；`dir 38=1,40=1`；`param 48=1,60=1`；`active 30=4`。面板 `abs=active 30=4`
- 1.7.83：进任务不闪。HUD 仍 0/3。`marshal r64=false`。无 `heap-qinfo`。面板仍 `FlowParam 99; hunt HUD not updated`，`get_QuestLife=3`
- 1.7.84：进任务不闪。HUD 仍 0/3。`life-inpl orig=3 after=3`。`getKeepQuestText` 等 MessageInfo 方法当时没进 fail-life 窗口。`make-post before=35` 把非倒下参数也写成了 99
- 1.7.85：进任务不闪。HUD 仍 0/3。`fail-fn getKeepQuestText`。开任务信息只有 `life-get orig=3`。无 `gui-types`（名字写成了 GUI50000）
- 1.7.86：进任务不闪。HUD 仍 0/3。`life-get orig=3 play=true`，无 `life-vt`。`gui-types` 有 `app.GUI050100`
- 1.7.87：`life-mk how=ci-true after=99`。真实上限 99（倒下后还剩 98）。任务内信息 **0/224**。列表 99。`GUI050100` 有 `get__QuestDetail`
- 1.7.88：任务内「倒下次数 0/0」。`life-i64 orig=3` 然后 `orig=0`。面板 `get_QuestLife=0 ret=99`
- 1.7.89：任务内「倒下次数 0/3」。`life-poke how=far orig=3 after=3 ud=userdata: 0000000000000003`。面板 `poke=3`。B8 仍 99
- 1.7.90：任务内仍 0/3。`hook GUI050100` 已装，开任务信息无 `detail`，只有 `life-get orig=3 play=true`
- 1.7.91：任务内仍 0/3。`gui-types` 含 GUI080000。`hook onOpenApp n=11` 无 `gui-open`。`gui-mgr` 有 `_Contexts:app.cGUIContext[]`，没把数组项打出来
- 1.7.92：任务内仍 0/3。`hunt-fn` 只有 KeepQuestText / TimeLimit，没有 Life。`g80 GUI080001.setDisableOpenSkillInfo`。`gui-ctx ctx#311`
- 1.7.93：**通过**。Playing 时 `sdk.to_ptr(99)`（指针位=99，与 `userdata: …0003` 同编码）。任务内「倒下次数 0/99」。加载期不改返回值。列表 99、B8=99 仍在

## 版本失败摘要

| 版本 | 做了什么 | 玩家看到 | 教训 |
| --- | --- | --- | --- |
| 1.7.20 | 加载时扫 ParamData methods | 进柜台崩溃 | 禁止扫该类 methods |
| 1.7.21–22 | 事后写 ParamValue | 仍是 3 | 改晚了 |
| 1.7.23 | union 指针写成 99 | 显示 0 | 只能写 union 里的 int 字段 |
| 1.7.24–26 | 写 ParamInt；Format | 仍是 3 | Format 不是这条 UI |
| 1.7.27 | skip addParam | 显示 0 | 参数确实驱动 `{0}`，但 skip 后没补上 99 |
| 1.7.28–31 | 事后改 MessageInfo；抓 GUID | 仍是 3 | 确认了模板和 GUID，没改到排版时机 |
| 1.7.32–34 | `set_MessageId`、模板 `{0}`→99 | 仍是 3 | 模板在 get() 里，不能换返回值 |
| 1.7.35–37 | 写 Msg 字段 | overlay `rewrote msg`，界面 3 | Msg 字段不是柜台用的 |
| 1.7.38 | get() 返回新 string | 进柜台 `c0000005`，RIP 紧跟 `get-msg 力尽倒下99次` | **禁止换 get() 返回值** |
| 1.7.39 | addParam 进函数前 `args[i]=to_int64(99)` | 不崩；`add=357 rewrote=0`；dump 仍 `4=3/nil`；界面 3 | 读得到槽位 4=3，**赋值没成功**（没进 rewrote）。不要再只「事后写 Param」 |
| 1.7.40 | fail_life_pre 写对象 Life 字段 | 无 `pre-life`；ViewData 顶层没有 Life 字段 | 要跟进嵌套对象，不要猜 setter |
| 1.7.41 | 对 addParam 指针槽 `to_managed_object` | `rewrote=0`，循环在槽 4 之前断了；界面 3 | 不要对非整数槽做 managed 转换 |
| 1.7.42 | 只改 addParam 槽 4 为 `to_int64(99)` | 界面「力尽倒下**0**次」。`addParam 99` 后立刻 `before=0` | **禁止再写 addParam 参数槽** |
| 1.7.43 | 撤掉 addParam 槽改写；对 ActiveQuestData 调用所有 life/die 方法 | 界面回到 **3**。`getQuestLife=0`。调用方法时 `c0000005` | 禁止在 fail_life_pre 里乱调方法。调查生命次数是 KeepQuest 的 Byte |
| 1.7.44 | Byte 解读 QuestLife；`patch_life_field` / board 日志里 `call get_QuestLife` | 进任务列表卡死。`cGUIQuestViewData QuestLife=99` 随后 `Recursive hook detected for 'app.cKeepQuestData.get_QuestLife'` | **禁止在 get_QuestLife 的 hook 里再调用 get_QuestLife**。读只用字段，包括 `<QuestLife>k__BackingField` |
| 1.7.45 | 去掉递归 get；只写字段 + `set_QuestLife` | 列表不卡了。界面仍 3。`keep` 无 QuestLife 字段 | 字段写不上调查生命次数 |
| 1.7.47 | SKIP `addParam(3)` + fail_life_post `addParam(99)` | 界面仍「力尽倒下**3**次」。无 `skip addParam`。有 `post-addParam true`、`n=2/3 before=99`。dump 仍 `4=3/nil` | dump 来自 `makeParamData`，SKIP 没挂上。事后 `addParam(99)` 改不到已排版的字 |
| 1.7.50 | fail_life_pre 才 hook get，就地改 interned UTF-16 | 界面仍「力尽倒下**3**次」。有 `hook via.gui.message.get`、`String layout len=16 chars=20`，无 `mutate-in-place` | get 不在 `in_fail_life` 窗口里被调用（或 String retval 转不成对象）。下一步：列表打开后一段时间都改 matching 文案，并打 `get-hit` |
| 1.7.51 | board_open 窗口内也 mutate；打 get-hit | 界面仍「力尽倒下**3**次」。Lua hook 日志在 `.362`，fail-life `.366`，**原生** hook `.379`。零条 `get-hit` / `mutate-in-place` | 不能在 fail_life_pre 里才 hook。原生安装晚于原函数。列表画出来之后也不再调用 get |
| 1.7.52 | 游戏循环 frame≥120 再 hook get | 界面仍「力尽倒下**3**次」。Hook 263/265 在 `21:08:22.570` 已活着，fail-life `21:09:03`，零条 `get-hit` | get 不在 fail_life 窗口内。门控 `in_fail_life`/`board_open` 会把列表打开时的 get 丢掉 |
| 1.7.53 | 每次 get 读 wchar，匹配「力尽」再 mutate | 界面仍「力尽倒下**3**次」。钩子已活，零条 `get-hit` / `mutate-in-place` | 游戏不会对这句调用 managed get。下一步：自己 get(GUID) 改 interned 模板；在 addParam 的 post 里改 Param（原函数还没返回） |
| 1.7.54 | Lua get(GUID) 就地改 interned；addParam post 改 Param | 界面仍 3。`pulled[1/2]` 仍是 `{0}`。ScriptRunner：`make_post` `to_managed_object` 不是托管对象 | get 返回的是拷贝。必须改 `getData` 字串表。`to_managed_object` 必须 pcall |

| 1.7.55 | getData + 修 to_managed_object；readback 验证 mutate | 界面仍 3。`readback` 仍 `{0}`。`getData type=via.gui.MessageAccessData` 无字段。ScriptRunner：invalid field `<QuestLife>k__BackingField` | 不要写 interned get() string。不要对不存在的字段 set_field。下一步：dump MessageAccessData 的 methods / getParamString |
| 1.7.56 | 只写能 get 到的字段；dump MessageAccessData methods | 无 ScriptRunner 红字。界面仍「力尽倒下**3**次」。`get_Message=力尽倒下{0}次`，`get_Name=Mission_Quest3001`，`get_AssetPath=GameDesign/Text/Mission/Mission.msg` | 模板在 Mission.msg。显示仍靠 addParam 的 3。下一步：fail_life 里 skip `addParam(3)` 并立刻 `addParam(99)`（1.7.27 只 skip 会显示 0） |

| 1.7.57 | fail_life 里 skip `addParam(Int32)` 的 3 并 call 99 | 不闪退。界面仍 3。无 `skip-add`。仍有 `int32-args 4=3` 然后 fail-life | 3 不走 `addParam(Int32)`。dump 是 `makeParamData`。不要再只 skip addParam(Int32) |
| 1.7.58 | `makeParamData` 槽写成 `create_int32(99)` | 界面「力尽倒下**-1235256888**次」。`FailLife before=-1235256888 wrote=true after=99` | 槽是裸 int，不是装箱对象。禁止把托管对象写进 Int32 槽。不要 skip makeParamData。不要 `to_int64`/`to_ptr` |
| 1.7.59 | `makeParamData` 槽写成裸数字 `99` | 界面「力尽倒下**0**次」。`make-box slot=4 ok=true after=0`。`before=0 wrote=true after=99` | 禁止再改 makeParamData/addParam 的裸 int 槽。下一步改返回的 ParamData（native_field / valuetype），不要改槽 |
| 1.7.60 | `make_post` 用 native_field 改返回的 ParamData | **柜台文案成功「力尽倒下99次」**。接任务进场景闪退。`make-post how=raw before=3 after=99`。进场景 `MaxDeaths@0xA0 (was 0)` 后 `c0000005` RIP `14a49d96a` | 文案这条留下。禁止对 0 / 未确认对象写 0xA0。不要 `set_field(create_int32)` 覆盖 ParamValue |
| 1.7.61 | 保留 make_post；0xA0 只在 1–30 时写 | 柜台 99，进场景不闪。任务内「倒下次数 **0/3**」。`PlDieCountMax@0xB8 (was 3)` 后 overlay OK。`info=nil`。`QuestData QuestLife=3` | overlay 的 B8=99 不是任务内 HUD。3 在接任务时拷进实战 QuestData。要在 accept **之前**改 QuestLife |
| 1.7.63 | accept 参数树写 QuestLife | 进任务仍「倒下次数 **0/3**」。ScriptRunner：`global 'managed_arg' is not callable`（第 614 行）。无 `accept-life`。`skip-a0 no-info` | `managed_arg` 定义在 `accept_pre` 后面，Lua 当全局 nil。接任务钩子没跑成 |
| 1.7.64 | 修好 managed_arg，accept 扫 QuestLife | 无红字。进任务仍「倒下次数 **0/3**」。无 `accept-life`。`skip-a0 no-info`。Writes=1 只是 B8 | accept 参数上读不到 QuestLife。任务内 HUD 不读 B8 |
| 1.7.65 | `get_QuestLife` post 把 3 改成 99 | 一进任务就失败，随后闪退。`life-get orig=3`。`c0000094` 除零 RDX=0 | **禁止改 get_QuestLife / getQuestLife 返回值** |
| 1.7.66 | 撤返回值改写；A0 仅 1–30 | 进任务不闪。HUD 仍「倒下次数 **0/3**」。`life-get orig=3 keep`。无 `qinfo`。`skip-a0 no-info` | `local info = ...` 把日志函数挡住了。B8 不是 HUD。`get_QuestLife` 仍返回 3 |
| 1.7.67 | life-this dump；A0 仅 1–30 | 进任务不闪。HUD 仍 0/3。`life-this app.cActiveQuestData life=nil`。`life-fields _MissionType=4,_IsRecommended=0`。`qinfo nil`。`life-get orig=3 keep` | 3 不是 ActiveQuestData 的字段。`get_QuestLife` 从嵌套对象算出来。不要改返回值。qinfo 指针链是空的 |
| 1.7.68 | 子对象 dump + director 扫 A0 | 红字 `757: compare nil with number`。HUD 仍 0/3。`life-all` 含 `_QuestData` 但接任务时 nil。`_KeepQuestData` 无 LIFE。`qinfo nil`。无 `life-child-wrote` | `life_get_logs` 删了 post 还在比。`update()` 进任务后不再 `maintain()`，加载后的 MaxDeaths 找不到 |
| 1.7.69 | 进任务后继续 maintain；修 post | 无红字。HUD 仍 0/3。`keep-all` 无 QuestLife。`active-qd nil`。无 `late-qd`。`life-get orig=3`。B8=99 | 调查次数是 KeepQuest.get_QuestLife **算出来的 3**，没有字段。B8 不是 HUD。不要让玩家去翻日志文件 |
| 1.7.70 | `set_QuestLife(99)` | HUD 仍 0/3。`life-api keep=get_QuestLife`（无 setter）。`get_QuestLife=3 qinfo=nil`。无 `late-dir` | **没有 set_QuestLife**。B8 成功后提前 return，director 指针 dump 没跑。开任务信息会调 `get_QuestLife` |
| 1.7.71 | A0 blob + HUD set_Message | 启动报错，脚本未加载。`3034: too many local variables (limit is 200)` | 主函数 local 上限 200。hook 安装段的 local 必须放进子函数 |
| 1.7.72 | 安装段放进 install() | 能加载。HUD 仍 0/3。`late-dir` 在 SceneLoading 时打完就不再 dump。无 `draw-hud`。director 无 CurrentQuestInformation | 要等加载结束再 dump。HUD 不是 via.gui.Text。不要只 dump 一次加载中的 director |
| 1.7.73 | 等非 Loading 再 dump；GUI 不限 Text | 能加载。HUD 仍 0/3。`flow-type app.cQuestPlaying`。无 `draw-hud`。开任务信息 `life-get orig=3`，无新 fail-life | overlay B8=99 仍不是 HUD。这句不是 Message/Text 字符串。进任务后 `_QuestData` 仍无 `_QuestLife` 可写 |
| 1.7.74 | late-qd + flow-nest；draw 认 MessageInfo、改 `/3` | 能加载。HUD 仍 0/3。`cat=nil`。`28/30/38=raw`。无 draw 命中 | 调查任务没有 catalog QuestData。任务内 HUD 不走 draw 回调。下一步：把 raw 指针当原生结构读 A0（仅 1–30 才写） |
| 1.7.75 | raw 指针 to_managed_object；dump GUI050100 | 能加载。HUD 仍 0/3。仍 `28/30/38=raw`。`gui-m` 空。开任务信息 `fail-life type=1` | 不要再 wrap 这些指针。用基址相对偏移读。type=1 可能是「倒下次数」字符串，要打 `pstr` |
| 1.7.76 | Playing 相对读 A0；ParamString 改 `0/3` | 能加载。HUD 仍 0/3。`rel a0=nil t=0`。无 `pstr`。开任务信息只有 `life-get orig=3` | 那些偏移不是 MaxDeaths。任务内 HUD 读的是 `get_QuestLife` 算出来的 3。下一步：静态字段 / 给空的 `_QuestData` 补上带 `_QuestLife=99` 的实例 |
| 1.7.77 | 写静态 QUEST_LIFE；create_instance 赋 `_QuestData` | 进任务闪退。`fill-qd-after life=99` 后 `c0000005` | **禁止伪造 QuestData 赋给调查任务**。KeepQuest 静态 `QUEST_LIFE=3` 才是默认次数。下一步只写这个静态，不要 create_instance |
| 1.7.82 | 托管对象扫加密 3 + 计时器 | 能进任务。HUD 仍 0/3。无 scan-md。Playing 只有 0x80 字节 | MaxDeaths 不在这些对象上。Playing+28/30/38 是堆指针。下一步用 Marshal 读堆上 A0 |
| 1.7.83 | Marshal.ReadInt64 读堆上 A0 | 能进任务。HUD 仍 0/3。`r64=false` | 这局 TDB 没有 ReadInt64。不要再依赖 Marshal。任务内「倒下次数」仍跟 `get_QuestLife=3` 走 |
| 1.7.87 | create_instance Byte + to_ptr | 上限真的是 99。任务内信息 0/**224**。列表 99 | 禁止返回 Byte 对象指针。HUD 把指针低 8 位当次数 |
| 1.7.88 | Playing 时 return to_int64(99) | 任务内 0/**0**。真实上限仍 99 | 禁止 to_int64 当 Byte 返回值。外层读到 0 |
| 1.7.89 | 对 Byte retval poke/write_byte | 任务内 0/**3**。`ud=userdata: …0003` | 返回值就是整数 3 的 lightuserdata，没有槽可写。不要再 poke |
| 1.7.90 | hook GUI050100 详情 | 任务内仍 0/3。无 `detail` 日志 | 任务内「任务信息」不是 GUI050100 |
| 1.7.91 | 扫 GUI ID + hook onOpenApp | 任务内仍 0/3。无 `gui-open`。`_Contexts` 没展开 | 不要只 hook onOpenApp |
| 1.7.92 | dump _Contexts + hook GUI080000 | 任务内仍 0/3。开信息只有 TimeLimit + get_QuestLife=3 | GUI080000 不是任务信息。0/3 直接来自 get_QuestLife |
| 1.7.93 | Playing 时 return to_ptr(99)，且指针位必须是 99 | **任务内 0/99**。列表 99。真实上限 99 | 这是 get_QuestLife Byte 的正确编码。加载/接任务时仍返回原值，否则会团灭（1.7.80） |

## 已完成（1.7.93）

调查任务：列表「力尽倒下99次」、任务内「倒下次数 0/99」、真实团灭上限 99（B8）。Playing 时 `get_QuestLife` 只返回指针位为 99 的 `to_ptr(99)`；加载期不改返回值。

