local mods = rom.mods
mods["SGG_Modding-ENVY"].auto()

---@diagnostic disable: lowercase-global
rom = rom
_PLUGIN = _PLUGIN
game = rom.game
modutil = mods["SGG_Modding-ModUtil"]
chalk = mods["SGG_Modding-Chalk"]
reload = mods["SGG_Modding-ReLoad"]
local lib = mods["adamant-ModpackLib"]

config = chalk.auto("config.lua")
public.config = config

local _, revert = lib.createBackupSystem()

local PACK_ID = "run-director"
RunDirectorBoonBans_Internal = RunDirectorBoonBans_Internal or {}
local internal = RunDirectorBoonBans_Internal

public.definition = {
    modpack = PACK_ID,
    id = "RunDirectorBoonBans",
    name = "Boon Bans",
    tabLabel = "Boon Bans",
    category = "Run Director",
    group = "Run Setup",
    tooltip = "Ban boon offerings, force rarity, and configure padding behavior.",
    default = false,
    special = true,
    dataMutation = false,
}
internal.definition = public.definition

public.definition.stateSchema = {
    { type = "checkbox", configKey = "EnablePadding", default = config.EnablePadding },
    { type = "checkbox", configKey = "Padding_UsePriority", default = config.Padding_UsePriority },
    { type = "checkbox", configKey = "Padding_AvoidFutureAllowed", default = config.Padding_AvoidFutureAllowed },
    { type = "checkbox", configKey = "Padding_AllowDuos", default = config.Padding_AllowDuos },
    { type = "stepper", configKey = "ImproveFirstNBoonRarity", default = config.ImproveFirstNBoonRarity, min = 0, max = 15 },
    { type = "int32", configKey = "ViewRegion", default = config.ViewRegion },
}

do
    local packedKeys = {}
    for key, value in pairs(config) do
        if type(key) == "string" and key:find("^Packed") then
            table.insert(packedKeys, { key = key, default = value })
        end
    end
    table.sort(packedKeys, function(a, b)
        return a.key < b.key
    end)
    for _, item in ipairs(packedKeys) do
        table.insert(public.definition.stateSchema, {
            type = "int32",
            configKey = item.key,
            default = item.default,
        })
    end
end

local managedSpecialState = lib.createSpecialState(config, public.definition.stateSchema)
public.specialState = managedSpecialState

local stateBackedKeys = {}
for _, field in ipairs(public.definition.stateSchema) do
    stateBackedKeys[field.configKey] = true
end
internal.stateBackedKeys = stateBackedKeys

function internal.withStateBackedConfig(specialState, fn)
    local realConfig = config
    local proxy = setmetatable({}, {
        __index = function(_, key)
            if stateBackedKeys[key] then
                return specialState.get(key)
            end
            return realConfig[key]
        end,
        __newindex = function(_, key, value)
            if stateBackedKeys[key] then
                specialState.set(key, value)
            else
                realConfig[key] = value
            end
        end,
    })

    local previous = config
    config = proxy
    local ok, resultA, resultB = pcall(fn)
    config = previous
    if not ok then
        error(resultA, 0)
    end
    return resultA, resultB
end

local function SyncPublicExports()
    public.DrawTab = internal.DrawTab
    public.DrawQuickContent = internal.DrawQuickContent
end

local function apply()
end

local function registerHooks()
    bit32 = require("bit32")
    import("mods/god_meta.lua")
    import("mods/utilities.lua")
    import("mods/logic_others.lua")
    import("mods/logic_core.lua")
    import("mods/ui.lua")
    SyncPublicExports()
end

local function reloadUi()
    import("mods/god_meta.lua")
    import("mods/ui.lua")
    SyncPublicExports()
end

public.definition.apply = apply
public.definition.revert = revert

local loader = reload.auto_single()

modutil.once_loaded.game(function()
    loader.load(function()
        import_as_fallback(rom.game)
        registerHooks()
        if lib.isEnabled(config, public.definition.modpack) then apply() end
    end, function()
        import_as_fallback(rom.game)
        reloadUi()
    end)
end)

local showWindow = false

local function warnIfStandaloneBypassedState(before)
    lib.warnIfSpecialConfigBypassedState(
        public.definition.name,
        config.DebugMode,
        public.specialState,
        config,
        public.definition.stateSchema,
        before
    )
end

---@diagnostic disable-next-line: redundant-parameter
rom.gui.add_imgui(function()
    if lib.isCoordinated(public.definition.modpack) then return end
    if not showWindow then return end

    if rom.ImGui.Begin(public.definition.name .. "###" .. public.definition.id) then
        local val, chg = rom.ImGui.Checkbox("Enabled", config.Enabled)
        if chg then
            config.Enabled = val
            if val then apply() else revert() end
        end
        rom.ImGui.Separator()
        rom.ImGui.Spacing()
        local beforeQuick = lib.captureSpecialConfigSnapshot(config, public.definition.stateSchema)
        if public.DrawQuickContent then
            public.DrawQuickContent(rom.ImGui, public.specialState, nil)
        end
        warnIfStandaloneBypassedState(beforeQuick)
        if public.specialState.isDirty() then
            public.specialState.flushToConfig()
        end
        rom.ImGui.Spacing()
        rom.ImGui.Separator()
        local beforeTab = lib.captureSpecialConfigSnapshot(config, public.definition.stateSchema)
        if public.DrawTab then
            public.DrawTab(rom.ImGui, public.specialState, nil)
        end
        warnIfStandaloneBypassedState(beforeTab)
        if public.specialState.isDirty() then
            public.specialState.flushToConfig()
        end
        rom.ImGui.End()
    else
        showWindow = false
    end
end)

---@diagnostic disable-next-line: redundant-parameter
rom.gui.add_to_menu_bar(function()
    if lib.isCoordinated(public.definition.modpack) then return end
    if rom.ImGui.BeginMenu(public.definition.name) then
        if rom.ImGui.MenuItem(public.definition.name) then
            showWindow = not showWindow
        end
        rom.ImGui.EndMenu()
    end
end)
