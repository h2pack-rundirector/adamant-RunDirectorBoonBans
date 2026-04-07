local mods = rom.mods
mods["SGG_Modding-ENVY"].auto()

---@diagnostic disable: lowercase-global
rom = rom
_PLUGIN = _PLUGIN
game = rom.game
modutil = mods["SGG_Modding-ModUtil"]
local chalk = mods["SGG_Modding-Chalk"]
local reload = mods["SGG_Modding-ReLoad"]
lib = mods["adamant-ModpackLib"]

local dataDefaults = import("config.lua")
local config = chalk.auto("config.lua")

local PACK_ID = "run-director"
RunDirectorBoonBans_Internal = RunDirectorBoonBans_Internal or {}
local internal = RunDirectorBoonBans_Internal

public.definition = {
    modpack = PACK_ID,
    id = "BoonBans",
    name = "Boon Bans",
    tooltip = "Ban boon offerings, force rarity, and configure padding behavior.",
    default = dataDefaults.Enabled,
    special = true,
    affectsRunData = false,
}
internal.definition = public.definition

public.definition.storage = {
    { type = "bool",   alias = "EnablePadding",                   configKey = "EnablePadding" },
    { type = "int",    alias = "Padding_PrioritizeCoreForFirstN", configKey = "Padding_PrioritizeCoreForFirstN", min = 0,     max = 15 },
    { type = "bool",   alias = "Padding_AvoidFutureAllowed",      configKey = "Padding_AvoidFutureAllowed" },
    { type = "bool",   alias = "Padding_AllowDuos",               configKey = "Padding_AllowDuos" },
    { type = "int",    alias = "ImproveFirstNBoonRarity",         configKey = "ImproveFirstNBoonRarity",         min = 0,     max = 15 },
    { type = "string", alias = "BridalGlowTargetBoon",            configKey = "BridalGlowTargetBoon",            maxLen = 128 },
    { type = "int",    alias = "ViewRegion",                      configKey = "ViewRegion" },
}
public.definition.ui = {}


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
        table.insert(public.definition.storage, {
            type = "int",
            alias = item.key,
            configKey = item.key,
        })
    end
end

public.store = lib.createStore(config, public.definition, dataDefaults)
store = public.store

local function SyncPublicExports()
    public.DrawTab = internal.DrawTab
    public.DrawQuickContent = internal.DrawQuickContent
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

local function init()
    import_as_fallback(rom.game)
    registerHooks()
    if lib.isEnabled(store, public.definition.modpack) then
        lib.applyDefinition(public.definition, store)
    end
end

local loader = reload.auto_single()

modutil.once_loaded.game(function()
    loader.load(init, init)
end)

local standaloneUi = lib.standaloneSpecialUI(
    public.definition,
    store,
    store.uiState,
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
