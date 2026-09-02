---@diagnostic disable: undefined-global

-- Easier Hunting retries: faint cap 99 (list + in-quest HUD + wipe).
-- 倒下上限 99（任务列表 + 任务内 HUD + 团灭上限）。
-- Written entirely by AI; published after human verification.
-- 完全由 AI 编写，经人工验证后发布。
-- List: makeParamData post writes ParamValue 3 or 5 to 99 (1.7.60).
-- HUD: Playing-only get_QuestLife to_ptr(99) if pointer bits are 99 (1.7.93).
-- Wipe: FlowParam PlDieCountMax @ 0xB8 when decode is 1-30.
-- Bans: QUEST_LIFE_LESSONS.md. Never call hooked get_QuestLife. Never write MaxDeaths@0xA0.

local sdk = sdk
local re = re
local imgui = imgui
local reframework = reframework
local log = log

local MOD_NAME = "Easier Hunting: Quest Life | 倒下次数"
local SCRIPT_VERSION = "1.7.96"
local TARGET = 99
local IDLE_INTERVAL = 60
local B8 = 0xB8
local CAP_MIN = 1
local CAP_MAX = 30

local PARAM_FIELDS = {
    "<Param>k__BackingField",
    "Param",
    "_Param",
    "FlowParam",
    "_FlowParam",
    "_QuestFlowParam",
    "_CurFlow",
}
local PARAM_GETTERS = { "get_Param()", "get_Param", "get_FlowParam()", "get_FlowParam" }
local MANDRAKE_NAMES = {
    "PlDieCountMax",
    "_PlDieCountMax",
    "<PlDieCountMax>k__BackingField",
}
local UNION_INT_FALLBACK = { "Int", "Int32", "INT", "mInt", "IntValue", "Value", "i32", "m_value" }
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

local state = {
    frame = 0,
    director = nil,
    max_deaths = nil,
    hunt_diag = "",
    last_path = "",
}

local param_union_td = nil
local param_data_td = nil
local union_int_fields = nil
local in_fail_life = 0
local life_get_logs = 0
local make_post_logs = 0
local life_hook_n = 0
local life_hooked_td = {}
local life_get_post

local function info(msg)
    if log ~= nil and log.info ~= nil then
        log.info("[Easier Hunting] " .. msg)
    end
end

local function try_get_field(object, name)
    if object == nil then
        return nil
    end
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

local function type_name(object)
    local name = nil
    pcall(function()
        name = object:get_type_definition():get_full_name()
    end)
    return name
end

local function managed_arg(arg)
    if arg == nil then
        return nil
    end
    local ok, obj = pcall(sdk.to_managed_object, arg)
    return ok and obj or nil
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

local function is_cart_cap(value)
    return type(value) == "number" and value >= CAP_MIN and value <= CAP_MAX
end

local function as_int(v)
    if type(v) == "number" then
        return math.floor(v)
    end
    if v == nil then
        return nil
    end
    local n = nil
    pcall(function()
        n = sdk.to_int64(v)
    end)
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

local function hook_method(method, pre, post)
    if method == nil then
        return false
    end
    return pcall(function()
        sdk.hook(method, pre, post)
    end)
end

local function hook_named(type_name_s, sig, pre, post)
    local td = sdk.find_type_definition(type_name_s)
    if td == nil then
        return
    end
    local method = td:get_method(sig)
    if method == nil and type(sig) == "string" and sig:sub(-2) == "()" then
        method = td:get_method(sig:sub(1, -3))
    end
    hook_method(method, pre, post)
end

