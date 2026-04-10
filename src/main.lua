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

local function BuildPackedStorageNode(item)
    local bits = internal.GetPackedStorageBits(item.key)
    if not bits then
        return {
            type = "int",
            alias = item.key,
            configKey = item.key,
        }
    end

    local packedWidth = nil
    local lastBit = bits[#bits]
    if lastBit then
        packedWidth = lastBit.offset + lastBit.width
    end

    return {
        type = "packedInt",
        alias = item.key,
        configKey = item.key,
        default = item.default,
        width = packedWidth,
        bits = bits,
    }
end

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

public.definition.storage = {}
public.definition.ui = {}

local function BuildDefinitionStorage()
    public.definition.storage = {
        { type = "bool",   alias = "EnablePadding",                   configKey = "EnablePadding" },
        { type = "int",    alias = "Padding_PrioritizeCoreForFirstN", configKey = "Padding_PrioritizeCoreForFirstN", min = 0,     max = 15 },
        { type = "bool",   alias = "Padding_AvoidFutureAllowed",      configKey = "Padding_AvoidFutureAllowed" },
        { type = "bool",   alias = "Padding_AllowDuos",               configKey = "Padding_AllowDuos" },
        { type = "int",    alias = "ImproveFirstNBoonRarity",         configKey = "ImproveFirstNBoonRarity",         min = 0,     max = 15 },
        { type = "string", alias = "BridalGlowTargetBoon",            configKey = "BridalGlowTargetBoon",            maxLen = 128 },
        { type = "int",    alias = "NpcViewRegion",                   lifetime = "transient",                         default = 4, min = 1, max = 4 },
        { type = "string", alias = "BanFilterText",                   lifetime = "transient",                         default = "", maxLen = 128 },
        { type = "string", alias = "BanFilterMode",                   lifetime = "transient",                         default = "all", maxLen = 16 },
    }

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
        table.insert(public.definition.storage, BuildPackedStorageNode(item))
    end
end

public.store = nil
store = nil
internal.standaloneUi = nil

local function RebuildStore()
    BuildDefinitionStorage()
    public.store = lib.createStore(config, public.definition, dataDefaults)
    store = public.store
end

local function SyncPublicExports()
    public.DrawTab = internal.DrawTab
    public.DrawQuickContent = internal.DrawQuickContent
end

local function registerHooks()
    bit32 = require("bit32")
    import("mods/utilities.lua")
    import("mods/runtime_state.lua")
    import("mods/npc_logic.lua")
    import("mods/loot_logic.lua")
    import("mods/ui.lua")
    SyncPublicExports()
end

local function init()
    import_as_fallback(rom.game)
    import("mods/god_meta.lua")
    import("mods/boon_catalog.lua")
    RebuildStore()
    registerHooks()
    if lib.isEnabled(store, public.definition.modpack) then
        lib.applyDefinition(public.definition, store)
    end

    internal.standaloneUi = lib.standaloneSpecialUI(
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
end

local loader = reload.auto_single()

modutil.once_loaded.game(function()
    loader.load(init, init)
end)

local function renderStandaloneWindow()
    if internal.standaloneUi and internal.standaloneUi.renderWindow then
        internal.standaloneUi.renderWindow()
    end
end

---@diagnostic disable-next-line: redundant-parameter
rom.gui.add_imgui(renderStandaloneWindow)

local function addStandaloneMenuBar()
    if internal.standaloneUi and internal.standaloneUi.addMenuBar then
        internal.standaloneUi.addMenuBar()
    end
end

---@diagnostic disable-next-line: redundant-parameter
rom.gui.add_to_menu_bar(addStandaloneMenuBar)
