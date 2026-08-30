---@diagnostic disable: undefined-global

-- Raises only a verified retry-cap member. It does not modify used retries,
-- retry tickets, rewards, quest results, failure records, timers, or saves.

local sdk = sdk
local re = re
local imgui = imgui
local reframework = reframework
local log = log

local MOD_NAME = "Easier Hunting: Infinite Quest Retries"
local TARGET_RETRY_CAP = 99
local SCAN_INTERVAL_FRAMES = 60
local RETRY_TYPE_FRAGMENT = "QuestRetryQuestData"

local MAX_RETRY_FIELD_NAMES = {
    "MaxRetryCnt",
    "_MaxRetryCnt",
    "<MaxRetryCnt>k__BackingField",
}

local RETRY_ACCESSOR_NAMES = {
    "get_QuestRetryQuestData",
    "get_QuestRetryData",
    "get_RetryQuestData",
    "get_RetryData",
    "get_QuestRetry",
    "get_Retry",
}

local RETRY_FIELD_NAMES = {
    "QuestRetryQuestData",
    "_QuestRetryQuestData",
    "<QuestRetryQuestData>k__BackingField",
    "QuestRetryData",
    "_QuestRetryData",
    "<QuestRetryData>k__BackingField",
    "Retry",
    "_Retry",
}

local INTEGER_TYPE_NAMES = {
    ["System.SByte"] = true,
    ["System.Byte"] = true,
    ["System.Int16"] = true,
    ["System.UInt16"] = true,
    ["System.Int32"] = true,
    ["System.UInt32"] = true,
    ["System.Int64"] = true,
    ["System.UInt64"] = true,
}

local state = {
    frame_count = 0,
    status = "Starting.",
    detail = "",
    last_path = "",
    last_member = "",
    last_value = nil,
    writes = 0,
}

local function set_status(status, detail)
    detail = detail or ""
    if state.status == status and state.detail == detail then
        return
    end
    state.status = status
    state.detail = detail
    if log ~= nil and log.info ~= nil then
        log.info("[Easier Hunting] " .. status .. (detail ~= "" and " " .. detail or ""))
    end
end

local function type_name(object)
    local ok, result = pcall(function()
        local type_definition = object:get_type_definition()
        return type_definition ~= nil and type_definition:get_full_name() or nil
    end)
    return ok and result or nil
end

local function integer_field(type_definition)
    for _, field_name in ipairs(MAX_RETRY_FIELD_NAMES) do
        local field = type_definition:get_field(field_name)
        if field ~= nil and not field:is_static() then
            local field_type = field:get_type()
            local field_type_name = field_type ~= nil and field_type:get_full_name() or nil
            if field_type_name ~= nil and INTEGER_TYPE_NAMES[field_type_name] then
                return field, field_name, field_type_name
            end
        end
    end
    return nil, nil, nil
end

local function integer_property(type_definition)
    local getter = type_definition:get_method("get_MaxRetryCnt")
    local setter = type_definition:get_method("set_MaxRetryCnt")
    if getter == nil or setter == nil
        or getter:is_static() or setter:is_static()
        or getter:get_num_params() ~= 0 or setter:get_num_params() ~= 1 then
        return nil, nil, nil
    end

    local return_type = getter:get_return_type()
    local return_type_name = return_type ~= nil and return_type:get_full_name() or nil
    local parameter_types = setter:get_param_types()
    local parameter_type = parameter_types ~= nil and (parameter_types[1] or parameter_types[0]) or nil
    local parameter_type_name = parameter_type ~= nil and parameter_type:get_full_name() or nil
    if return_type_name == nil or return_type_name ~= parameter_type_name
        or not INTEGER_TYPE_NAMES[return_type_name] then
        return nil, nil, nil
    end
    return getter, setter, return_type_name
end

local function has_retry_cap_member(object)
    local ok, result = pcall(function()
        local type_definition = object:get_type_definition()
        if type_definition == nil then
            return false
        end
        local field = integer_field(type_definition)
        if field ~= nil then
            return true
        end
        local getter = integer_property(type_definition)
        return getter ~= nil
    end)
    return ok and result == true