-- Do not hook getQuestLife. Do not call get_QuestLife from Lua.
local function hook_life_td(td)
    local depth = 0
    while td ~= nil and depth < 6 do
        local tn = nil
        pcall(function()
            tn = td:get_full_name()
        end)
        if tn ~= nil and not life_hooked_td[tn] then
            life_hooked_td[tn] = true
            local methods = nil
            pcall(function()
                methods = td:get_methods()
            end)
            if methods ~= nil then
                for _, method in ipairs(methods) do
                    local name = nil
                    pcall(function()
                        name = method:get_name()
                    end)
                    if name == "get_QuestLife" then
                        if hook_method(method, function(_args) end, life_get_post) then
                            life_hook_n = life_hook_n + 1
                        end
                    end
                end
            end
            local direct = nil
            pcall(function()
                direct = td:get_method("get_QuestLife()") or td:get_method("get_QuestLife")
            end)
            if direct ~= nil then
                if hook_method(direct, function(_args) end, life_get_post) then
                    life_hook_n = life_hook_n + 1
                end
            end
        end
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

local function hook_life_obj(obj)
    if obj == nil or type(obj) ~= "userdata" then
        return
    end
    local td = nil
    pcall(function()
        td = obj:get_type_definition()
    end)
    hook_life_td(td)
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
        if sdk.is_managed_object == nil or sdk.is_managed_object(obj) then
            return obj
        end
    end
    return nil
end

local function get_mission()
    return sdk.get_managed_singleton("app.MissionManager")
end

-- 1.7.93 used MissionManager+0x178 as the live director. The getter alone
-- can miss _CurFlow=Playing, so HUD would pass through 3.
local function live_director()
    local mission = get_mission()
    if mission == nil then
        return nil
    end
    return follow_ptr(mission, 0x178)
        or follow_ptr(mission, 0x168)
        or follow_ptr(mission, 0x158)
        or try_call(mission, "get_QuestDirector()")
        or try_call(mission, "get_QuestDirector")
        or try_get_field(mission, "QuestDirector")
        or try_get_field(mission, "_QuestDirector")
end

local function cache_director()
    local qd = live_director()
    if qd ~= nil then
        state.director = qd
        hook_life_obj(qd)
        hook_life_obj(try_get_field(qd, "_CurFlow"))
        hook_life_obj(try_get_field(qd, "_ActiveQuestData") or try_get_field(qd, "ActiveQuestData"))
        hook_life_obj(try_get_field(qd, "_KeepQuestData") or try_get_field(qd, "KeepQuestData"))
    end
    return state.director
end

local function hunt_playing()
    local qd = state.director
    if qd == nil then
        return false
    end
    local flow = type_name(try_get_field(qd, "_CurFlow")) or ""
    return flow:find("Playing", 1, true) ~= nil
end

local function quest_session()
    local mission = get_mission()
    local playing = try_call(mission, "get_IsPlayingQuest()") or try_call(mission, "get_IsPlayingQuest")
    local active = try_call(mission, "get_IsActiveQuest()") or try_call(mission, "get_IsActiveQuest")
    if playing == true or playing == 1 or active == true or active == 1 then
        return true
    end
    local qd = cache_director()
    if qd == nil then
        return false
    end
    local flow = type_name(try_get_field(qd, "_CurFlow")) or ""
    return flow:find("Playing", 1, true) ~= nil or flow:find("Loading", 1, true) ~= nil
end

-- List UI: ParamData.ParamValue 3 or 5 -> 99 during fail-life makeParamData.

