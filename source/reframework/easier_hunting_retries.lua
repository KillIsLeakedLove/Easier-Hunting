---@diagnostic disable: undefined-global

-- Goal: quest faint/cart cap = 99 (UI + wipe check + faint message).
-- Runtime cap field: app.cQuestFlowParam.PlDieCountMax (Mandrake @ 0xB8).
-- UI field: QuestData._QuestLife.
-- Do not touch QuestPlDieCount.

local sdk = sdk
local re = re
local imgui = imgui
local reframework = reframework
local log = log

local MOD_NAME = "Easier Hunting: Quest Life"
local TARGET = 99
local SCAN_INTERVAL = 20
local PL_DIE_COUNT_MAX_OFF = 0xB8

local state = {
    frame = 0,
    status = "Waiting for quest.",
    detail = "",
    writes = 0,
    ui_life = nil,
    max_deaths = nil,
    deaths = nil,
    last_path = "",
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
    return ok and value or nil
end

local function try_set_field(object, name, value)
    return pcall(function()
        object:set_field(name, value)
    end)
end

local function try_call(object, method_name, ...)
    local args = { ... }
    local ok, value = pcall(function()
        return object:call(method_name, table.unpack(args))
    end)
    return ok and value or nil
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

local function get_quest_director()
    local mission = sdk.get_managed_singleton("app.MissionManager")
    if mission == nil then
        return nil
    end
    return try_get_field(mission, "QuestDirector")
        or try_get_field(mission, "_QuestDirector")
        or try_call(mission, "get_QuestDirector")
end

local function get_live_quest_data(qd)
    local active = try_get_field(qd, "_QuestData")
    if active == nil then
        return nil
    end
    return try_get_field(active, "_QuestData") or active
end

local function quest_is_live(qd)
    local data = get_live_quest_data(qd)
    if data == nil then
        return false
    end
    local life = try_get_field(data, "_QuestLife") or try_get_field(data, "QuestLife")
    return type(life) == "number" and life >= 1 and life <= 30
end

local function raise_ui_quest_life(qd)
    local data = get_live_quest_data(qd)
    if data == nil then
        return false
    end
    local value = try_get_field(data, "_QuestLife") or try_get_field(data, "QuestLife")
    if value == TARGET then
        state.ui_life = TARGET
        return true
    end
    if type(value) ~= "number" or value < 1 or value > 30 then
        return false
    end
    if not (try_set_field(data, "_QuestLife", TARGET) or try_set_field(data, "QuestLife", TARGET)) then
        return false
    end
    local after = try_get_field(data, "_QuestLife") or try_get_field(data, "QuestLife")
    if after ~= TARGET then
        return false
    end
    state.writes = state.writes + 1
    state.ui_life = TARGET
    state.last_path = "QuestDirector._QuestData._QuestData._QuestLife"
    set_status("QuestLife set to 99.", state.last_path)
    return true
end

local function raise_pl_die_count_max(qd)
    local param = try_get_field(qd, "<Param>k__BackingField")
        or try_get_field(qd, "Param")
        or try_call(qd, "get_Param")
    if param == nil then
        return false
    end

    -- 1) Managed Mandrake field
    for _, name in ipairs({ "PlDieCountMax", "_PlDieCountMax", "<PlDieCountMax>k__BackingField" }) do
        local enc = try_get_field(param, name)
        if enc ~= nil then
            local current = decode_mandrake(enc)
            if current == TARGET then
                state.max_deaths = TARGET
                state.last_path = "Param." .. name
                return true
            end
            if current ~= nil and current >= 1 and current <= 10 then
                if write_mandrake(enc, TARGET) then
                    try_set_field(param, name, enc)
                    if decode_mandrake(try_get_field(param, name)) == TARGET then
                        state.writes = state.writes + 1
                        state.max_deaths = TARGET
                        state.last_path = "Param." .. name
                        set_status("PlDieCountMax set to 99.", string.format("%s (was %d)", state.last_path, current))
                        return true
                    end
                end
            end
        end
    end

    -- 2) Offset fallback only while quest is live and value looks like a normal cap.
    local current, divisor = decode_at(param, PL_DIE_COUNT_MAX_OFF)
    if current == TARGET then
        state.max_deaths = TARGET
        state.last_path = "Param.PlDieCountMax@0xB8"
        return true
    end
    if current ~= nil and current >= 1 and current <= 10 and divisor ~= nil then
        if write_qword(param, PL_DIE_COUNT_MAX_OFF, TARGET * divisor)
            and decode_at(param, PL_DIE_COUNT_MAX_OFF) == TARGET
        then
            state.writes = state.writes + 1
            state.max_deaths = TARGET
            state.last_path = "Param.PlDieCountMax@0xB8"
            set_status("PlDieCountMax@0xB8 set to 99.", string.format("%s (was %d)", state.last_path, current))
            return true
        end
    end

    return false
end

local function read_deaths(qd)
    local n = decode_mandrake(try_get_field(qd, "QuestPlDieCount"))
    if n ~= nil then
        state.deaths = n
    end
end

local function maintain()
    local qd = get_quest_director()
    if qd == nil or not quest_is_live(qd) then
        set_status("Waiting for quest.")
        return
    end

    raise_ui_quest_life(qd)
    raise_pl_die_count_max(qd)
    read_deaths(qd)

    if state.max_deaths == TARGET then
        set_status(
            "OK: faint cap 99.",
            string.format("%s; deaths=%s", state.last_path, tostring(state.deaths or 0))
        )
    elseif state.ui_life == TARGET then
        set_status("QuestLife=99; PlDieCountMax not set yet.", state.last_path)
    else
        set_status("Applying faint cap...")
    end
end

local function update()
    state.frame = state.frame + 1
    if state.frame % SCAN_INTERVAL ~= 0 then
        return
    end
    local ok, err = pcall(maintain)
    if not ok then
        set_status("Error.", tostring(err):gsub("[\r\n]+", " "))
    end
end

if reframework == nil or reframework:get_game_name() ~= "mhwilds" then
    return
end

re.on_frame(update)

re.on_script_reset(function()
    state.frame = 0
    state.status = "Script reset."
    state.detail = ""
    state.writes = 0
    state.ui_life = nil
    state.max_deaths = nil
    state.deaths = nil
    state.last_path = ""
end)

re.on_draw_ui(function()
    if not imgui.tree_node(MOD_NAME) then
        return
    end
    imgui.text("Target faint cap: " .. tostring(TARGET))
    imgui.text("Status: " .. state.status)
    if state.detail ~= "" then
        imgui.text("Detail: " .. state.detail)
    end
    imgui.text("Writes: " .. tostring(state.writes))
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