end

local function is_retry_data(object)
    local current_type_name = type_name(object)
    return (current_type_name ~= nil and current_type_name:find(RETRY_TYPE_FRAGMENT, 1, true) ~= nil)
        or has_retry_cap_member(object)
end

local function call_zero_arg_getter(object, method_name)
    local ok, result = pcall(function()
        local type_definition = object:get_type_definition()
        local method = type_definition:get_method(method_name)
        if method == nil or method:is_static() or method:get_num_params() ~= 0 then
            return nil
        end
        return method:call(object)
    end)
    return ok and result or nil
end

local function get_instance_field(object, field_name)
    local ok, result = pcall(function()
        local type_definition = object:get_type_definition()
        local field = type_definition:get_field(field_name)
        if field == nil or field:is_static() then
            return nil
        end
        return field:get_data(object)
    end)
    return ok and result or nil
end

local function find_retry_data_in_members(root)
    if is_retry_data(root) then
        return root, "root"
    end

    for _, method_name in ipairs(RETRY_ACCESSOR_NAMES) do
        local candidate = call_zero_arg_getter(root, method_name)
        if is_retry_data(candidate) then
            return candidate, method_name .. "()"
        end
    end

    for _, field_name in ipairs(RETRY_FIELD_NAMES) do
        local candidate = get_instance_field(root, field_name)
        if is_retry_data(candidate) then
            return candidate, field_name
        end
    end

    return nil, nil
end

local function find_retry_data_in_typed_members(root)
    local found_value, found_name = nil, nil
    local ok = pcall(function()
        local type_definition = root:get_type_definition()
        for _, field in ipairs(type_definition:get_fields()) do
            if not field:is_static() then
                local name = field:get_name()
                local field_type = field:get_type()
                local field_type_name = field_type ~= nil and field_type:get_full_name() or nil
                if name:lower():find("retry", 1, true) ~= nil
                    or (field_type_name ~= nil and field_type_name:find(RETRY_TYPE_FRAGMENT, 1, true) ~= nil) then
                    local value = field:get_data(root)
                    if is_retry_data(value) then
                        found_value, found_name = value, name
                        return
                    end
                end
            end
        end

        for _, method in ipairs(type_definition:get_methods()) do
            local name = method:get_name()
            local return_type = method:get_return_type()
            local return_type_name = return_type ~= nil and return_type:get_full_name() or nil
            if name:sub(1, 4) == "get_"
                and not method:is_static()
                and method:get_num_params() == 0
                and (name:lower():find("retry", 1, true) ~= nil
                    or (return_type_name ~= nil and return_type_name:find(RETRY_TYPE_FRAGMENT, 1, true) ~= nil)) then
                local value = method:call(root)
                if is_retry_data(value) then
                    found_value, found_name = value, name .. "()"
                    return
                end
            end
        end
    end)
    if ok then
        return found_value, found_name
    end
    return nil, nil
end

local function append_root(roots, object, path)
    if object ~= nil then
        table.insert(roots, { object = object, path = path })
    end
end

local function find_retry_data(mission_manager)
    local roots = {}
    append_root(roots, mission_manager, "MissionManager")

    local quest_director = call_zero_arg_getter(mission_manager, "get_QuestDirector")
    append_root(roots, quest_director, "MissionManager.get_QuestDirector()")
    if quest_director ~= nil then
        append_root(
            roots,
            call_zero_arg_getter(quest_director, "get_QuestData"),
            "MissionManager.get_QuestDirector().get_QuestData()"
        )
    end
    append_root(roots, call_zero_arg_getter(mission_manager, "get_QuestData"), "MissionManager.get_QuestData()")

    for _, root in ipairs(roots) do
        local retry_data, member_name = find_retry_data_in_members(root.object)
        if retry_data ~= nil then
            return retry_data, root.path .. "." .. member_name
        end
        retry_data, member_name = find_retry_data_in_typed_members(root.object)
        if retry_data ~= nil then
            return retry_data, root.path .. "." .. member_name
        end
    end
    return nil, nil
