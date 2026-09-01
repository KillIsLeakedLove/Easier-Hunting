---@diagnostic disable: undefined-global

-- Goal: quest faint/cart cap = 99 (UI + wipe check + faint message).
-- Runtime cap: app.cQuestFlowParam.PlDieCountMax (Mandrake @ 0xB8).
-- Investigation HUD also uses encrypted MaxDeaths @ 0xA0 (HunterPie CurrentQuestInformation).
-- UI field: QuestData._QuestLife (wrapper + nested copies).
-- Investigation list is save/generated data, not PAK QuestData — walk SaveDataManager
-- and hook get_QuestLife on types discovered from that walk.
-- Pre-accept quest board reads catalog _QuestLife, not the live QuestDirector.
-- Do not hook getQuestLife retval (divide-by-zero). Pre-hook get_QuestLife only.
-- Keep-quest fail text is ace.cGUIMessageInfo (MsgID + Params/ParamData).
-- Patch ParamData.ParamValue by field write only. Do not iterate ParamData methods
-- (that AV'd at load). Do not replace via.gui.message.get's return pointer (1.7.38).
-- 1.7.93: Playing-only return to_ptr(99) if pointer bits are 99 (same encoding as userdata 0x3).
-- 1.7.92: GUI080000 is equipment UI; in-hunt 0/3 is get_QuestLife after TimeLimit text.
-- Failure log: QUEST_LIFE_LESSONS.md — do not repeat banned approaches.
-- Never call get_QuestLife from Lua (it is hooked; 1.7.44 Recursive hook froze the quest list).

local sdk = sdk
local re = re
local imgui = imgui
local reframework = reframework
local log = log

local MOD_NAME = "Easier Hunting: Quest Life"
local SCRIPT_VERSION = "1.7.93"
local TARGET = 99
local FAINT_LIFE_GUID = "0df6a924-2f62-4443-9dc9-d0641a007beb"
local IDLE_INTERVAL = 60
local PL_DIE_COUNT_MAX_OFF = 0xB8
local MAX_DEATHS_OFF = 0xA0
local NORMAL_CAP_MIN = 1
local NORMAL_CAP_MAX = 30

local PARAM_FIELD_NAMES = {
    "<Param>k__BackingField",
    "Param",
    "_Param",
    "FlowParam",
    "_FlowParam",
    "_QuestFlowParam",
    "_CurFlow",
    "_QuestInfo",
    "QuestInfo",
    "_Info",
    "Info",
    "_CurrentInfo",
    "CurrentInfo",
}

local PARAM_GETTERS = {
    "get_Param()",
    "get_Param",
    "get_FlowParam()",
    "get_FlowParam",
    "get_QuestInfo()",
    "get_QuestInfo",
}
local LIFE_FIELD_NAMES = {
    "_QuestLife",
    "QuestLife",
    "questLife",
    "<QuestLife>k__BackingField",
}
local MANDRAKE_NAMES = {
    "PlDieCountMax",
    "_PlDieCountMax",
    "<PlDieCountMax>k__BackingField",
    "MaxDeaths",
    "_MaxDeaths",
    "<MaxDeaths>k__BackingField",
}

local state = {
    frame = 0,
    status = "Waiting for quest.",
    detail = "",
    writes = 0,
    catalog_writes = 0,
    in_quest = false,
    ui_life = nil,
    max_deaths = nil,
    deaths = nil,
    last_path = "",
    hunt_diag = "",
    logged_types = {},
    board_types = "",
    info_max_deaths = nil,
    fail_life_diag = "not called",
    fmt_add = 0,
    fmt_pts = 0,
    fmt_rewrote = 0,
    fmt_sig = "",
    fmt_str = 0,
    fmt_dump = "",
    fail_life_frame = 0,
    msg_ids = {},
    msg_id_dump = "",
}

local function info(msg)
    if log ~= nil and log.info ~= nil then
        log.info("[Easier Hunting] " .. msg)
    end
end

local function set_status(status, detail)
    detail = detail or ""
    if state.status == status and state.detail == detail then
        return
    end
    state.status = status
    state.detail = detail
    info(status .. (detail ~= "" and (" " .. detail) or ""))
end

local function try_get_field(object, name)
    local ok, value = pcall(function()
        return object:get_field(name)
    end)
    if not ok then
        return nil
    end
    return value
end

local function try_set_field(object, name, value)
    return pcall(function()
        object:set_field(name, value)
    end)
end

local function try_call(object, method_name, ...)
    if object == nil then
        return nil
    end
    local args = { ... }
    local ok, value = pcall(function()
        return object:call(method_name, table.unpack(args))
    end)
    if not ok then
        return nil
    end
    return value
end

local mission_api_ready = false
local m_get_qd
local m_get_playing
local m_get_active

local function call_method(method, instance)
    if method == nil or instance == nil then
        return nil
    end
    local ok, value = pcall(method.call, method, instance)
    if not ok then
        return nil
    end
    return value
end

local function ensure_mission_api()
    if mission_api_ready then
        return
    end
    local typedef = sdk.find_type_definition("app.MissionManager")
    if typedef == nil then
        return
    end
    m_get_qd = typedef:get_method("get_QuestDirector()")
    m_get_playing = typedef:get_method("get_IsPlayingQuest()")
    m_get_active = typedef:get_method("get_IsActiveQuest()")
    mission_api_ready = true
end

local function flag_true(value)
    return value == true or value == 1
end

local function flag_false(value)
    return value == false or value == 0
end

local function is_normal_cart_cap(value)
    return type(value) == "number" and value >= NORMAL_CAP_MIN and value <= NORMAL_CAP_MAX
end

local function object_id(object)
    if object == nil then
        return nil
    end
    local ok, addr = pcall(function()
        return object:get_address()
    end)
    if ok and addr ~= nil then
        return addr
    end
    return tostring(object)
end

local function read_qword(object, offset)
    local ok, value = pcall(function()
        return object:read_qword(offset)
    end)
    if ok and type(value) == "number" then
        return value
    end
    return nil
end

local function write_qword(object, offset, value)
    return pcall(function()
        object:write_qword(offset, value)
    end)
end

local function read_float(object, offset)
    local ok, value = pcall(function()
        return object:read_float(offset)
    end)
    if ok and type(value) == "number" then
        return value
    end
    return nil
end

-- CurrentQuestInformation: Timer@0xB8 / MaxTimer@0xBC are floats (ms).
local function quest_timer_at(object, timer_off)
    if object == nil then
        return false
    end
    local t = read_float(object, timer_off)
    local m = read_float(object, timer_off + 4)
    if type(t) ~= "number" or type(m) ~= "number" then
        return false
    end
    if t ~= t or m ~= m then
        return false
    end
    return (m >= 30000 and m <= 3.0e7 and t >= 0 and t <= m + 10000)
        or (m >= 180 and m <= 7200 and t >= 0 and t <= m + 5)
end

local function decode_mandrake(enc)
    if enc == nil then
        return nil
    end
    if type(enc) == "number" then
        return enc
    end
    local value = try_get_field(enc, "_Value")
        or try_get_field(enc, "Value")
        or try_get_field(enc, "<Value>k__BackingField")
    local divisor = try_get_field(enc, "_Divisor")
        or try_get_field(enc, "Divisor")
        or try_get_field(enc, "<Divisor>k__BackingField")
    if type(value) == "number" and type(divisor) == "number" and divisor ~= 0 then
        return math.floor(value / divisor)
    end
    return nil
end

local function write_mandrake(enc, target)
    if enc == nil or type(enc) == "number" then
        return false
    end
    local divisor = try_get_field(enc, "_Divisor")
        or try_get_field(enc, "Divisor")
        or try_get_field(enc, "<Divisor>k__BackingField")
    if type(divisor) ~= "number" or divisor == 0 then
        divisor = 1
    end
    local packed = target * divisor
    if try_set_field(enc, "_Value", packed)
        or try_set_field(enc, "Value", packed)
        or try_set_field(enc, "<Value>k__BackingField", packed)
    then
        return decode_mandrake(enc) == target
    end
    return false
end

local function decode_at(object, offset)
    local value = read_qword(object, offset)
    local divisor = read_qword(object, offset + 8)
    if value == nil or divisor == nil or divisor == 0 then
        return nil, nil
    end
    return math.floor(value / divisor), divisor
end

-- CurrentQuestInformation: MaxDeaths@A0 is 1-30. FlowParam stores PlDieCountMax at B8.
local function is_max_deaths_blob(object)
    local a0 = decode_at(object, MAX_DEATHS_OFF)
    if not is_normal_cart_cap(a0) then
        return false
    end
    local b8 = decode_at(object, PL_DIE_COUNT_MAX_OFF)
    if is_normal_cart_cap(b8) or b8 == TARGET then
        return false
    end
    return true
end

local function follow_ptr(object, offset)
    if object == nil then
        return nil
    end
    local ptr = read_qword(object, offset)
    if ptr == nil or ptr == 0 then
        return nil
    end
    local ok, obj = pcall(sdk.to_managed_object, ptr)
    if ok and obj ~= nil then
        local valid = true
        if sdk.is_managed_object ~= nil then
            valid = sdk.is_managed_object(obj)
        end
        if valid then
            return obj
        end
    end
    return nil
end

local function type_name(object)
    local name = nil
    pcall(function()
        name = object:get_type_definition():get_full_name()
    end)
    return name
end

local function is_index_list(object)
    local name = type_name(object)
    if name == nil then
        return false
    end
    local lower = name:lower()
    if lower:find("dictionary", 1, true) or lower:find("hashset", 1, true) then
        return false
    end
    return lower:find("list`", 1, true)
        or lower:find("ilist", 1, true)
        or lower:find("array", 1, true)
        or lower:find("[]", 1, true)
end

local function get_mission_manager()
    return sdk.get_managed_singleton("app.MissionManager")
end

local function live_director()
    local mission = get_mission_manager()
    if mission == nil then
        return nil
    end
    return follow_ptr(mission, 0x178)
        or follow_ptr(mission, 0x168)
        or follow_ptr(mission, 0x158)
end

local function get_quest_director()
    local mission = get_mission_manager()
    if mission == nil then
        return nil
    end
    ensure_mission_api()
    return call_method(m_get_qd, mission)
        or try_get_field(mission, "QuestDirector")
        or try_get_field(mission, "_QuestDirector")
        or try_call(mission, "get_QuestDirector()")
        or try_call(mission, "get_QuestDirector")
end

local function add_unique(list, seen, object)
    if object == nil then
        return
    end
    local id = object_id(object)
    if id ~= nil and seen[id] then
        return
    end
    if id ~= nil then
        seen[id] = true
    end
    list[#list + 1] = object
end

local function collect_quest_data(qd)
    local list = {}
    local seen = {}
    local active = try_get_field(qd, "_QuestData")
        or try_get_field(qd, "QuestData")
        or try_call(qd, "get_QuestData()")
        or try_call(qd, "get_QuestData")
        or try_call(qd, "get_ActiveQuestData()")
        or try_get_field(qd, "_ActiveQuestData")
    add_unique(list, seen, active)
    if active ~= nil then
        add_unique(list, seen, try_get_field(active, "_QuestData"))
        add_unique(list, seen, try_get_field(active, "QuestData"))
        add_unique(list, seen, try_get_field(active, "_DataList"))
        add_unique(list, seen, try_get_field(active, "_Data"))
    end
    local typedef = nil
    pcall(function()
        typedef = qd:get_type_definition()
    end)
    local fields = nil
    if typedef ~= nil then
        pcall(function()
            fields = typedef:get_fields()
        end)
    end
    if fields ~= nil then
        for _, field in ipairs(fields) do
            local fname = nil
            pcall(function()
                if not field:is_static() then
                    fname = field:get_name()
                end
            end)
            if fname ~= nil then
                local lower = fname:lower()
                if lower:find("quest", 1, true)
                    or lower:find("investig", 1, true)
                    or lower:find("exquest", 1, true)
                    or lower:find("event", 1, true)
                    or lower:find("arena", 1, true)
                    or lower:find("mission", 1, true)
                    or lower:find("flow", 1, true)
                then
                    add_unique(list, seen, try_get_field(qd, fname))
                end
            end
        end
    end
    return list
end

local function life_num(v)
    if type(v) == "number" then
        local n = math.floor(v)
        if n >= 0 and n <= 255 then
            return n
        end
        return nil
    end
    if v == nil then
        return nil
    end
    local n = nil
    pcall(function()
        n = sdk.to_int64(v)
    end)
    if type(n) ~= "number" then
        n = tonumber(tostring(v))
    end
    if type(n) == "number" and n >= 0 and n <= 255 then
        return math.floor(n)
    end
    return nil
end

local function read_quest_life(data)
    for _, name in ipairs(LIFE_FIELD_NAMES) do
        local n = life_num(try_get_field(data, name))
        if n ~= nil then
            return n
        end
    end
    return nil
end

local function write_quest_life(data, target)
    for _, name in ipairs(LIFE_FIELD_NAMES) do
        if life_num(try_get_field(data, name)) ~= nil then
            try_set_field(data, name, target)
        end
    end
    try_call(data, "set_QuestLife", target)
    return read_quest_life(data) == target
end

-- KeepQuest/Active have no QuestLife field (1.7.69 keep-all). Setter may still store.
-- Never call get_QuestLife here (1.7.44 recursive hook).
local set_life_logs = 0
local function apply_set_life(obj)
    if obj == nil or type(obj) ~= "userdata" then
        return false
    end
    local tn = type_name(obj)
    if tn ~= "app.cKeepQuestData" and tn ~= "app.cActiveQuestData" and tn ~= "app.user_data.QuestData" then
        return false
    end
    pcall(function()
        obj:call("set_QuestLife", TARGET)
    end)
    pcall(function()
        obj:call("set_QuestLife(System.Byte)", TARGET)
    end)
    if is_normal_cart_cap(read_quest_life(obj)) then
        pcall(write_quest_life, obj, TARGET)
    end
    if set_life_logs < 6 then
        set_life_logs = set_life_logs + 1
        info("set-life " .. tostring(tn))
    end
    return true
end

-- Patch catalog life when the board reads a quest. Do not scan managers every frame.
local function patch_life_field(obj)
    if obj == nil then
        return false
    end
    local life = nil
    for _, name in ipairs(LIFE_FIELD_NAMES) do
        local n = life_num(try_get_field(obj, name))
        if n ~= nil then
            life = n
            break
        end
    end
    if life == nil then
        return false
    end
    if life == TARGET then
        return true
    end
    if is_normal_cart_cap(life) then
        for _, name in ipairs(LIFE_FIELD_NAMES) do
            if life_num(try_get_field(obj, name)) ~= nil then
                try_set_field(obj, name, TARGET)
            end
        end
        for _, name in ipairs(LIFE_FIELD_NAMES) do
            if life_num(try_get_field(obj, name)) == TARGET then
                state.catalog_writes = state.catalog_writes + 1
                return true
            end
        end
    end
    local nested = try_get_field(obj, "_DataList")
        or try_get_field(obj, "_QuestData")
        or try_get_field(obj, "_Data")
        or try_get_field(obj, "<ActiveQuestData>k__BackingField")
        or try_get_field(obj, "ActiveQuestData")
        or try_get_field(obj, "<KeepQuestData>k__BackingField")
        or try_get_field(obj, "KeepQuestData")
    if nested ~= nil and nested ~= obj then
        return patch_life_field(nested)
    end
    return false
end

local function managed_arg(arg)
    if arg == nil then
        return nil
    end
    local ok, obj = pcall(sdk.to_managed_object, arg)
    return ok and obj or nil
end

local accept_logs = 0
local a0_skip_logs = 0
local qinfo_logs = 0
local function patch_quest_life_tree(obj, depth, seen)
    depth = depth or 0
    seen = seen or {}
    if obj == nil or type(obj) ~= "userdata" or depth > 4 then
        return
    end
    local id = object_id(obj)
    if id ~= nil then
        if seen[id] then
            return
        end
        seen[id] = true
    end
    apply_set_life(obj)
    local before = read_quest_life(obj)
    if is_normal_cart_cap(before) then
        pcall(write_quest_life, obj, TARGET)
        pcall(patch_life_field, obj)
        if accept_logs < 8 then
            accept_logs = accept_logs + 1
            info("accept-life " .. tostring(type_name(obj)) .. " " .. tostring(before) .. "->" .. tostring(read_quest_life(obj)))
        end
    end
    if is_index_list(obj) then
        local count = try_call(obj, "get_Count()") or try_call(obj, "get_Count")
        if type(count) == "number" and count > 0 and count <= 24 then
            for i = 0, count - 1 do
                patch_quest_life_tree(
                    try_call(obj, "get_Item", i) or try_call(obj, "get_Item(System.Int32)", i),
                    depth + 1,
                    seen
                )
            end
        end
        return
    end
    local tn = type_name(obj)
    local lower = tn and tn:lower() or ""
    local dive = depth < 2
        or lower:find("quest", 1, true)
        or lower:find("mission", 1, true)
        or lower:find("param", 1, true)
        or lower:find("keep", 1, true)
        or lower:find("event", 1, true)
        or lower:find("arena", 1, true)
        or lower:find("flow", 1, true)
    if not dive then
        return
    end
    local td = nil
    pcall(function()
        td = obj:get_type_definition()
    end)
    local fields = nil
    if td ~= nil then
        pcall(function()
            fields = td:get_fields()
        end)
    end
    if fields == nil then
        return
    end
    for _, field in ipairs(fields) do
        local fname = nil
        pcall(function()
            if not field:is_static() then
                fname = field:get_name()
            end
        end)
        if fname ~= nil then
            local child = try_get_field(obj, fname)
            if type(child) == "userdata" then
                patch_quest_life_tree(child, depth + 1, seen)
            end
        end
    end
end

local function accept_live()
    local qd = nil
    pcall(function()
        qd = live_director()
        if qd == nil then
            qd = get_quest_director()
        end
    end)
    if qd ~= nil then
        patch_quest_life_tree(qd, 0, {})
    end
end

local static_life_logs = 0
local function write_keep_quest_life()
    if state.static_life == TARGET then
        return
    end
    local td = sdk.find_type_definition("app.cKeepQuestData")
    if td == nil then
        info("static-life no-td")
        return
    end
    local field = td:get_field("QUEST_LIFE")
    if field == nil then
        info("static-life no-field")
        return
    end
    local lit = false
    pcall(function()
        lit = field:is_literal()
    end)
    local before = life_num(field:get_data(nil))
    local ok = false
    if not lit then
        ok = pcall(function()
            sdk.set_native_field(nil, td, "QUEST_LIFE", TARGET)
        end)
    end
    local after = life_num(field:get_data(nil))
    state.static_life = after
    state.static_lit = lit
    if static_life_logs < 3 then
        static_life_logs = static_life_logs + 1
        info(
            "static-life lit="
                .. tostring(lit)
                .. " "
                .. tostring(before)
                .. "->"
                .. tostring(after)
                .. " ok="
                .. tostring(ok)
        )
    end
end

local accept_frame = 0
local function accept_pre(args)
    accept_frame = state.frame
    if accept_logs < 1 then
        info("accept-pre")
        accept_logs = accept_logs + 1
    end
    local seen = {}
    for i = 2, 8 do
        patch_quest_life_tree(managed_arg(args[i]), 0, seen)
    end
    pcall(accept_live)
end

local pending_keep_build = nil
local function keep_build_pre(args)
    for i = 2, 8 do
        local obj = managed_arg(args[i])
        apply_set_life(obj)
        if type_name(obj) == "app.cKeepQuestData" then
            pending_keep_build = obj
        end
    end
end

local function keep_build_post(retval)
    local obj = nil
    pcall(function()
        obj = sdk.to_managed_object(retval)
    end)
    apply_set_life(obj or pending_keep_build)
    pending_keep_build = nil
    return retval
end

local BOARD_GETTERS = {
    "get_QuestLv()",
    "get_TimeLimit()",
    "get_QuestType()",
    "get_RemMoney()",
    "get_HRPoint()",
    "get_MissionId()",
    "get_QuestAttribute()",
}

-- Pre-hook writes _QuestLife then lets the original method return.
-- Never replace getQuestLife's retval (that crash is a garbage pointer).
-- Never hook via.gui.message.get at boot (1.7.15 black-screened).
-- Never call get_QuestLife from Lua (1.7.44 Recursive hook).
-- Never rewrite get_QuestLife retval (1.7.46: getter not called for investigation UI).
local LIFE_GETTERS = {
    "get_QuestLife()",
    "get_QuestLife",
    "getQuestLife()",
    "getQuestLife",
}

local function pass_retval(retval)
    return retval
end

-- Do not rewrite retval (1.7.65 div0). 3 is on a nested object, not ActiveQuestData fields.
local life_write_logs = 0
local dumped_life_types = {}
local function write_if_life(obj, tag)
    if obj == nil or type(obj) ~= "userdata" then
        return
    end
    if not is_normal_cart_cap(read_quest_life(obj)) then
        return
    end
    pcall(write_quest_life, obj, TARGET)
    pcall(patch_life_field, obj)
    if life_write_logs < 8 then
        life_write_logs = life_write_logs + 1
        info("life-child-wrote " .. tag .. " " .. tostring(type_name(obj)))
    end
end

local function each_instance_field(obj, fn)
    local td = nil
    pcall(function()
        td = obj:get_type_definition()
    end)
    local fields = nil
    if td ~= nil then
        pcall(function()
            fields = td:get_fields()
        end)
    end
    if fields == nil then
        return
    end
    for _, field in ipairs(fields) do
        pcall(function()
            if not field:is_static() then
                fn(field:get_name(), field)
            end
        end)
    end
end

local function patch_nested_life(obj)
    if obj == nil or type(obj) ~= "userdata" then
        return
    end
    write_if_life(obj, "self")
    each_instance_field(obj, function(fname)
        local child = try_get_field(obj, fname)
        write_if_life(child, fname)
        if type(child) == "userdata" then
            each_instance_field(child, function(gname)
                write_if_life(try_get_field(child, gname), fname .. "." .. gname)
            end)
        end
    end)
end

local function life_get_pre(args)
    local obj = managed_arg(args[2])
    if obj == nil then
        return
    end
    pcall(patch_nested_life, obj)
    local tn = type_name(obj) or "?"
    if dumped_life_types[tn] then
        return
    end
    dumped_life_types[tn] = true
    info("life-this " .. tn .. " life=" .. tostring(read_quest_life(obj)))
    local names = {}
    each_instance_field(obj, function(fname, field)
        local ftn = nil
        pcall(function()
            ftn = field:get_type():get_full_name()
        end)
        names[#names + 1] = fname .. ":" .. tostring(ftn)
        local child = try_get_field(obj, fname)
        if fname == "_QuestData" or fname == "QuestData" then
            info("active-qd " .. tostring(type_name(child)) .. " life=" .. tostring(read_quest_life(child)))
        end
        if type(child) == "userdata" then
            info("life-child " .. fname .. " " .. tostring(type_name(child)) .. " life=" .. tostring(read_quest_life(child)))
            if type_name(child) == "app.cKeepQuestData" then
                local knames = {}
                each_instance_field(child, function(gname, gfield)
                    local gtn = nil
                    pcall(function()
                        gtn = gfield:get_type():get_full_name()
                    end)
                    knames[#knames + 1] = gname .. ":" .. tostring(gtn)
                end)
                info("keep-all " .. table.concat(knames, ","))
            end
            each_instance_field(child, function(gname)
                local gc = try_get_field(child, gname)
                if type(gc) == "userdata" then
                    info("life-gc " .. fname .. "." .. gname .. " " .. tostring(type_name(gc)) .. " life=" .. tostring(read_quest_life(gc)))
                elseif is_normal_cart_cap(life_num(gc)) then
                    info("life-gc " .. fname .. "." .. gname .. " n=" .. tostring(life_num(gc)))
                end
            end)
        end
    end)
    if #names > 0 then
        info("life-all " .. table.concat(names, ","))
    end
end

local life_get_logs = 0
local function hunt_playing()
    local qd = state.cached_qd
    if qd == nil then
        return false
    end
    local flow = type_name(try_get_field(qd, "_CurFlow")) or ""
    return flow:find("Playing", 1, true) ~= nil
end

local function life_get_post(retval)
    local n = nil
    pcall(function()
        n = sdk.to_int64(retval)
    end)
    if type(n) ~= "number" then
        return retval
    end
    n = n % 256
    if hunt_playing() and n ~= TARGET then
        local packed = nil
        pcall(function()
            packed = sdk.to_ptr(TARGET)
        end)
        local bits = nil
        pcall(function()
            bits = tonumber((tostring(packed):match("(%x+)$") or ""), 16)
        end)
        if packed ~= nil and bits == TARGET then
            if life_get_logs < 8 then
                life_get_logs = life_get_logs + 1
                info("life-ptr orig=" .. tostring(n) .. " ud=" .. tostring(packed))
            end
            state.hunt_diag = "get_QuestLife=" .. tostring(n) .. " ptr=99"
            return packed
        end
        if life_get_logs < 8 then
            life_get_logs = life_get_logs + 1
            info("life-ptr skip bits=" .. tostring(bits) .. " ud=" .. tostring(packed))
        end
    end
    state.hunt_diag = "get_QuestLife=" .. tostring(n)
    if is_normal_cart_cap(n) and life_get_logs < 6 then
        life_get_logs = life_get_logs + 1
        info("life-get orig=" .. tostring(n) .. " play=" .. tostring(hunt_playing()))
    end
    return retval
end

-- ParamType INT=2 (Enums_Internal.hpp). Fail-life text is 力尽倒下{0}次 + one INT param.
local INT_TYPES = {
    ["System.Byte"] = true,
    ["System.SByte"] = true,
    ["System.Int16"] = true,
    ["System.UInt16"] = true,
    ["System.Int32"] = true,
    ["System.UInt32"] = true,
    ["System.Int64"] = true,
    ["System.UInt64"] = true,
}
local UNION_INT_FIELDS = {}
local UNION_FIELD_LOG = "none"
local PARAM_UNION_TD = sdk.find_type_definition("ace.cGUIMessageInfo.ParamUnion")
local PARAM_DATA_TD = sdk.find_type_definition("ace.cGUIMessageInfo.ParamData")
do
    local fields = nil
    local parts = {}
    if PARAM_UNION_TD ~= nil then
        pcall(function()
            fields = PARAM_UNION_TD:get_fields()
        end)
    end
    if fields ~= nil then
        for _, field in ipairs(fields) do
            pcall(function()
                if not field:is_static() then
                    local fname = field:get_name()
                    local ftn = field:get_type():get_full_name()
                    parts[#parts + 1] = fname .. ":" .. tostring(ftn)
                    if INT_TYPES[ftn] then
                        UNION_INT_FIELDS[#UNION_INT_FIELDS + 1] = fname
                    end
                end
            end)
        end
    end
    if #parts > 0 then
        UNION_FIELD_LOG = table.concat(parts, ",")
    end
    info("ParamUnion fields " .. UNION_FIELD_LOG)
end
do
    local parts = {}
    local fields = nil
    if PARAM_DATA_TD ~= nil then
        pcall(function()
            fields = PARAM_DATA_TD:get_fields()
        end)
    end
    if fields ~= nil then
        for _, field in ipairs(fields) do
            pcall(function()
                if not field:is_static() then
                    parts[#parts + 1] = field:get_name()
                end
            end)
        end
    end
    if #parts > 0 then
        info("ParamData fields " .. table.concat(parts, ","))
    end
end

local function as_int(v)
    if type(v) == "number" then
        return math.floor(v)
    end
    if v == nil then
        return nil
    end
    local n = nil
    if sdk.to_int64 ~= nil then
        pcall(function()
            n = sdk.to_int64(v)
        end)
    end
    if type(n) == "number" then
        return n
    end
    return tonumber(tostring(v))
end

local function native_get(obj, td, name)
    local v = nil
    if obj ~= nil and td ~= nil and sdk.get_native_field ~= nil then
        pcall(function()
            v = sdk.get_native_field(obj, td, name)
        end)
    end
    if v ~= nil then
        return v
    end
    return try_get_field(obj, name)
end

local function native_set(obj, td, name, value)
    local ok = false
    if obj ~= nil and td ~= nil and sdk.set_native_field ~= nil then
        ok = pcall(function()
            sdk.set_native_field(obj, td, name, value)
        end)
    end
    if not ok then
        ok = try_set_field(obj, name, value)
    end
    return ok
end

local function faint_replace(text)
    if type(text) ~= 'string' then
        return nil
    end
    local n = text:gsub('倒下3次', '倒下99次'):gsub('倒下０次', '倒下99次')
        :gsub('倒下0次', '倒下99次'):gsub('倒下３次', '倒下99次')
        :gsub('倒下三次', '倒下99次'):gsub('Faint 3 time', 'Faint 99 time')
        :gsub('Faint 0 time', 'Faint 99 time')
        :gsub('0/3', '0/99'):gsub('0／3', '0／99')
    if n == text then
        return nil
    end
    return n
end

local function patch_template_string(s)
    if type(s) ~= 'string' then
        return nil
    end
    if s:find('力尽倒下', 1, true) or s:find('Faint', 1, true) then
        return (s:gsub('{0}', '99'))
    end
    return nil
end

local function union_int_names()
    if #UNION_INT_FIELDS > 0 then
        return UNION_INT_FIELDS
    end
    return { "Int", "Int32", "INT", "mInt", "IntValue", "Value", "i32", "m_value" }
end

local function patch_param_data(pd)
    if pd == nil or type(pd) ~= 'userdata' then
        return nil, nil, false, nil
    end
    local s = try_get_field(pd, 'ParamString')
    local n = faint_replace(s)
    if n ~= nil then
        try_set_field(pd, 'ParamString', n)
    end
    local ptype = as_int(native_get(pd, PARAM_DATA_TD, "ParamType"))
    if ptype == 1 and (state.pstr_logs or 0) < 6 then
        state.pstr_logs = (state.pstr_logs or 0) + 1
        info("pstr " .. tostring(to_text(s)))
    end
    local union = native_get(pd, PARAM_DATA_TD, "ParamValue")
    local names = union_int_names()
    local before = nil
    local wrote = false
    if type(union) == "number" then
        before = union
        if before == 3 or before == 5 then
            wrote = native_set(pd, PARAM_DATA_TD, "ParamValue", TARGET)
        end
    elseif type(union) == "userdata" then
        for _, fname in ipairs(names) do
            local cur = as_int(native_get(union, PARAM_UNION_TD, fname))
            if before == nil and cur ~= nil then
                before = cur
            end
            if cur == 3 or cur == 5 then
                native_set(union, PARAM_UNION_TD, fname, TARGET)
                wrote = true
            end
        end
        if wrote then
            native_set(pd, PARAM_DATA_TD, "ParamValue", union)
            try_set_field(pd, "ParamValue", union)
        end
    end
    local after = nil
    local u2 = native_get(pd, PARAM_DATA_TD, "ParamValue")
    if type(u2) == "number" then
        after = u2
    elseif type(u2) == "userdata" then
        after = as_int(native_get(u2, PARAM_UNION_TD, names[1]))
    end
    return ptype, before, wrote, after
end

local function patch_msginfo(obj)
    if obj == nil or type(obj) ~= 'userdata' then
        return
    end
    local params = try_get_field(obj, '<Params>k__BackingField')
        or try_call(obj, 'get_Params()') or try_call(obj, 'get_Params')
    local count = try_call(params, 'get_Count()') or try_call(params, 'get_Count')
    if type(count) ~= "number" then
        if state.fail_life_diag ~= "params=" .. tostring(count) then
            state.fail_life_diag = "params=" .. tostring(count)
            info("fail-life " .. state.fail_life_diag)
        end
        return
    end
    if count < 1 or count > 8 then
        local diag = "n=" .. tostring(count)
        if state.fail_life_diag ~= diag then
            state.fail_life_diag = diag
            info("fail-life " .. diag)
        end
        return
    end
    local ptype, before, wrote, after
    for i = 0, count - 1 do
        local pd = try_call(params, 'get_Item', i) or try_call(params, 'get_Item(System.Int32)', i)
        ptype, before, wrote, after = patch_param_data(pd)
    end
    local diag = string.format(
        "n=%s type=%s before=%s wrote=%s after=%s fields=%s",
        tostring(count),
        tostring(ptype),
        tostring(before),
        tostring(wrote),
        tostring(after),
        table.concat(UNION_INT_FIELDS, ",")
    )
    if state.fail_life_diag ~= diag then
        info("fail-life " .. diag)
    end
    state.fail_life_diag = diag
end

-- Format happens during the original getter. 1.7.23 treated ParamUnion as
-- int 3 and replaced the union pointer with 99, so the UI read 0.
local in_fail_life = 0

local function method_param_types(method)
    local names = {}
    pcall(function()
        local types = method:get_param_types()
        if types ~= nil then
            for _, t in ipairs(types) do
                names[#names + 1] = t:get_full_name()
            end
        end
    end)
    return names
end

local INT_ARG_TD = {
    ["System.Int32"] = sdk.find_type_definition("System.Int32"),
    ["System.Int64"] = sdk.find_type_definition("System.Int64"),
    ["System.Byte"] = sdk.find_type_definition("System.Byte"),
}
local INT32_VALUE_FIELD = "m_value"
do
    local td = INT_ARG_TD["System.Int32"]
    local fields = nil
    if td ~= nil then
        pcall(function()
            fields = td:get_fields()
        end)
    end
    local parts = {}
    if fields ~= nil then
        for _, field in ipairs(fields) do
            pcall(function()
                if not field:is_static() then
                    parts[#parts + 1] = field:get_name()
                end
            end)
        end
    end
    if #parts > 0 then
        INT32_VALUE_FIELD = parts[1]
        info("Int32 fields " .. table.concat(parts, ","))
    end
end

-- Int32 may be by-value in the slot (small to_int64) or a pointer (m_value).
-- 1.7.23 replaced leftover slots and the UI showed 0. Only touch 1-30.
local dumped_int32 = false
local function rewrite_life_int(args, idx)
    local v = args[idx]
    if v == nil then
        return false
    end
    local raw = nil
    pcall(function()
        raw = sdk.to_int64(v)
    end)
    local n = raw
    if type(n) ~= "number" then
        n = tonumber(tostring(raw))
    end
    -- Pointer slots are huge. Only rewrite the bare 1-30 int (log: slot 4=3).
    -- Do not to_managed_object pointer slots — that aborted the loop before slot 4 (1.7.41).
    if type(n) ~= "number" or n < 1 or n > 30 then
        return false
    end
    local ok, err = pcall(function()
        args[idx] = sdk.to_int64(TARGET)
    end)
    if ok then
        return true
    end
    info("rewrite slot " .. tostring(idx) .. " val=" .. tostring(n)
        .. " type=" .. type(raw) .. " assign-fail " .. tostring(err))
    return false
end

local function dump_int32_args(args)
    if dumped_int32 then
        return
    end
    dumped_int32 = true
    local parts = {}
    for i = 1, 6 do
        local raw = nil
        pcall(function()
            raw = sdk.to_int64(args[i])
        end)
        local mv = as_int(native_get(args[i], INT_ARG_TD["System.Int32"], INT32_VALUE_FIELD))
        parts[#parts + 1] = tostring(i) .. "=" .. tostring(raw) .. "/" .. tostring(mv)
    end
    state.fmt_dump = table.concat(parts, " ")
    info("int32-args " .. state.fmt_dump)
end

local add_this = nil
local add_post_logs = 0
local adding_99 = false
local SKIP_ORIGINAL = nil
pcall(function()
    SKIP_ORIGINAL = sdk.PreHookResult.SKIP_ORIGINAL
end)

local function slot_small_int(args, i)
    local n = nil
    pcall(function()
        n = sdk.to_int64(args[i])
    end)
    if type(n) == "number" and n >= 1 and n <= 30 then
        return n
    end
    return nil
end

local function add_int_pre(args)
    if in_fail_life < 1 then
        add_this = nil
        return
    end
    state.fmt_add = state.fmt_add + 1
    dump_int32_args(args)
    add_this = managed_arg(args[2])
end

local make_this = nil
local make_post_logs = 0
local function make_int_pre(args)
    make_this = nil
    if in_fail_life < 1 then
        return
    end
    state.fmt_add = state.fmt_add + 1
    dump_int32_args(args)
    make_this = managed_arg(args[2])
end

local function coerce_param_data(retval)
    if retval == nil then
        return nil, "nil"
    end
    local pd = managed_arg(retval)
    if pd ~= nil then
        return pd, "managed"
    end
    if type(retval) == "userdata" then
        return retval, "raw"
    end
    if sdk.to_valuetype ~= nil and PARAM_DATA_TD ~= nil then
        local ok, vt = pcall(function()
            return sdk.to_valuetype(retval, PARAM_DATA_TD)
        end)
        if ok and vt ~= nil then
            return vt, "valuetype"
        end
        ok, vt = pcall(function()
            return sdk.to_valuetype(retval, "ace.cGUIMessageInfo.ParamData")
        end)
        if ok and vt ~= nil then
            return vt, "valuetype-name"
        end
    end
    return nil, type(retval)
end

local function make_post(retval)
    if in_fail_life < 1 then
        return retval
    end
    if make_this ~= nil then
        pcall(patch_msginfo, make_this)
    end
    local pd, how = coerce_param_data(retval)
    local ptype, before, wrote, after
    if pd ~= nil then
        ptype, before, wrote, after = patch_param_data(pd)
    end
    if make_post_logs < 6 then
        make_post_logs = make_post_logs + 1
        info("make-post how=" .. tostring(how)
            .. " type=" .. tostring(ptype)
            .. " before=" .. tostring(before)
            .. " wrote=" .. tostring(wrote)
            .. " after=" .. tostring(after)
            .. " this=" .. tostring(make_this ~= nil))
    end
    return retval
end

local add_int_seen = 0
local function add_param_int_pre(args)
    if adding_99 then
        return
    end
    if in_fail_life < 1 then
        return
    end
    state.fmt_add = state.fmt_add + 1
    dump_int32_args(args)
    local n3 = slot_small_int(args, 3)
    local n4 = slot_small_int(args, 4)
    if add_int_seen < 4 then
        add_int_seen = add_int_seen + 1
        info("add-int-pre n3=" .. tostring(n3) .. " n4=" .. tostring(n4))
    end
    local n = n4 or n3
    if n ~= 3 then
        add_this = managed_arg(args[2])
        return
    end
    local this = managed_arg(args[2])
    if this == nil then
        info("skip-add no this")
        return
    end
    local ok = false
    adding_99 = true
    pcall(function()
        this:call("addParam(System.Int32)", TARGET)
        ok = true
    end)
    adding_99 = false
    if ok and SKIP_ORIGINAL ~= nil then
        info("skip-add 3 call-99")
        return SKIP_ORIGINAL
    end
    info("skip-add call99=" .. tostring(ok))
end

local function add_int_post(retval)
    if add_this ~= nil then
        pcall(patch_msginfo, add_this)
        if add_post_logs < 2 then
            add_post_logs = add_post_logs + 1
            info("addParam-post patched")
        end
        add_this = nil
    end
    return retval
end

local dumped_set_msg = false
local function format_pre(args)
    if in_fail_life < 1 then
        return
    end
    state.fmt_str = state.fmt_str + 1
    local s = nil
    local obj = sdk.to_managed_object(args[2])
    pcall(function()
        if obj ~= nil then
            s = obj:call("ToString()")
        end
    end)
    if type(s) ~= "string" then
        return
    end
    if not (s:find("倒下", 1, true) or s:find("Faint", 1, true) or s:find("faint", 1, true)) then
        return
    end
    for i = 2, 6 do
        if rewrite_life_int(args, i) then
            state.fmt_rewrote = state.fmt_rewrote + 1
        end
        local arr = sdk.to_managed_object(args[i])
        if arr ~= nil then
            local len = try_call(arr, "get_Length()") or try_call(arr, "get_Length")
            if type(len) == "number" and len > 0 and len <= 8 then
                for n = 0, len - 1 do
                    local item = try_call(arr, "GetValue", n) or try_call(arr, "get_Item", n)
                    local cur = as_int(item)
                    if cur ~= nil and cur >= 1 and cur <= 30 and sdk.create_int32 ~= nil then
                        pcall(function()
                            arr:call("SetValue", sdk.create_int32(TARGET), n)
                        end)
                        state.fmt_rewrote = state.fmt_rewrote + 1
                    end
                end
            end
        end
    end
end

local function pts_post(retval)
    if in_fail_life < 1 then
        return retval
    end
    state.fmt_pts = state.fmt_pts + 1
    local obj = sdk.to_managed_object(retval)
    if obj == nil then
        local n = as_int(retval)
        if n == 3 then
            state.fmt_rewrote = state.fmt_rewrote + 1
            return sdk.to_ptr(sdk.to_int64(TARGET))
        end
        return retval
    end
    local len = try_call(obj, "get_Length()") or try_call(obj, "get_Length")
        or try_call(obj, "get_Count()") or try_call(obj, "get_Count")
    if type(len) == "number" and len > 0 and len <= 8 then
        for i = 0, len - 1 do
            local item = try_call(obj, "GetValue", i) or try_call(obj, "get_Item", i)
            if as_int(item) == 3 then
                if sdk.create_int32 ~= nil then
                    pcall(function()
                        obj:call("SetValue", sdk.create_int32(TARGET), i)
                    end)
                end
                state.fmt_rewrote = state.fmt_rewrote + 1
            end
        end
    end
    return retval
end

local dumped_fail_args = false
local ensure_msg_get_hook
local function dump_type_chain(obj)
    local td = nil
    pcall(function()
        td = obj:get_type_definition()
    end)
    local depth = 0
    while td ~= nil and depth < 5 do
        local tn = nil
        pcall(function()
            tn = td:get_full_name()
        end)
        local fields = nil
        pcall(function()
            fields = td:get_fields()
        end)
        local names = {}
        if fields ~= nil then
            for _, field in ipairs(fields) do
                local fname = nil
                pcall(function()
                    if not field:is_static() then
                        fname = field:get_name()
                    end
                end)
                if fname ~= nil then
                    names[#names + 1] = fname
                end
            end
        end
        info("fields " .. tostring(tn) .. " " .. table.concat(names, ","))
        local parent = nil
        pcall(function()
            parent = td:get_parent_type()
        end)
        if parent == nil then
            pcall(function()
                parent = td:get_parent()
            end)
        end
        td = parent
        depth = depth + 1
    end
end

local function dump_life_methods(obj)
    local td = nil
    pcall(function()
        td = obj:get_type_definition()
    end)
    local methods = nil
    if td ~= nil then
        pcall(function()
            methods = td:get_methods()
        end)
    end
    if methods == nil then
        return
    end
    local names = {}
    for _, method in ipairs(methods) do
        local name = nil
        pcall(function()
            name = method:get_name()
        end)
        if name ~= nil then
            local lower = name:lower()
            if lower:find("life", 1, true) or lower:find("die", 1, true) then
                local rtn = nil
                pcall(function()
                    rtn = method:get_return_type():get_full_name()
                end)
                names[#names + 1] = name .. ":" .. tostring(rtn)
            end
        end
    end
    info("methods " .. (type_name(obj) or "?") .. " " .. table.concat(names, ","))
end

local function find_keep_quest(obj)
    if obj == nil then
        return nil
    end
    if type_name(obj) == "app.cKeepQuestData" then
        return obj
    end
    local keep = try_get_field(obj, "<KeepQuestData>k__BackingField")
        or try_get_field(obj, "KeepQuestData")
        or try_get_field(obj, "_KeepQuestData")
    if keep ~= nil then
        return keep
    end
    local nested = try_get_field(obj, "<ActiveQuestData>k__BackingField")
        or try_get_field(obj, "ActiveQuestData")
    if nested ~= nil and nested ~= obj then
        return find_keep_quest(nested)
    end
    return nil
end

local function patch_fail_life_args(args)
    for i = 2, 4 do
        local obj = managed_arg(args[i])
        if obj ~= nil then
            pcall(patch_life_field, obj)
            pcall(write_quest_life, obj, TARGET)
            local keep = find_keep_quest(obj)
            if keep ~= nil then
                pcall(patch_life_field, keep)
                pcall(write_quest_life, keep, TARGET)
            end
            if not dumped_fail_args then
                info("fail-arg[" .. tostring(i) .. "] " .. (type_name(obj) or "?"))
                pcall(dump_type_chain, obj)
                pcall(dump_life_methods, obj)
                if keep ~= nil then
                    pcall(dump_type_chain, keep)
                    pcall(dump_life_methods, keep)
                end
            end
        end
    end
    dumped_fail_args = true
end

local function fail_life_pre(args)
    in_fail_life = in_fail_life + 1
    state.fail_life_frame = state.frame
    pcall(patch_fail_life_args, args)
end

local fail_fn_logs = 0
local function wrap_fail_pre(tag)
    return function(args)
        if fail_fn_logs < 12 then
            fail_fn_logs = fail_fn_logs + 1
            info("fail-fn " .. tostring(tag))
        elseif hunt_playing() and (state.hunt_fn or 0) < 8 then
            state.hunt_fn = (state.hunt_fn or 0) + 1
            info("hunt-fn " .. tostring(tag))
        end
        return fail_life_pre(args)
    end
end

local function board_open()
    local started = state.fail_life_frame
    if started == nil or started == 0 then
        return false
    end
    return state.frame - started <= 600
end

local function to_text(v)
    if v == nil then
        return nil
    end
    if type(v) == "string" then
        return v
    end
    local s = nil
    pcall(function()
        s = v:call("ToString()")
    end)
    return s
end

local str_len_off = nil
local str_char_off = nil
local msg_get_hooked = false
local mutate_logs = 0
local get_hits = 0
local CN99 = { 0x529B, 0x5C3D, 0x5012, 0x4E0B, 0x0039, 0x0039, 0x6B21 }
local CN99_SHORT = { 0x529B, 0x5C3D, 0x5012, 0x0039, 0x0039, 0x6B21 }
local EN99 = { 0x46, 0x61, 0x69, 0x6E, 0x74, 0x20, 0x39, 0x39, 0x20, 0x74, 0x69, 0x6D, 0x65, 0x73 }

local function init_string_layout()
    if str_char_off ~= nil then
        return
    end
    local probe = nil
    pcall(function()
        probe = sdk.create_managed_string("AB")
    end)
    if probe == nil then
        return
    end
    for off = 8, 48, 2 do
        local a = nil
        local b = nil
        pcall(function()
            a = probe:read_short(off)
            b = probe:read_short(off + 2)
        end)
        if a == 0x41 and b == 0x42 then
            str_char_off = off
            break
        end
    end
    for off = 8, 40, 4 do
        local n = nil
        pcall(function()
            n = probe:read_dword(off)
        end)
        if n == 2 then
            str_len_off = off
            break
        end
    end
    info("String layout len=" .. tostring(str_len_off) .. " chars=" .. tostring(str_char_off))
end

local function write_wchars(obj, codes)
    for i = 1, #codes do
        obj:write_short(str_char_off + (i - 1) * 2, codes[i])
    end
end

local function mutate_faint_string(obj, s)
    if str_char_off == nil or str_len_off == nil then
        return false
    end
    if s:find("力尽倒下", 1, true) then
        if s:find("{0}", 1, true) then
            write_wchars(obj, CN99)
            obj:write_dword(str_len_off, 7)
            local after = to_text(obj)
            info("readback " .. tostring(after))
            return type(after) == "string" and after:find("99", 1, true) ~= nil
        end
        if s:find("3次", 1, true) or s:find("３次", 1, true) or s:find("0次", 1, true) then
            write_wchars(obj, CN99_SHORT)
            obj:write_dword(str_len_off, 6)
            return true
        end
    end
    if s:find("Faint", 1, true) and s:find("{0}", 1, true) then
        write_wchars(obj, EN99)
        obj:write_dword(str_len_off, 14)
        return true
    end
    return false
end

local function msg_get_post(retval)
    if str_char_off == nil then
        return retval
    end
    local obj = managed_arg(retval)
    if obj == nil then
        return retval
    end
    local c0 = nil
    local c1 = nil
    pcall(function()
        c0 = obj:read_short(str_char_off)
        c1 = obj:read_short(str_char_off + 2)
    end)
    local faint_cn = c0 == 0x529B and c1 == 0x5C3D
    local faint_en = c0 == 0x46 and c1 == 0x61
    if faint_en then
        local c2 = nil
        local c3 = nil
        pcall(function()
            c2 = obj:read_short(str_char_off + 4)
            c3 = obj:read_short(str_char_off + 6)
        end)
        faint_en = c2 == 0x69 and c3 == 0x6E
    end
    if not faint_cn and not faint_en then
        return retval
    end
    local s = to_text(obj)
    if get_hits < 8 then
        get_hits = get_hits + 1
        local prefix = type(s) == "string" and s:sub(1, 32) or tostring(s)
        info("get-hit managed=true text=" .. tostring(prefix))
    end
    if type(s) == "string" then
        -- 1.7.55: write_short does not change ToString (readback still {0}).
        if get_hits <= 2 then
            info("skip-mutate-get " .. s:sub(1, 32))
        end
    end
    return retval
end

local data_dump_n = 0
local dumped_data_api = false
local function mutate_data_fields(obj)
    if obj == nil then
        return
    end
    local s = to_text(obj)
    if type(s) == "string" and s:find("力尽倒下", 1, true) then
        pcall(mutate_faint_string, obj, s)
    end
    local td = nil
    pcall(function()
        td = obj:get_type_definition()
    end)
    local fields = nil
    if td ~= nil then
        pcall(function()
            fields = td:get_fields()
        end)
    end
    if fields == nil then
        fields = {}
    end
    if not dumped_data_api then
        dumped_data_api = true
        info("getData nfields=" .. tostring(#fields) .. " type=" .. tostring(td and td:get_full_name()))
        local methods = nil
        if td ~= nil then
            pcall(function()
                methods = td:get_methods()
            end)
        end
        if methods ~= nil then
            local mi = 0
            for _, method in ipairs(methods) do
                mi = mi + 1
                if mi > 20 then
                    break
                end
                local mn = nil
                pcall(function()
                    mn = method:get_name()
                end)
                if mn ~= nil then
                    local sig = mn .. "(" .. table.concat(method_param_types(method), ",") .. ")"
                    info("getData.m " .. sig)
                    if mn:sub(1, 4) == "get_" or mn == "get" or mn == "ToString" then
                        local v = try_call(obj, mn .. "()") or try_call(obj, mn)
                        info("getData.call " .. mn .. "=" .. tostring(to_text(v) or v))
                    end
                end
            end
        end
    end
    local n = 0
    for _, f in ipairs(fields) do
        n = n + 1
        if n > 12 then
            break
        end
        local fn = nil
        pcall(function()
            fn = f:get_name()
        end)
        if fn ~= nil then
            local v = try_get_field(obj, fn)
            local vs = to_text(v)
            if data_dump_n < 12 then
                data_dump_n = data_dump_n + 1
                info("getData." .. tostring(fn) .. "=" .. tostring(vs or type(v)))
            end
            if type(vs) == "string" and vs:find("力尽倒下", 1, true) then
                pcall(mutate_faint_string, v, vs)
            end
        end
    end
end

local pull_n = 0
local function pull_faint_template()
    if pull_n >= 2 or str_char_off == nil then
        return
    end
    pull_n = pull_n + 1
    local obj = nil
    local text = nil
    pcall(function()
        local guid = sdk.create_instance("System.Guid", false)
        local parsed = guid:call("Parse(System.String)", FAINT_LIFE_GUID)
        if parsed == nil then
            parsed = guid:call("Parse", FAINT_LIFE_GUID)
        end
        if parsed ~= nil then
            guid = parsed
        end
        local m = sdk.find_type_definition("via.gui.message"):get_method("get(System.Guid)")
        obj = m:call(nil, guid)
        text = to_text(obj)
        local dm = sdk.find_type_definition("via.gui.message"):get_method("getData(System.Guid)")
        if dm ~= nil then
            local data = dm:call(nil, guid)
            local dobj = managed_arg(data)
            if dobj == nil and type(data) == "userdata" then
                dobj = data
            end
            info("getData type=" .. tostring(type_name(dobj)) .. " text=" .. tostring(to_text(dobj)))
            pcall(mutate_data_fields, dobj)
        end
        local gp = sdk.find_type_definition("via.gui.message"):get_method("getParamString(System.Guid, System.UInt32)")
        if gp ~= nil then
            local ps = gp:call(nil, guid, 0)
            info("getParamString0 " .. tostring(to_text(ps)))
        end
    end)
    info("pulled[" .. tostring(pull_n) .. "] " .. tostring(text))
    if obj ~= nil and type(text) == "string" then
        pcall(mutate_faint_string, obj, text)
    end
end

ensure_msg_get_hook = function()
    if msg_get_hooked then
        return
    end
    msg_get_hooked = true
    pcall(init_string_layout)
    local api_n = 0
    for _, tn in ipairs({ "via.gui.message", "via.gui.Message" }) do
        local td = sdk.find_type_definition(tn)
        local methods = nil
        if td ~= nil then
            pcall(function()
                methods = td:get_methods()
            end)
        end
        if methods ~= nil then
            for _, method in ipairs(methods) do
                local name = nil
                pcall(function()
                    name = method:get_name()
                end)
                if name ~= nil then
                    local params = table.concat(method_param_types(method), ",")
                    if name ~= "get" and api_n < 16 then
                        api_n = api_n + 1
                        info("msg-api " .. tn .. "." .. name .. "(" .. params .. ")")
                    end
                end
                if name == "get" then
                    local rtn = nil
                    pcall(function()
                        rtn = method:get_return_type():get_full_name()
                    end)
                    local params = table.concat(method_param_types(method), ",")
                    info("get-method " .. tn .. "(" .. params .. ") -> " .. tostring(rtn))
                    if rtn == "System.String" then
                        pcall(function()
                            sdk.hook(method, function(_args) end, msg_get_post)
                        end)
                        info("hook " .. tn .. ".get -> String queued")
                    end
                elseif name == "getData" then
                    pcall(function()
                        sdk.hook(method, function(_args) end, function(retval)
                            if in_fail_life < 1 and state.fail_life_frame == 0 then
                                return retval
                            end
                            local dobj = managed_arg(retval)
                            if dobj == nil and type(retval) == "userdata" then
                                dobj = retval
                            end
                            pcall(mutate_data_fields, dobj)
                            return retval
                        end)
                    end)
                    info("hook " .. tn .. ".getData queued")
                end
            end
        end
    end
end

local function patch_guid_param(guid, params)
    if guid == nil or params == nil or state.msg_ids[guid] ~= true then
        return
    end
    local count = try_call(params, "get_Count()") or try_call(params, "get_Count")
    if type(count) == "number" and count > 0 and count <= 8 then
        for i = 0, count - 1 do
            local item = try_call(params, "get_Item", i)
                or try_call(params, "get_Item(System.Int32)", i)
            local cur = as_int(item)
            if cur ~= nil and cur >= 1 and cur <= 30 and sdk.create_int32 ~= nil then
                pcall(function()
                    params:call("SetValue", sdk.create_int32(TARGET), i)
                end)
            end
        end
    end
end

local function text_pre(args)
    local obj = sdk.to_managed_object(args[3])
    local tn = nil
    if obj ~= nil then
        pcall(function()
            tn = obj:get_type_definition():get_full_name()
        end)
    end
    if not dumped_set_msg then
        dumped_set_msg = true
        local tn4 = nil
        pcall(function()
            local o4 = sdk.to_managed_object(args[4])
            if o4 ~= nil then
                tn4 = o4:get_type_definition():get_full_name()
            end
        end)
        state.fmt_dump = "set_Message " .. tostring(tn) .. " | " .. tostring(tn4)
        info(state.fmt_dump)
    end
    if tn == "System.Guid" then
        local g = to_text(obj)
        local recent = state.frame - (state.fail_life_frame or 0) <= 180
        if g ~= nil and (recent or in_fail_life > 0) then
            state.msg_ids[g] = true
            local line = "msg-id " .. tostring(#state.msg_ids)
                .. " " .. tostring(g)
            info(line)
            state.msg_id_dump = line
        end
    end
    if tn == "ace.cGUIMessageInfo" then
        local recent = state.frame - (state.fail_life_frame or 0) <= 180
        if recent or in_fail_life > 0 then
            pcall(patch_msginfo, obj)
            state.fmt_rewrote = state.fmt_rewrote + 1
        end
    end
    if tn == "System.String" then
        local s = to_text(obj)
        local n = patch_template_string(s) or faint_replace(s)
        if n ~= nil and sdk.create_managed_string ~= nil then
            args[3] = sdk.create_managed_string(n)
            state.fmt_rewrote = state.fmt_rewrote + 1
            info("set_Text " .. n)
        end
    end
    local params = sdk.to_managed_object(args[4])
    if params ~= nil then
        local g = to_text(sdk.to_managed_object(args[3]))
        pcall(patch_guid_param, g, params)
    end
end

local function fail_life_post(retval)
    local obj = sdk.to_managed_object(retval)
    if obj == nil then
        state.fail_life_diag = "retval not object"
        info("fail-life " .. state.fail_life_diag)
        if in_fail_life > 0 then
            in_fail_life = in_fail_life - 1
        end
        return retval
    end
    pcall(patch_msginfo, obj)
    if fail_fn_logs <= 12 then
        local msg = try_call(obj, "get_Message()") or try_call(obj, "get_Message")
        info("fail-msg " .. tostring(to_text(msg) or to_text(obj)))
    end
    if hunt_playing() and (state.hunt_msg or 0) < 8 then
        state.hunt_msg = (state.hunt_msg or 0) + 1
        local msg = try_call(obj, "get_Message()") or try_call(obj, "get_Message")
        info("hunt-msg " .. tostring(to_text(msg)) .. " t=" .. tostring(type_name(msg)))
    end
    if in_fail_life > 0 then
        in_fail_life = in_fail_life - 1
    end
    return retval
end

do
    local td = sdk.find_type_definition("ace.cGUIMessageInfo")
    local methods = nil
    if td ~= nil then
        pcall(function()
            methods = td:get_methods()
        end)
    end
    if methods ~= nil then
        for _, method in ipairs(methods) do
            local name = nil
            pcall(function()
                name = method:get_name()
            end)
            if name == "addParam" or name == "makeParamData" then
                local ptypes = method_param_types(method)
                local first = 3
                pcall(function()
                    if method:is_static() then
                        first = 2
                    end
                end)
                local sig = name .. "(" .. table.concat(ptypes, ",") .. ")"
                local rt = ""
                pcall(function()
                    local t = method:get_return_type()
                    if t ~= nil then
                        rt = t:get_full_name()
                    end
                end)
                if rt ~= "" then
                    sig = sig .. "->" .. rt
                end
                info("hook cGUIMessageInfo." .. sig)
                if state.fmt_sig == "" then
                    state.fmt_sig = sig
                elseif not state.fmt_sig:find(sig, 1, true) then
                    state.fmt_sig = state.fmt_sig .. " | " .. sig
                end
                pcall(function()
                    local pre = add_int_pre
                    local post = add_int_post
                    if name == "makeParamData" then
                        pre = make_int_pre
                        post = make_post
                    elseif name == "addParam" and #ptypes == 1 and ptypes[1] == "System.Int32" then
                        pre = add_param_int_pre
                        post = pass_retval
                    end
                    sdk.hook(method, pre, post)
                end)
            elseif name == "paramToString" then
                pcall(function()
                    sdk.hook(method, function(_args) end, pts_post)
                end)
            end
        end
    end
end

do
    local td = sdk.find_type_definition("System.String")
    local methods = nil
    if td ~= nil then
        pcall(function()
            methods = td:get_methods()
        end)
    end
    if methods ~= nil then
        for _, method in ipairs(methods) do
            local name = nil
            pcall(function()
                name = method:get_name()
            end)
            if name == "Format" then
                pcall(function()
                    sdk.hook(method, format_pre, pass_retval)
                end)
                local sig = table.concat(method_param_types(method), ",")
                info("hook String.Format(" .. sig .. ")")
            end
        end
    end
end

do
    local type_names = {
        "via.gui.Text",
        "via.gui.Message",
        "via.gui.StaticText",
        "via.gui.GUIText",
    }
    for _, tn in ipairs(type_names) do
        local td = sdk.find_type_definition(tn)
        local methods = nil
        if td ~= nil then
            pcall(function()
                methods = td:get_methods()
            end)
        end
        if methods ~= nil then
            for _, method in ipairs(methods) do
                local name = nil
                pcall(function()
                    name = method:get_name()
                end)
                local lower = nil
                if name ~= nil then
                    lower = name:lower()
                end
                if lower ~= nil and lower:sub(1, 4) == "set_"
                    and (lower:find("message", 1, true) or lower:find("param", 1, true)
                        or lower:find("argument", 1, true) or lower:find("text", 1, true))
                then
                    pcall(function()
                        sdk.hook(method, text_pre, pass_retval)
                    end)
                    info("hook " .. tn .. "." .. name .. "(" .. table.concat(method_param_types(method), ",") .. ")")
                end
            end
        end
    end
end

local function hook_named(typedef, sig, pre, post)
    local method = typedef:get_method(sig)
    if method == nil and type(sig) == "string" and sig:sub(-2) == "()" then
        method = typedef:get_method(sig:sub(1, -3))
    end
    if method == nil then
        return
    end
    pcall(function()
        sdk.hook(method, pre, post)
    end)
end

local hooked_board_types = {}
local hook_board_type
local board_pre_hook

board_pre_hook = function(args)
    local obj = managed_arg(args[2])
    if obj == nil then
        return
    end
    local tn = type_name(obj)
    if tn ~= nil and state.logged_types[tn] == nil then
        state.logged_types[tn] = true
        info("board " .. tn .. " QuestLife=" .. tostring(read_quest_life(obj)))
        if state.board_types == "" then
            state.board_types = tn
        elseif not state.board_types:find(tn, 1, true) then
            state.board_types = state.board_types .. " | " .. tn
        end
    end
    pcall(function()
        hook_board_type(obj:get_type_definition())
    end)
    pcall(ensure_msg_get_hook)
    pcall(pull_faint_template)
    patch_life_field(obj)
end

hook_board_type = function(typedef)
    if typedef == nil then
        return
    end
    local name = nil
    pcall(function()
        name = typedef:get_full_name()
    end)
    if name == nil or hooked_board_types[name] then
        return
    end
    hooked_board_types[name] = true
    for _, sig in ipairs(BOARD_GETTERS) do
        hook_named(typedef, sig, board_pre_hook, pass_retval)
    end
    for _, sig in ipairs(LIFE_GETTERS) do
        local pre = board_pre_hook
        local post = pass_retval
        if sig:find("get_QuestLife", 1, true) then
            pre = life_get_pre
            post = life_get_post
        end
        hook_named(typedef, sig, pre, post)
    end
end

local function hook_board_readers()
    local types = {
        "app.user_data.QuestData",
        "app.user_data.QuestData.cData",
        "app.cActiveQuestData",
        "app.cQuestInfo",
        "app.cQuestOrderInfo",
        "app.cQuestListData",
        "app.cGeneratedQuestData",
        "app.cExQuestData",
        "app.user_data.ExQuestData",
        "app.user_data.ExQuestData.cData",
        "app.cFieldQuestData",
        "app.cInvestigationData",
        "app.cResearchQuestData",
        "app.savedata.cQuestSave",
        "app.savedata.cQuestWork",
        "app.savedata.cInvestigation",
        "app.cQuestSaveData",
        "app.cQuestCreateData",
        "app.cQuestOrder",
        "app.cKeepQuestData",
        "app.cGUIQuestViewData",
        "app.GUI050100QuestDetail",
        "app.GUI050000QuestListParts",
        "app.GUIUtilApp.QuestUtil",
        "app.QuestUtil",
        "app.net_session_manager.SessionManager.cSearchResultQuest",
        "app.Net_LobbyUserInfo.CreateQuestInfo",
        "app.savedata.cQuestParam",
        "app.savedata.cInstantQuestParam",
        "app.cInstantQuestTemporaryHolder",
    }
    for _, type_name in ipairs(types) do
        hook_board_type(sdk.find_type_definition(type_name))
    end
end

local BOARD_WALK_MAX = 400
local BOARD_WALK_DEPTH = 5
local BOARD_KEEP = {
    _Setting = true,
    _Values = true,
    _Value = true,
    _Data = true,
    _DataList = true,
    _List = true,
    _Array = true,
    _QuestData = true,
    QuestData = true,
    _Quest = true,
}

local function keep_board_field(name)
    if name == nil then
        return false
    end
    if BOARD_KEEP[name] then
        return true
    end
    local lower = name:lower()
    return lower:find("quest", 1, true)
        or lower:find("accept", 1, true)
        or lower:find("order", 1, true)
        or lower:find("investig", 1, true)
        or lower:find("research", 1, true)
        or lower:find("save", 1, true)
        or lower:find("user", 1, true)
        or lower:find("work", 1, true)
        or lower:find("field", 1, true)
        or lower:find("generat", 1, true)
        or lower:find("instant", 1, true)
        or lower:find("keepquest", 1, true)
        or lower:find("exfield", 1, true)
        or lower:find("exquest", 1, true)
end

local function patch_board_from_mission()
    local seen = {}
    local queue = {}
    local head = 1
    local function enqueue(object, depth, keep_only)
        if object == nil or type(object) ~= "userdata" then
            return
        end
        queue[#queue + 1] = { object, depth, keep_only }
    end
    local mission = get_mission_manager()
    enqueue(mission, 0, false)
    enqueue(sdk.get_managed_singleton("app.SaveDataManager"), 0, false)
    do
        local save_mgr = sdk.get_managed_singleton("app.SaveDataManager")
        if save_mgr ~= nil then
            enqueue(try_call(save_mgr, "getCurrentUserSaveData()"), 0, false)
            enqueue(try_call(save_mgr, "getCurrentUserSaveData"), 0, false)
        end
    end
    enqueue(sdk.get_managed_singleton("app.GUIManager"), 0, true)
    while head <= #queue and head <= BOARD_WALK_MAX do
        local item = queue[head]
        head = head + 1
        local object, depth, keep_only = item[1], item[2], item[3]
        local id = object_id(object)
        if id ~= nil and not seen[id] then
            seen[id] = true
            pcall(function()
                hook_board_type(object:get_type_definition())
            end)
            patch_life_field(object)
            if depth < BOARD_WALK_DEPTH then
                if is_index_list(object) then
                    local count = try_call(object, "get_Count()") or try_call(object, "get_Count")
                    if type(count) == "number" and count > 0 and count <= 500 then
                        for i = 0, count - 1 do
                            local child = try_call(object, "get_Item", i)
                                or try_call(object, "get_Item(System.Int32)", i)
                            enqueue(child, depth + 1, keep_only)
                        end
                    end
                else
                    local typedef = nil
                    pcall(function()
                        typedef = object:get_type_definition()
                    end)
                    local fields = nil
                    if typedef ~= nil then
                        pcall(function()
                            fields = typedef:get_fields()
                        end)
                    end
                    if fields ~= nil then
                        for _, field in ipairs(fields) do
                            local fname = nil
                            pcall(function()
                                if not field:is_static() then
                                    fname = field:get_name()
                                end
                            end)
                            if (not keep_only and depth < 2) or keep_board_field(fname) then
                                local child = try_get_field(object, fname)
                                if child ~= nil and type(child) == "userdata" then
                                    enqueue(child, depth + 1, keep_only)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local function catalog_status_detail()
    if state.catalog_writes > 0 then
        return "Quest list patched"
    end
    return ""
end

local function collect_params(qd)
    local list = {}
    local seen = {}
    local owners = { qd }
    for _, data in ipairs(collect_quest_data(qd)) do
        owners[#owners + 1] = data
    end
    for _, owner in ipairs(owners) do
        for _, name in ipairs(PARAM_FIELD_NAMES) do
            add_unique(list, seen, try_get_field(owner, name))
        end
        for _, getter in ipairs(PARAM_GETTERS) do
            add_unique(list, seen, try_call(owner, getter))
        end
    end
    return list
end

local function current_quest_information(qd)
    -- TU4.1 HunterPie: director+0x38 -> +0x18. Do not use +0x30 (that's Quest::Data).
    local holder = follow_ptr(qd, 0x38)
    if holder == nil then
        return nil
    end
    return follow_ptr(holder, 0x18)
end

-- 1.7.67: +0x38/+0x18 is empty. Try nearby director pointers; require timer or A0=1-30.
local DIR_INFO_OFFS = { 0x20, 0x28, 0x30, 0x38, 0x40, 0x48, 0x50, 0x58, 0x60, 0x80, 0xA0, 0xC0, 0xE0, 0x100, 0x120, 0x140, 0x160, 0x178 }
local NEST_INFO_OFFS = { 0x10, 0x18, 0x20, 0x28, 0x30, 0x38 }
local function scan_quest_info(qd)
    if qd == nil then
        return nil, nil
    end
    for _, o1 in ipairs(DIR_INFO_OFFS) do
        local a = follow_ptr(qd, o1)
        if a ~= nil then
            if quest_timer_at(a, PL_DIE_COUNT_MAX_OFF) then
                return a, MAX_DEATHS_OFF
            end
            local a0 = decode_at(a, MAX_DEATHS_OFF)
            if is_normal_cart_cap(a0) then
                return a, MAX_DEATHS_OFF
            end
            for _, o2 in ipairs(NEST_INFO_OFFS) do
                local b = follow_ptr(a, o2)
                if b ~= nil then
                    if quest_timer_at(b, PL_DIE_COUNT_MAX_OFF) then
                        return b, MAX_DEATHS_OFF
                    end
                    local b0 = decode_at(b, MAX_DEATHS_OFF)
                    if is_normal_cart_cap(b0) then
                        return b, MAX_DEATHS_OFF
                    end
                end
            end
        end
    end
    return nil, nil
end

local function is_quest_timer_float(n)
    return type(n) == "number"
        and ((n >= 1500 and n <= 4000) or (n >= 30000 and n <= 4.0e7))
end

local scan3_logs = 0
local function scan_enc3(obj, tag)
    if obj == nil or type(obj) ~= "userdata" then
        return
    end
    local sz = 0x180
    pcall(function()
        local n = obj:get_type_definition():get_size()
        if type(n) == "number" and n >= 0x40 and n <= 0x800 then
            sz = n
        end
    end)
    local hits = {}
    local off = 0
    while off + 24 <= sz do
        local a0, div = decode_at(obj, off)
        if is_normal_cart_cap(a0) then
            local t = read_float(obj, off + 0x18)
            local m = read_float(obj, off + 0x1C)
            hits[#hits + 1] = string.format("%X=%s", off, tostring(a0))
            if is_quest_timer_float(t) or is_quest_timer_float(m) then
                if write_encrypted_at(obj, off, TARGET) then
                    state.info_max_deaths = TARGET
                    info("scan-md " .. tostring(tag) .. " " .. string.format("%X", off) .. " " .. tostring(a0) .. "->99")
                end
            end
        end
        off = off + 8
    end
    if scan3_logs < 8 then
        scan3_logs = scan3_logs + 1
        if #hits > 0 then
            state.raw_qinfo_diag = tostring(tag) .. ":" .. table.concat(hits, ",")
            info("scan3 " .. tostring(tag) .. " " .. table.concat(hits, ","))
        else
            info("scan3 " .. tostring(tag) .. " none sz=" .. tostring(sz))
        end
    end
end

local late_dir_dumped = false
local function dump_dir_ptrs(qd)
    if qd == nil then
        return
    end
    local flow = type_name(try_get_field(qd, "_CurFlow")) or ""
    if flow:find("Loading", 1, true) then
        return
    end
    if late_dir_dumped then
        return
    end
    late_dir_dumped = true
    write_keep_quest_life()
    local parts = {}
    for _, o1 in ipairs(DIR_INFO_OFFS) do
        local a = follow_ptr(qd, o1)
        if a ~= nil then
            parts[#parts + 1] = string.format(
                "%X:%s a0=%s t=%s",
                o1,
                tostring(type_name(a)),
                tostring(decode_at(a, MAX_DEATHS_OFF)),
                tostring(read_float(a, PL_DIE_COUNT_MAX_OFF))
            )
        end
    end
    info("late-dir " .. table.concat(parts, ";"))
    info("flow-type " .. flow)
    info("die-now " .. tostring(decode_mandrake(try_get_field(qd, "QuestPlDieCount"))))
    local fparts = {}
    each_instance_field(qd, function(fname)
        local child = try_get_field(qd, fname)
        if type(child) == "userdata" then
            local a0 = decode_at(child, MAX_DEATHS_OFF)
            fparts[#fparts + 1] = fname .. ":" .. tostring(type_name(child)) .. " a0=" .. tostring(a0)
            if is_max_deaths_blob(child) then
                info("late-a0 " .. fname .. " " .. tostring(a0))
            end
        end
    end)
    info("late-fields " .. table.concat(fparts, ";"))
    local pnames = {}
    local param = try_get_field(qd, "<Param>k__BackingField") or try_get_field(qd, "Param")
    each_instance_field(param, function(fname)
        local v = try_get_field(param, fname)
        pnames[#pnames + 1] = fname
            .. ":"
            .. tostring(type_name(v) or type(v))
            .. "="
            .. tostring(decode_mandrake(v) or life_num(v) or "")
    end)
    info("flow-fields " .. table.concat(pnames, ","))
    info("remain " .. tostring(try_call(qd, "get_QuestRemainTime()")))
    local active = try_get_field(qd, "_QuestData")
    local catalog = nil
    if active ~= nil then
        catalog = try_get_field(active, "_QuestData")
    end
    info(
        "late-qd "
            .. tostring(type_name(active))
            .. " cat="
            .. tostring(type_name(catalog))
            .. " life="
            .. tostring(read_quest_life(catalog) or read_quest_life(active))
    )
    local flowobj = try_get_field(qd, "_CurFlow")
    local nest = {}
    for _, o2 in ipairs(NEST_INFO_OFFS) do
        local b = follow_ptr(flowobj, o2)
        local raw = read_qword(flowobj, o2)
        if b ~= nil then
            local a0 = decode_at(b, MAX_DEATHS_OFF)
            local t = read_float(b, PL_DIE_COUNT_MAX_OFF)
            local m = read_float(b, PL_DIE_COUNT_MAX_OFF + 4)
            nest[#nest + 1] = string.format(
                "%X:%s a0=%s t=%s m=%s",
                o2,
                tostring(type_name(b) or "blob"),
                tostring(a0),
                tostring(t),
                tostring(m)
            )
            if is_normal_cart_cap(a0) and quest_timer_at(b, PL_DIE_COUNT_MAX_OFF) then
                state.blob_obj = b
                info("blob-hit " .. string.format("%X", o2))
            end
        elseif raw ~= nil and raw ~= 0 then
            local ba = nil
            pcall(function()
                ba = flowobj:get_address()
            end)
            local a0 = nil
            local div = nil
            local t = nil
            local m = nil
            local rel = nil
            if type(ba) == "number" then
                rel = raw - ba
                local value = read_qword(flowobj, rel + MAX_DEATHS_OFF)
                div = read_qword(flowobj, rel + MAX_DEATHS_OFF + 8)
                if type(value) == "number" and type(div) == "number" and div ~= 0 then
                    a0 = math.floor(value / div)
                end
                t = read_float(flowobj, rel + PL_DIE_COUNT_MAX_OFF)
                m = read_float(flowobj, rel + PL_DIE_COUNT_MAX_OFF + 4)
            end
            nest[#nest + 1] = string.format(
                "%X:rel a0=%s t=%s m=%s",
                o2,
                tostring(a0),
                tostring(t),
                tostring(m)
            )
            if is_normal_cart_cap(a0) and type(m) == "number" and m >= 30000 and m <= 3.0e7 then
                state.blob_base = flowobj
                state.blob_rel = rel
                state.blob_div = div
                info("blob-hit " .. string.format("%X", o2))
            end
        end
    end
    info("flow-nest " .. table.concat(nest, ";"))
    scan_enc3(qd, "dir")
    scan_enc3(flowobj, "flow")
    scan_enc3(param, "param")
    scan_enc3(active, "active")
    if active ~= nil then
        scan_enc3(try_get_field(active, "_KeepQuestData"), "keep")
    end
    local before = try_get_field(qd, "_QuestBeforeStage")
    info(
        "before-stage "
            .. tostring(type_name(before))
            .. " life="
            .. tostring(read_quest_life(before))
    )
    local sparts = {}
    for _, stn in ipairs({
        "app.cKeepQuestData",
        "app.cActiveQuestData",
        "app.QuestDef",
        "app.QuestDefine",
        "app.QuestUtil",
    }) do
        local std = sdk.find_type_definition(stn)
        local sfields = nil
        if std ~= nil then
            pcall(function()
                sfields = std:get_fields()
            end)
        end
        if sfields ~= nil then
            for _, field in ipairs(sfields) do
                local sn = nil
                local isst = false
                pcall(function()
                    isst = field:is_static()
                    sn = field:get_name()
                end)
                if isst and sn ~= nil then
                    local sv = nil
                    pcall(function()
                        sv = field:get_data(nil)
                    end)
                    local n = life_num(sv)
                    sparts[#sparts + 1] = sn .. "=" .. tostring(n or sv)
                end
            end
        end
    end
    info("static " .. table.concat(sparts, ","))
end

local function write_encrypted_at(object, offset, target)
    local current, divisor = decode_at(object, offset)
    if current == target then
        return true
    end
    -- 1.7.60: writing when current is 0 (or inventing divisor at +8) crashed quest load.
    if not is_normal_cart_cap(current) or divisor == nil or divisor == 0 then
        return false
    end
    return write_qword(object, offset, target * divisor) and decode_at(object, offset) == target
end

-- Returns object, max-deaths offset. Identify CurrentInformation by its timer floats,
-- not by MaxDeaths already decoding to 1-30 (investigations often fail that check).
local function find_info_target()
    local seen = {}
    local function consider(object)
        if object == nil or type(object) ~= "userdata" then
            return nil, nil
        end
        local id = object_id(object)
        if id ~= nil and seen[id] then
            return nil, nil
        end
        if id ~= nil then
            seen[id] = true
        end
        if quest_timer_at(object, PL_DIE_COUNT_MAX_OFF) then
            return object, MAX_DEATHS_OFF
        end
        if quest_timer_at(object, 0x18 + PL_DIE_COUNT_MAX_OFF) then
            return object, 0x18 + MAX_DEATHS_OFF
        end
        if is_max_deaths_blob(object) then
            return object, MAX_DEATHS_OFF
        end
        return nil, nil
    end
    local function walk_fields(object)
        local hit, off = consider(object)
        if hit ~= nil then
            return hit, off
        end
        local typedef = nil
        pcall(function()
            typedef = object:get_type_definition()
        end)
        local fields = nil
        if typedef ~= nil then
            pcall(function()
                fields = typedef:get_fields()
            end)
        end
        if fields == nil then
            return nil, nil
        end
        for _, field in ipairs(fields) do
            local fname = nil
            pcall(function()
                if not field:is_static() then
                    fname = field:get_name()
                end
            end)
            if fname ~= nil then
                local child = try_get_field(object, fname)
                if type(child) == "userdata" and not is_index_list(child) then
                    hit, off = consider(child)
                    if hit ~= nil then
                        return hit, off
                    end
                    hit, off = consider(follow_ptr(child, 0x18))
                    if hit ~= nil then
                        return hit, off
                    end
                    hit, off = consider(follow_ptr(child, 0x38))
                    if hit ~= nil then
                        return hit, off
                    end
                end
            end
        end
        return nil, nil
    end
    local mission = get_mission_manager()
    local roots = {
        live_director(),
        follow_ptr(mission, 0x178),
        follow_ptr(mission, 0x168),
        follow_ptr(mission, 0x158),
        follow_ptr(mission, 0x188),
    }
    for _, root in ipairs(roots) do
        local hit, off = walk_fields(root)
        if hit ~= nil then
            return hit, off
        end
        hit, off = consider(current_quest_information(root))
        if hit ~= nil then
            return hit, off
        end
    end
    return nil, nil
end

local function find_current_info()
    local object, offset = find_info_target()
    if object == nil then
        return nil
    end
    if offset == MAX_DEATHS_OFF then
        return object
    end
    return object
end

local function write_max_deaths_only(param, target, offset)
    offset = offset or MAX_DEATHS_OFF
    if write_encrypted_at(param, offset, target) then
        return true, string.format("MaxDeaths@0x%X", offset)
    end
    return false, nil
end

local function read_pl_die_count_max(param)
    for _, name in ipairs(MANDRAKE_NAMES) do
        local current = decode_mandrake(try_get_field(param, name))
        if type(current) == "number" then
            return current, name, nil
        end
    end
    local current, divisor = decode_at(param, PL_DIE_COUNT_MAX_OFF)
    if current ~= nil then
        return current, "PlDieCountMax@0xB8", divisor
    end
    current, divisor = decode_at(param, MAX_DEATHS_OFF)
    if current ~= nil then
        return current, "MaxDeaths@0xA0", divisor
    end
    return nil, nil, nil
end

local function write_pl_die_count_max(param, target)
    local wrote = false
    local path = nil
    for _, name in ipairs(MANDRAKE_NAMES) do
        local enc = try_get_field(param, name)
        if enc ~= nil then
            local current = decode_mandrake(enc)
            if current == target then
                wrote = true
                path = name
            elseif is_normal_cart_cap(current) and write_mandrake(enc, target) then
                try_set_field(param, name, enc)
                if decode_mandrake(try_get_field(param, name)) == target then
                    wrote = true
                    path = name
                end
            end
        end
    end
    if not quest_timer_at(param, PL_DIE_COUNT_MAX_OFF) then
        for _, spec in ipairs({
            { PL_DIE_COUNT_MAX_OFF, "PlDieCountMax@0xB8" },
        }) do
            local current, divisor = decode_at(param, spec[1])
            if current == target then
                wrote = true
                if path == nil then
                    path = spec[2]
                end
            elseif is_normal_cart_cap(current) and divisor ~= nil then
                if write_qword(param, spec[1], target * divisor)
                    and decode_at(param, spec[1]) == target
                then
                    wrote = true
                    path = spec[2]
                end
            end
        end
    end
    return wrote, path
end

-- Prefer MissionManager flags (CatLib signatures). Do not use QuestLife<=30
-- as the session check: after we write 99 that predicate goes false.
local function quest_session_active()
    local mission = get_mission_manager()
    if mission == nil then
        return nil
    end
    ensure_mission_api()
    local playing = call_method(m_get_playing, mission)
        or try_call(mission, "get_IsPlayingQuest()")
        or try_call(mission, "get_IsPlayingQuest")
    local active = call_method(m_get_active, mission)
        or try_call(mission, "get_IsActiveQuest()")
        or try_call(mission, "get_IsActiveQuest")
    if flag_true(playing) or flag_true(active) then
        return true
    end
    if flag_false(playing) or flag_false(active) then
        return false
    end
    return nil
end

local function params_have_cap(qd)
    for _, param in ipairs(collect_params(qd)) do
        local current = read_pl_die_count_max(param)
        if is_normal_cart_cap(current) or current == TARGET then
            return true
        end
    end
    return false
end

local function quest_data_has_cap(qd)
    for _, data in ipairs(collect_quest_data(qd)) do
        local life = read_quest_life(data)
        if is_normal_cart_cap(life) or life == TARGET then
            return true
        end
    end
    return false
end

local late_qd_logs = 0
local function raise_ui_quest_life(qd)
    local copies = collect_quest_data(qd)
    if #copies == 0 then
        return false
    end
    local any_ok = false
    local all_ok = true
    local saw_value = false
    for _, data in ipairs(copies) do
        apply_set_life(data)
        local nested = try_get_field(data, "_KeepQuestData") or try_get_field(data, "KeepQuestData")
        apply_set_life(nested)
        local value = read_quest_life(data)
        if late_qd_logs < 3 and value ~= nil then
            late_qd_logs = late_qd_logs + 1
            info("late-qd " .. tostring(type_name(data)) .. " life=" .. tostring(value))
        end
        if value == TARGET then
            any_ok = true
            saw_value = true
        elseif is_normal_cart_cap(value) then
            saw_value = true
            if write_quest_life(data, TARGET) then
                state.writes = state.writes + 1
                state.last_path = "QuestData._QuestLife"
                set_status("QuestLife set to 99.", state.last_path)
                any_ok = true
            else
                all_ok = false
            end
        end
    end
    if any_ok and all_ok then
        state.ui_life = TARGET
        return true
    end
    if saw_value then
        state.ui_life = any_ok and TARGET or nil
    end
    return any_ok and all_ok
end

local function raise_pl_die_count_max(qd)
    if accept_frame > 0 and state.frame >= accept_frame + 60 then
        dump_dir_ptrs(qd)
        if state.blob_base ~= nil and state.blob_rel ~= nil and state.blob_div ~= nil then
            if write_qword(
                state.blob_base,
                state.blob_rel + MAX_DEATHS_OFF,
                TARGET * state.blob_div
            ) then
                state.info_max_deaths = TARGET
                info("blob-wrote")
            end
        elseif state.blob_obj ~= nil then
            if write_encrypted_at(state.blob_obj, MAX_DEATHS_OFF, TARGET) then
                state.info_max_deaths = TARGET
                info("blob-wrote")
            end
        end
    end
    local any_ok = false
    local all_ok = true
    local saw_cap = false
    if qd ~= nil then
        for _, param in ipairs(collect_params(qd)) do
            local current, path = read_pl_die_count_max(param)
            if current == TARGET or is_normal_cart_cap(current) then
                saw_cap = true
                local ok, written_path = write_pl_die_count_max(param, TARGET)
                if ok then
                    any_ok = true
                    state.last_path = "Param." .. tostring(written_path or path)
                    if current ~= TARGET then
                        state.writes = state.writes + 1
                        set_status("PlDieCountMax set to 99.", string.format("%s (was %d)", state.last_path, current))
                    end
                else
                    all_ok = false
                end
            end
        end
    end
    local qinfo, qoff = find_info_target()
    if qinfo == nil and qd ~= nil then
        local qobj = current_quest_information(qd)
        local a0 = decode_at(qobj, MAX_DEATHS_OFF)
        if qinfo_logs < 3 then
            qinfo_logs = qinfo_logs + 1
            local t = nil
            local m = nil
            if qobj ~= nil then
                t = read_float(qobj, PL_DIE_COUNT_MAX_OFF)
                m = read_float(qobj, PL_DIE_COUNT_MAX_OFF + 4)
            end
            info("qinfo " .. tostring(type_name(qobj)) .. " t=" .. tostring(t) .. " m=" .. tostring(m) .. " a0=" .. tostring(a0))
        end
        if is_normal_cart_cap(a0) then
            qinfo = qobj
            qoff = MAX_DEATHS_OFF
        else
            qinfo, qoff = scan_quest_info(qd)
            if qinfo ~= nil and qinfo_logs <= 3 then
                info("qscan a0=" .. tostring(decode_at(qinfo, qoff)))
            end
        end
    end
    if qinfo == nil and a0_skip_logs < 2 then
        a0_skip_logs = a0_skip_logs + 1
        info("skip-a0 no-info")
    end
    if qinfo ~= nil then
        local before = decode_at(qinfo, qoff)
        state.info_max_deaths = before
        if before ~= TARGET and not is_normal_cart_cap(before) and a0_skip_logs < 2 then
            a0_skip_logs = a0_skip_logs + 1
            info("skip-a0 cur=" .. tostring(before))
        end
        if before == TARGET or is_normal_cart_cap(before) then
            local ok, written_path = write_max_deaths_only(qinfo, TARGET, qoff)
            if ok then
                state.info_max_deaths = TARGET
                any_ok = true
                saw_cap = true
                state.last_path = "Param." .. tostring(written_path)
                if before ~= TARGET then
                    state.writes = state.writes + 1
                    set_status("PlDieCountMax set to 99.", string.format("%s (was %d)", state.last_path, before))
                end
            else
                all_ok = false
                saw_cap = true
            end
        end
    end
    if any_ok and all_ok then
        state.max_deaths = TARGET
        return true
    end
    if saw_cap then
        state.max_deaths = (any_ok and all_ok) and TARGET or nil
    end
    return any_ok and all_ok
end

local function read_deaths(qd)
    local n = decode_mandrake(try_get_field(qd, "QuestPlDieCount"))
        or decode_mandrake(try_get_field(qd, "_QuestPlDieCount"))
    if n ~= nil then
        state.deaths = n
    end
end

local function clear_quest_state()
    state.ui_life = nil
    state.max_deaths = nil
    state.deaths = nil
    state.last_path = ""
    state.cached_qd = nil
    state.blob_obj = nil
    state.blob_base = nil
    state.blob_rel = nil
    state.blob_div = nil
    late_dir_dumped = false
end

local function director_has_cap(qd)
    local obj = find_info_target()
    if obj ~= nil then
        return true
    end
    if qd == nil then
        return false
    end
    if quest_data_has_cap(qd) or params_have_cap(qd) then
        return true
    end
    local nested = current_quest_information(qd)
    if nested == nil then
        return false
    end
    local n = decode_at(nested, MAX_DEATHS_OFF)
    return is_normal_cart_cap(n) or n == TARGET
end

local function maintain(force_peek)
    local session = quest_session_active()
    local qd = live_director()
    if qd == nil and session ~= false then
        qd = get_quest_director()
    end
    if qd ~= nil then
        state.cached_qd = qd
    elseif state.in_quest and state.cached_qd ~= nil and not force_peek then
        qd = state.cached_qd
        session = true
    elseif force_peek then
        qd = get_quest_director()
        if director_has_cap(qd) then
            session = true
            state.cached_qd = qd
        else
            qd = nil
        end
    end
    -- Live hunt only if the quest timer struct exists. FlowParam at the
    -- quest counter is not an in-quest session.
    if session == false then
        local timer_info = find_info_target()
        if timer_info ~= nil then
            session = true
        end
    end
    if session == false or qd == nil or (session == nil and find_info_target() == nil) then
        state.in_quest = false
        clear_quest_state()
        patch_board_from_mission()
        set_status("Waiting for quest.", catalog_status_detail())
        return
    end

    state.in_quest = true
    state.ui_life = nil
    state.max_deaths = nil

    raise_ui_quest_life(qd)
    raise_pl_die_count_max(qd)
    read_deaths(qd)

    if state.info_max_deaths == TARGET then
        set_status(
            "OK: faint cap 99.",
            string.format("%s; deaths=%s", state.last_path, tostring(state.deaths or 0))
        )
    elseif state.max_deaths == TARGET then
        set_status("FlowParam 99; hunt HUD not updated.", state.hunt_diag)
    elseif state.ui_life == TARGET then
        set_status("QuestLife=99; hunt HUD not updated.", state.last_path)
    else
        set_status("Applying faint cap...")
    end
end

local function update()
    state.frame = state.frame + 1
    -- sdk.hook is async (~17ms). Install after the game loop starts, never in
    -- fail_life_pre (1.7.51: native hook landed after the original already ran).
    -- Not at script parse time (1.7.15 black screen).
    if not msg_get_hooked and state.frame >= 120 then
        pcall(ensure_msg_get_hook)
    end
    if msg_get_hooked and pull_n < 1 and state.frame >= 180 then
        pcall(pull_faint_template)
    end
    -- 1.7.68: returning here skipped maintain after accept, so MaxDeaths
    -- created during scene load was never written.
    if state.frame % IDLE_INTERVAL ~= 0 then
        return
    end
    local ok, err = pcall(maintain)
    if not ok then
        set_status("Error.", tostring(err):gsub("[\r\n]+", " "))
    end
end

local function try_hook(type_name, method_name, pre)
    local typedef = sdk.find_type_definition(type_name)
    if typedef == nil then
        return
    end
    local method = typedef:get_method(method_name)
    if method == nil then
        return
    end
    pcall(function()
        sdk.hook(method, pre or function(_args)
        end, function(retval)
            local ok, err = pcall(maintain, true)
            if not ok then
                set_status("Error.", tostring(err):gsub("[\r\n]+", " "))
            end
            return retval
        end)
    end)
end

if reframework == nil or reframework:get_game_name() ~= "mhwilds" then
    return
end
-- Hook-install locals must not live in the main chunk (Lua 200-local limit, 1.7.71).
local function dump_named_methods(tn)
    local td = sdk.find_type_definition(tn)
    if td == nil then
        return
    end
    local methods = nil
    pcall(function()
        methods = td:get_methods()
    end)
    if methods == nil then
        return
    end
    local names = {}
    for _, method in ipairs(methods) do
        local n = nil
        pcall(function()
            n = method:get_name()
        end)
        if n ~= nil then
            local l = n:lower()
            if l:find("die", 1, true)
                or l:find("life", 1, true)
                or l:find("fail", 1, true)
                or l:find("count", 1, true)
            then
                names[#names + 1] = n
            end
        end
    end
    if #names > 0 then
        info("api " .. tn .. " " .. table.concat(names, ","))
    end
end

local function dump_all_methods(tn)
    local td = sdk.find_type_definition(tn)
    if td == nil then
        info("api-all " .. tn .. " missing")
        return
    end
    local methods = nil
    pcall(function()
        methods = td:get_methods()
    end)
    if methods == nil then
        return
    end
    local names = {}
    local i = 1
    while i <= #methods and #names < 40 do
        local n = nil
        pcall(function()
            n = methods[i]:get_name()
        end)
        if n ~= nil then
            names[#names + 1] = n
        end
        i = i + 1
    end
    info("api-all " .. tn .. " n=" .. tostring(#methods) .. " " .. table.concat(names, ","))
end

local function install()
info("loaded " .. SCRIPT_VERSION)
pcall(function()
    dump_named_methods("app.QuestUtil")
    dump_named_methods("app.GUI050100QuestDetail")
    dump_named_methods("app.cGUIQuestViewData")
    dump_all_methods("app.GUI050100")
    dump_all_methods("app.GUIManager")
    dump_all_methods("ace.GUIManager")
    dump_all_methods("app.GUI080000")
    dump_all_methods("app.GUI080100")
    dump_all_methods("app.cGUIContext")
    dump_named_methods("app.GUIBase")
    dump_named_methods("ace.gui.GUIBase")
    pcall(function()
        local td = sdk.find_type_definition("app.cGUIContext")
        local fields = td:get_fields()
        local names = {}
        for _, field in ipairs(fields) do
            pcall(function()
                if not field:is_static() then
                    names[#names + 1] = field:get_name() .. ":" .. field:get_type():get_full_name()
                end
            end)
        end
        info("ctx-fields " .. table.concat(names, ","))
    end)
    pcall(function()
        local td = sdk.find_type_definition("System.Byte")
        local fields = td:get_fields()
        local names = {}
        for _, field in ipairs(fields) do
            names[#names + 1] = field:get_name()
        end
        info("byte-fields " .. table.concat(names, ","))
    end)
    local found = {}
    local function scan(a, b)
        local i = a
        while i <= b do
            local n = string.format("app.GUI%06d", i)
            if sdk.find_type_definition(n) ~= nil then
                found[#found + 1] = n
                dump_named_methods(n)
            end
            i = i + 1
        end
    end
    scan(10000, 10200)
    scan(20000, 20150)
    scan(50000, 50200)
    scan(80000, 80200)
    state.gui_found = found
    if #found > 0 then
        info("gui-types " .. table.concat(found, ","))
    end
end)
write_keep_quest_life()
do
    for _, tn in ipairs({ "app.cKeepQuestData", "app.cActiveQuestData" }) do
        local td = sdk.find_type_definition(tn)
        local names = {}
        local methods = nil
        if td ~= nil then
            pcall(function()
                methods = td:get_methods()
            end)
        end
        if methods ~= nil then
            for _, method in ipairs(methods) do
                pcall(function()
                    local n = method:get_name()
                    if n:lower():find("life", 1, true) then
                        names[#names + 1] = n
                    end
                end)
            end
        end
        info("life-api " .. tn .. " " .. table.concat(names, ","))
    end
end

-- Apply immediately when investigation/static quests copy params onto the live session.
try_hook("app.cQuestDirector", "acceptQuest(app.cActiveQuestData, app.cQuestAcceptArg, System.Boolean, System.Boolean)", accept_pre)
try_hook("app.cQuestStart", "enter()", accept_pre)
try_hook("app.cQuestPlaying", "enter()", accept_pre)
do
    local td = sdk.find_type_definition("app.cQuestDirector")
    local methods = nil
    if td ~= nil then
        pcall(function()
            methods = td:get_methods()
        end)
    end
    if methods ~= nil then
        for _, method in ipairs(methods) do
            local name = nil
            pcall(function()
                name = method:get_name()
            end)
            if name ~= nil then
                local lower = name:lower()
                if lower:find("acceptquest", 1, true)
                    or lower:find("startquest", 1, true)
                    or lower:find("entryquest", 1, true)
                    or lower:find("orderquest", 1, true)
                then
                    pcall(function()
                        sdk.hook(method, accept_pre, function(retval)
                            local ok, err = pcall(maintain, true)
                            if not ok then
                                set_status("Error.", tostring(err):gsub("[\r\n]+", " "))
                            end
                            return retval
                        end)
                    end)
                end
            end
        end
    end
end
hook_board_readers()
do
    local detail_logs = 0
    local function patch_detail(obj, tag)
        if obj == nil or type(obj) ~= "userdata" then
            return
        end
        local wrote = 0
        local parts = {}
        each_instance_field(obj, function(fname, field)
            if #parts >= 20 then
                return
            end
            local v = try_get_field(obj, fname)
            local n = life_num(v)
            parts[#parts + 1] = fname .. "=" .. tostring(n or type_name(v) or type(v))
            local lower = fname:lower()
            if (lower:find("life", 1, true) or lower:find("die", 1, true) or lower:find("fail", 1, true) or lower:find("count", 1, true))
                and is_normal_cart_cap(n)
            then
                if try_set_field(obj, fname, TARGET) then
                    wrote = wrote + 1
                end
            end
            if type_name(v) == "ace.cGUIMessageInfo" then
                patch_msginfo(v)
            end
        end)
        if detail_logs < 8 then
            detail_logs = detail_logs + 1
            info("detail " .. tostring(tag) .. " t=" .. tostring(type_name(obj)) .. " w=" .. tostring(wrote) .. " " .. table.concat(parts, ","))
        end
        if wrote > 0 then
            state.hunt_diag = "detail w=" .. tostring(wrote)
        end
    end
    local function detail_post(retval)
        if hunt_playing() then
            local obj = retval
            pcall(function()
                local m = sdk.to_managed_object(retval)
                if m ~= nil then
                    obj = m
                end
            end)
            patch_detail(obj, "det")
        end
        return retval
    end
    pcall(function()
        local found = state.gui_found or { "app.GUI050100" }
        local hooked = 0
        for _, n in ipairs(found) do
            local td = sdk.find_type_definition(n)
            local methods = nil
            if td ~= nil then
                pcall(function()
                    methods = td:get_methods()
                end)
            end
            if methods ~= nil then
                for _, method in ipairs(methods) do
                    local name = nil
                    pcall(function()
                        name = method:get_name()
                    end)
                    if name == "onOpenApp" then
                        sdk.hook(method, function(args)
                            if not hunt_playing() then
                                return
                            end
                            local this = managed_arg(args[2])
                            info("gui-open " .. n)
                            patch_detail(this, n)
                        end, pass_retval)
                        hooked = hooked + 1
                    elseif name == "get__QuestDetail" then
                        sdk.hook(method, function() end, detail_post)
                    end
                end
            end
        end
        info("hook onOpenApp n=" .. tostring(hooked))
    end)
end
do
    local util_types = {
        "app.QuestUtil",
        "app.cQuestUtil",
        "app.QuestDataUtil",
        "app.GUIUtilApp.QuestUtil",
        "app.cQuestDirector",
        "app.cActiveQuestData",
        "app.GUI050100",
        "app.GUI050100QuestDetail",
        "app.GUI050000QuestListParts",
        "app.cGUIQuestViewData",
        "app.cKeepQuestData",
    }
    for _, type_name in ipairs(util_types) do
        local td = sdk.find_type_definition(type_name)
        local methods = nil
        if td ~= nil then
            pcall(function()
                methods = td:get_methods()
            end)
        end
        if methods ~= nil then
            for _, method in ipairs(methods) do
                local name = nil
                pcall(function()
                    name = method:get_name()
                end)
                if name ~= nil then
                    local lower = name:lower()
                    if lower:find("questlife", 1, true)
                        or lower:find("failcond", 1, true)
                        or lower:find("keepquest", 1, true)
                        or lower:find("questtext", 1, true)
                        or lower:find("diecount", 1, true)
                        or lower:find("pldie", 1, true)
                    then
                        local rtn = nil
                        pcall(function()
                            rtn = method:get_return_type():get_full_name()
                        end)
                        local pre = board_pre_hook
                        local post = pass_retval
                        if name == "get_QuestLife" then
                            pre = life_get_pre
                            post = life_get_post
                        elseif lower:find("convertsavedata2keepquest", 1, true)
                            or lower:find("createkeepquest", 1, true)
                        then
                            pre = keep_build_pre
                            post = keep_build_post
                        elseif rtn == "ace.cGUIMessageInfo" then
                            pre = wrap_fail_pre(type_name .. "." .. name)
                            post = fail_life_post
                        end
                        pcall(function()
                            sdk.hook(method, pre, post)
                        end)
                        info("hook " .. type_name .. "." .. name .. " -> " .. tostring(rtn))
                    end
                end
            end
        end
    end
end
pcall(patch_board_from_mission)

if re.on_pre_gui_draw_element ~= nil then
    local draw_logs = 0
    re.on_pre_gui_draw_element(function(element, _)
        if element == nil then
            return true
        end
        local tn = nil
        pcall(function()
            tn = element:get_type_definition():get_name()
        end)
        local msg = try_call(element, "get_Message()") or try_call(element, "get_Text()")
        local mtn = type_name(msg)
        if mtn == "ace.cGUIMessageInfo" then
            pcall(patch_msginfo, msg)
            if draw_logs < 8 then
                draw_logs = draw_logs + 1
                info("draw-msginfo " .. tostring(tn) .. " " .. tostring(to_text(msg)))
            end
        end
        local s = to_text(msg)
        if type(s) ~= "string" then
            return true
        end
        if s:find("倒下", 1, true) or s:find("/3", 1, true) then
            if draw_logs < 8 then
                draw_logs = draw_logs + 1
                info("draw-hud " .. tostring(tn) .. " " .. s:sub(1, 48))
            end
        end
        if s:find("/3", 1, true) then
            local n = s:gsub("/3", "/99")
            pcall(function()
                element:call("set_Message", sdk.create_managed_string(n))
            end)
            pcall(function()
                element:call("set_Text", sdk.create_managed_string(n))
            end)
        elseif s:find("力尽倒下", 1, true) then
            pcall(mutate_faint_string, msg, s)
        end
        return true
    end)
end

re.on_frame(update)

local dumped_once = false
local function dump_once(dir, qinfo, qoff)
    if dumped_once then
        return
    end
    dumped_once = true
    local names = {}
    if dir ~= nil then
        pcall(function()
            local fields = dir:get_type_definition():get_fields()
            for _, field in ipairs(fields) do
                pcall(function()
                    if not field:is_static() then
                        names[#names + 1] = field:get_name()
                    end
                end)
            end
        end)
    end
    local payload = {
        version = SCRIPT_VERSION,
        director = type_name(dir),
        info = type_name(qinfo),
        offset = qoff,
        maxdeaths = (qinfo ~= nil and qoff ~= nil) and decode_at(qinfo, qoff) or nil,
        fields = names,
    }
    info(string.format(
        "dump director=%s info=%s off=%s max=%s fields=%s",
        tostring(payload.director),
        tostring(payload.info),
        tostring(payload.offset),
        tostring(payload.maxdeaths),
        table.concat(names, ",")
    ))
end

if re.on_application_entry ~= nil then
    local function pulse()
        local dir = live_director()
        local qinfo, qoff = find_info_target()
        local session = quest_session_active()
        if qinfo ~= nil and qoff ~= nil then
            state.info_max_deaths = decode_at(qinfo, qoff)
        end
        if session == false and qinfo == nil then
            return
        end
        dump_once(dir, qinfo, qoff)
        local ok, err = pcall(function()
            raise_pl_die_count_max(dir)
            if dir ~= nil then
                raise_ui_quest_life(dir)
            end
        end)
        if not ok then
            set_status("Error.", tostring(err):gsub("[\r\n]+", " "))
        end
    end
    re.on_application_entry("LateUpdateBehavior", pulse)
    re.on_application_entry("EndRendering", function()
        if not state.in_quest then
            return
        end
        local qinfo, qoff = find_info_target()
        if qinfo ~= nil then
            pcall(write_max_deaths_only, qinfo, TARGET, qoff)
        end
    end)
end

re.on_script_reset(function()
    state.frame = 0
    state.status = "Script reset."
    state.detail = ""
    state.writes = 0
    state.catalog_writes = 0
    state.in_quest = false
    clear_quest_state()
end)

re.on_draw_ui(function()
    if not imgui.tree_node(MOD_NAME) then
        return
    end
    imgui.text("Version: " .. SCRIPT_VERSION)
    imgui.text("Target faint cap: " .. tostring(TARGET))
    imgui.text("Static QUEST_LIFE: " .. tostring(state.static_life) .. " lit=" .. tostring(state.static_lit))
    imgui.text("Hunt: " .. (state.hunt_diag ~= "" and state.hunt_diag or "open quest info in-hunt"))
    imgui.text("Status: " .. state.status)
    if state.detail ~= "" then
        imgui.text("Detail: " .. state.detail)
    end
    imgui.text("Writes: " .. tostring(state.writes))
    imgui.text("Quest list writes: " .. tostring(state.catalog_writes))
    imgui.text("FailLife: " .. tostring(state.fail_life_diag))
    imgui.text("GetHits: " .. tostring(get_hits) .. " mutate=" .. tostring(mutate_logs))
    local c = 0
    for _ in pairs(state.msg_ids) do
        c = c + 1
    end
    if c > 0 then
        imgui.text("MsgIds: " .. tostring(c))
    end
    if state.msg_id_dump ~= "" then
        imgui.text(state.msg_id_dump)
    end
    imgui.text("Fmt: add=" .. tostring(state.fmt_add)
        .. " pts=" .. tostring(state.fmt_pts)
        .. " str=" .. tostring(state.fmt_str)
        .. " rewrote=" .. tostring(state.fmt_rewrote))
    if state.fmt_dump ~= "" then
        imgui.text("Dump: " .. state.fmt_dump)
    end
    if state.fmt_sig ~= "" then
        imgui.text("FmtSig: " .. state.fmt_sig)
    end
    imgui.text("ParamUnion: " .. UNION_FIELD_LOG)
    if state.info_max_deaths ~= nil then
        imgui.text("MaxDeaths@0xA0: " .. tostring(state.info_max_deaths))
    end
    if state.board_types ~= "" then
        imgui.text("Board: " .. state.board_types)
    end
    if state.ui_life ~= nil then
        imgui.text("QuestLife: " .. tostring(state.ui_life))
    end
    if state.max_deaths ~= nil then
        imgui.text("PlDieCountMax: " .. tostring(state.max_deaths))
    end
    if state.deaths ~= nil then
        imgui.text("Deaths: " .. tostring(state.deaths))
    end
    if state.last_path ~= "" then
        imgui.text("Path: " .. state.last_path)
    end
    imgui.tree_pop()
end)
end
install()