local function ensure_param_tds()
    if param_data_td == nil then
        param_data_td = sdk.find_type_definition("ace.cGUIMessageInfo.ParamData")
    end
    if param_union_td == nil then
        param_union_td = sdk.find_type_definition("ace.cGUIMessageInfo.ParamUnion")
    end
    if union_int_fields ~= nil then
        return
    end
    union_int_fields = {}
    local fields = nil
    if param_union_td ~= nil then
        pcall(function()
            fields = param_union_td:get_fields()
        end)
    end
    if fields ~= nil then
        for _, field in ipairs(fields) do
            pcall(function()
                if not field:is_static() then
                    local ftn = field:get_type():get_full_name()
                    if INT_TYPES[ftn] then
                        union_int_fields[#union_int_fields + 1] = field:get_name()
                    end
                end
            end)
        end
    end
    if #union_int_fields == 0 then
        union_int_fields = UNION_INT_FALLBACK
    end
end

local function patch_param_data(pd)
    if pd == nil or type(pd) ~= "userdata" then
        return false
    end
    ensure_param_tds()
    local names = union_int_fields
    local union = native_get(pd, param_data_td, "ParamValue")
    local wrote = false
    if type(union) == "number" then
        if union == 3 or union == 5 then
            wrote = native_set(pd, param_data_td, "ParamValue", TARGET)
        end
    elseif type(union) == "userdata" then
        for _, fname in ipairs(names) do
            local cur = as_int(native_get(union, param_union_td, fname))
            if cur == 3 or cur == 5 then
                native_set(union, param_union_td, fname, TARGET)
                wrote = true
            end
        end
        if wrote then
            native_set(pd, param_data_td, "ParamValue", union)
            try_set_field(pd, "ParamValue", union)
        end
    end
    return wrote
end

local function coerce_param_data(retval)
    if retval == nil then
        return nil
    end
    local pd = managed_arg(retval)
    if pd ~= nil then
        return pd
    end
    if type(retval) == "userdata" then
        return retval
    end
    return nil
end

local function fail_life_pre(_args)
    in_fail_life = in_fail_life + 1
end

local function fail_life_post(retval)
    if in_fail_life > 0 then
        in_fail_life = in_fail_life - 1
    end
    return retval
end

local function make_post(retval)
    if in_fail_life < 1 then
        return retval
    end
    local pd = coerce_param_data(retval)
    local wrote = false
    if pd ~= nil then
        wrote = patch_param_data(pd)
    end
    if make_post_logs < 6 then
        make_post_logs = make_post_logs + 1
        info("make-post wrote=" .. tostring(wrote))
    end
    return retval
end

-- HUD: Playing-only Byte-in-pointer-bits encoding. Load/accept pass through (1.7.80).

life_get_post = function(retval)
    local n = nil
    pcall(function()
        n = sdk.to_int64(retval)
    end)
    if type(n) ~= "number" then
        return retval
    end
    n = n % 256
    local playing = hunt_playing()
    if playing and n ~= TARGET then
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
            info("life-ptr skip bits=" .. tostring(bits))
        end
    end
    state.hunt_diag = "get_QuestLife=" .. tostring(n)
    if life_get_logs < 8 then
        life_get_logs = life_get_logs + 1
        info("life-get orig=" .. tostring(n) .. " play=" .. tostring(playing))
    end
    return retval
end

-- Wipe cap: Mandrake / qword at 0xB8. Never write 0xA0 (1.7.60).

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

local function collect_params(qd)
    local list = {}
    local seen = {}
    local function add(obj)
        if obj == nil or type(obj) ~= "userdata" then
            return
        end
        local id = object_id(obj)
        if id ~= nil and seen[id] then
            return
        end
        if id ~= nil then
            seen[id] = true
        end
        list[#list + 1] = obj
    end
    add(qd)
    for _, name in ipairs(PARAM_FIELDS) do
        add(try_get_field(qd, name))
    end
    for _, getter in ipairs(PARAM_GETTERS) do
        add(try_call(qd, getter))
    end
    return list
end

local function write_b8(param, target)
    local wrote = false
    local path = nil
    for _, name in ipairs(MANDRAKE_NAMES) do
        local enc = try_get_field(param, name)
        if enc ~= nil then
            local current = decode_mandrake(enc)
            if current == target then
                wrote = true
                path = name
            elseif is_cart_cap(current) and write_mandrake(enc, target) then
                try_set_field(param, name, enc)
                if decode_mandrake(try_get_field(param, name)) == target then
                    wrote = true
                    path = name
                end
            end
        end
    end
    if not quest_timer_at(param, B8) then
        local current, divisor = decode_at(param, B8)
        if current == target then
            wrote = true
            if path == nil then
                path = "PlDieCountMax@0xB8"
            end
        elseif is_cart_cap(current) and divisor ~= nil then
            if write_qword(param, B8, target * divisor) and decode_at(param, B8) == target then
                wrote = true
                path = "PlDieCountMax@0xB8"
            end
        end
    end
    return wrote, path
end

local function raise_b8(qd)
    if qd == nil then
        return
    end
    for _, param in ipairs(collect_params(qd)) do
        local ok, path = write_b8(param, TARGET)
        if ok then
            state.max_deaths = TARGET
            state.last_path = path or "PlDieCountMax@0xB8"
        end
    end
end

local function maintain()
    local qd = cache_director()
    if qd == nil or not quest_session() then
        if not quest_session() then
            state.max_deaths = nil
        end
        return
    end
    raise_b8(qd)
end

local function update()
    state.frame = state.frame + 1
    cache_director()
    if state.frame % IDLE_INTERVAL ~= 0 then
        return
    end
    pcall(maintain)
end

local function hook_make_param_data()
    local td = sdk.find_type_definition("ace.cGUIMessageInfo")
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
    for _, method in ipairs(methods) do
        local name = nil
        pcall(function()
            name = method:get_name()
        end)
        if name == "makeParamData" then
            hook_method(method, function(_args) end, make_post)
        end
    end
end

local function hook_fail_life()
    local types = {
        "app.QuestUtil",
        "app.GUIUtilApp.QuestUtil",
        "app.cActiveQuestData",
        "app.cGUIQuestViewData",
    }
    local sigs = {
        "getKeepQuestFailConditionText_Life()",
        "getFailConditionText_Life()",
    }
    for _, tn in ipairs(types) do
        for _, sig in ipairs(sigs) do
            hook_named(tn, sig, fail_life_pre, fail_life_post)
        end
    end
end

local function hook_quest_life()
    -- 1.7.95: KeepQuest+ActiveQuestData was one address; HUD never hit post.
    -- Same type list as 1.7.93, plus parents / live director objects.
    local types = {
        "app.cKeepQuestData",
        "app.cActiveQuestData",
        "app.cGUIQuestViewData",
        "app.user_data.QuestData",
        "app.user_data.QuestData.cData",
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
        "app.GUI050100",
        "app.GUI050100QuestDetail",
        "app.GUI050000QuestListParts",
        "app.GUIUtilApp.QuestUtil",
        "app.QuestUtil",
        "app.cQuestUtil",
        "app.QuestDataUtil",
        "app.cQuestDirector",
        "app.cQuestPlaying",
        "app.savedata.cQuestParam",
        "app.savedata.cInstantQuestParam",
        "app.cInstantQuestTemporaryHolder",
        "app.net_session_manager.SessionManager.cSearchResultQuest",
        "app.Net_LobbyUserInfo.CreateQuestInfo",
    }
    for _, tn in ipairs(types) do
        hook_life_td(sdk.find_type_definition(tn))
    end
    info("hook get_QuestLife n=" .. tostring(life_hook_n))
end

local function install()
    info("loaded " .. SCRIPT_VERSION)
    hook_make_param_data()
    hook_fail_life()
    hook_quest_life()
    hook_named("app.cQuestPlaying", "enter()", function(_args) end, function(retval)
        pcall(maintain)
        return retval
    end)
    re.on_frame(update)
    re.on_draw_ui(function()
        if imgui.tree_node(MOD_NAME) then
            imgui.text("Version / 版本: " .. SCRIPT_VERSION)
            imgui.text("Playing / 进行中: " .. tostring(hunt_playing()))
            imgui.text("PlDieCountMax / 倒下上限: " .. tostring(state.max_deaths))
            imgui.text("Path / 路径: " .. tostring(state.last_path))
            imgui.text("HUD / 界面: " .. (state.hunt_diag ~= "" and state.hunt_diag or "-"))
            imgui.tree_pop()
        end
    end)
end

if reframework == nil or reframework:get_game_name() ~= "mhwilds" then
    return
end
install()