end

local function read_field(field, object)
    local ok, value = pcall(function()
        return field:get_data(object)
    end)
    return ok and type(value) == "number" and value == math.floor(value) and value or nil
end

local function read_property(getter, object)
    local ok, value = pcall(function()
        return getter:call(object)
    end)
    return ok and type(value) == "number" and value == math.floor(value) and value or nil
end

local function maintain_retry_cap()
    local mission_manager = sdk.get_managed_singleton("app.MissionManager")
    if mission_manager == nil then
        set_status("Waiting for app.MissionManager.")
        return
    end

    local retry_data, data_path = find_retry_data(mission_manager)
    if retry_data == nil then
        set_status("Waiting for quest retry data.")
        return
    end

    local type_definition = retry_data:get_type_definition()
    local field, field_name, field_type_name = integer_field(type_definition)
    local getter = nil
    local setter = nil
    local member_name = field_name
    if field == nil then
        getter, setter, field_type_name = integer_property(type_definition)
        member_name = "MaxRetryCnt"
    end
    if field == nil and getter == nil then
        set_status("Retry data found, but MaxRetryCnt is unavailable.", type_name(retry_data) or "")
        return
    end

    local current_value = field ~= nil and read_field(field, retry_data) or read_property(getter, retry_data)
    if current_value == nil then
        set_status("MaxRetryCnt is not a readable integer.", field_type_name or "")
        return
    end

    state.last_path = data_path
    state.last_member = member_name
    state.last_value = current_value
    if current_value >= TARGET_RETRY_CAP then
        set_status("Quest retry cap is " .. tostring(current_value) .. ".", data_path)
        return
    end
    if current_value < 1 then
        set_status("MaxRetryCnt has an unexpected value; no change was made.", tostring(current_value))
        return
    end

    local write_ok = false
    if field ~= nil then
        write_ok = pcall(function()
            retry_data:set_field(field_name, TARGET_RETRY_CAP)
        end)
    else
        write_ok = pcall(function()
            setter:call(retry_data, TARGET_RETRY_CAP)
        end)
    end
    if not write_ok then
        set_status("MaxRetryCnt write failed; no change was verified.", data_path)
        return
    end

    local verified_value = field ~= nil and read_field(field, retry_data) or read_property(getter, retry_data)
    if verified_value ~= TARGET_RETRY_CAP then
        set_status("MaxRetryCnt write could not be verified.", data_path)
        return
    end

    state.last_value = verified_value
    state.writes = state.writes + 1
    set_status("Quest retry cap raised from " .. tostring(current_value) .. " to " .. tostring(TARGET_RETRY_CAP) .. ".", data_path)
end

local function update()
    state.frame_count = state.frame_count + 1
    if state.frame_count % SCAN_INTERVAL_FRAMES ~= 0 then
        return
    end
    local ok, error = pcall(maintain_retry_cap)
    if not ok then
        set_status("Runtime lookup failed; no change was made.", tostring(error):gsub("[\r\n]+", " "))
    end
end

if reframework == nil or reframework:get_game_name() ~= "mhwilds" then
    return
end

re.on_frame(update)

re.on_script_reset(function()
    state.frame_count = 0
    state.status = "Script reset."
    state.detail = ""
    state.last_path = ""
    state.last_member = ""
    state.last_value = nil
end)

re.on_draw_ui(function()
    if not imgui.tree_node(MOD_NAME) then
        return
    end
    imgui.text("Target retry cap: " .. tostring(TARGET_RETRY_CAP))
    imgui.text("Status: " .. state.status)
    if state.detail ~= "" then
        imgui.text("Detail: " .. state.detail)
    end
    if state.last_member ~= "" then
        imgui.text("Live member: " .. state.last_path .. "." .. state.last_member)
    end
    if state.last_value ~= nil then
        imgui.text("Last observed cap: " .. tostring(state.last_value))
    end
    imgui.text("Verified writes this session: " .. tostring(state.writes))
    imgui.tree_pop()
end)
