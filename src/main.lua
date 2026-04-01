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

local config = chalk.auto("config.lua")

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

public.store = lib.createStore(config, public.definition.stateSchema)
internal.store = public.store

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
    import("mods/runtime_state.lua")
    import("mods/npc_logic.lua")
    import("mods/loot_logic.lua")
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
        if lib.isEnabled(public.store, public.definition.modpack) then apply() end
    end, function()
        import_as_fallback(rom.game)
        reloadUi()
    end)
end)

local standaloneUi = lib.standaloneSpecialUI(
    public.definition,
    public.store,
    public.store.specialState,
    apply,
    revert,
    {
        getDrawQuickContent = function()
            return public.DrawQuickContent
        end,
        getDrawTab = function()
            return public.DrawTab
        end,
    }
)

---@diagnostic disable-next-line: redundant-parameter
rom.gui.add_imgui(standaloneUi.renderWindow)

---@diagnostic disable-next-line: redundant-parameter
rom.gui.add_to_menu_bar(standaloneUi.addMenuBar)
