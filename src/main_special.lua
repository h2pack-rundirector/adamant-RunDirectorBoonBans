-- =============================================================================
-- ADAMANT SPECIAL MODULE TEMPLATE
-- =============================================================================
-- Copy this file as src/main.lua in a new mod folder.
-- Fill in the sections marked FILL below.
--
-- Special modules get their own sidebar tab in the Framework UI and can encode
-- custom state into the config hash. They also render standalone when the
-- coordinator is not installed.
--
-- Managed special state is handled by lib.createSpecialState.
-- Hashing is handled by Framework via definition.stateSchema — modules don't encode/decode.
--
-- Public API wired automatically:
--   public.specialState             -- managed special-state object
--   public.definition.stateSchema   -- declares state shape for Framework to hash
--
-- You implement (optional):
--   public.DrawTab(ui, specialState, theme)         -- full tab content
--   public.DrawQuickContent(ui, specialState, theme) -- quick setup snippet

local mods = rom.mods
mods['SGG_Modding-ENVY'].auto()

---@diagnostic disable: lowercase-global
rom = rom
_PLUGIN = _PLUGIN
game = rom.game
modutil = mods['SGG_Modding-ModUtil']
chalk = mods['SGG_Modding-Chalk']
reload = mods['SGG_Modding-ReLoad']
local lib = mods['adamant-ModpackLib']

config = chalk.auto('config.lua')
public.config = config

local _, revert = lib.createBackupSystem()

local PACK_ID = "run-director"

-- =============================================================================
-- FILL: Module definition
-- =============================================================================

public.definition = {
    modpack      = PACK_ID, -- Opts this module into pack discovery
    id           = "",           -- Unique key, e.g. "FirstHammer"
    name         = "",           -- Display name, e.g. "First Hammer Selection"
    tabLabel     = "",           -- Sidebar tab label in the UI, e.g. "Hammers"
    category     = "",           -- Category, e.g. "Bug Fixes" | "Run Modifiers" | "QoL"
    group        = "",           -- UI group header, drives merged repo assignment
    tooltip      = "",           -- Hover text
    default      = false,        -- Default enabled state
    special      = true,         -- Marks this as a special module
    dataMutation = false,        -- true if apply() modifies game tables
}

-- =============================================================================
-- FILL: Module data & constants
-- =============================================================================

-- Define your module-specific data here (lookup tables, option lists, etc.)
-- Example:
-- local MY_OPTIONS = { "OptionA", "OptionB", "OptionC" }

-- Layout constants — set per-module based on your label text lengths.
local DEFAULT_FIELD_MEDIUM = 0.4

-- =============================================================================
-- FILL: State schema & managed state
-- =============================================================================
-- Declare your config shape on definition.stateSchema.
-- Framework uses this for hashing and profiles. lib.createSpecialState gives you
-- a managed `specialState` object with:
--   specialState.view               -- read-only live view for rendering
--   specialState.get(path)
--   specialState.set(path, value)
--   specialState.update(path, fn)
--   specialState.toggle(path)
--   specialState.reloadFromConfig()
--   specialState.flushToConfig()
--   specialState.isDirty()
--
-- Supported field types:
--   "checkbox" — single boolean toggle
--     { type="checkbox", configKey="X", default=false }
--
--   "dropdown" — pick one from a list (combo box)
--     { type="dropdown", configKey="X", values={...}, default="" }
--
--   "radio"    — pick one from a list (radio buttons)
--     { type="radio", configKey="X", values={...}, default="" }
--
-- configKey can be a string or a table path for nested config:
--   configKey = { "ParentTable", "ChildKey" }  -->  config.ParentTable.ChildKey

public.definition.stateSchema = {
    -- Example "dropdown" field (single selection):
    -- {
    --     configKey = "Mode",
    --     type      = "dropdown",
    --     values    = { "Normal", "Fast", "Slow" },
    --     default   = "Normal",
    -- },
}

local managedSpecialState = lib.createSpecialState(config, public.definition.stateSchema)

-- =============================================================================
-- FILL: apply() — mutate game data or set initial state
-- =============================================================================

local function apply()
end

-- =============================================================================
-- FILL: registerHooks() — wrap game functions
-- =============================================================================

local function registerHooks()
    -- modutil.mod.Path.Wrap("SomeGameFunction", function(baseFunc, ...)
    --     if not lib.isEnabled(config, public.definition.modpack) then return baseFunc(...) end
    --     return baseFunc(...)
    -- end)
end

-- =============================================================================
-- FILL: UI rendering
-- =============================================================================
-- DrawTab and DrawQuickContent receive a `theme` table (Framework theme when hosted,
-- nil when standalone). Unpack only what you need at the public boundary and
-- pass plain values down to inner functions — never pass `theme` itself deeper.
--
-- Available theme keys:
--   theme.colors             -- { info, success, error, warning, text, textDisabled, ... }
--   theme.FIELD_MEDIUM       -- fraction of window width for medium input fields
--   theme.FIELD_NARROW       -- fraction for narrow fields
--   theme.FIELD_WIDE         -- fraction for wide fields
--   theme.ImGuiTreeNodeFlags -- { None, DefaultOpen, Leaf, Framed, CollapsingHeader, ... }
--   theme.PushTheme          -- function()  apply full color theme (useful for standalone windows)
--   theme.PopTheme           -- function()  paired with PushTheme
--
-- headerColor pattern (add `local ImGuiCol = rom.ImGuiCol` at the top of your file):
--   local headerColor = (colors and colors.info) or {1, 1, 1, 1}
--   ui.PushStyleColor(ImGuiCol.Text, table.unpack(headerColor))
--   local open = ui.CollapsingHeader("Section")
--   ui.PopStyleColor()
--

--luacheck: ignore 212
local function DrawMainContent(ui, specialState, colors, headerColor, fieldMedium)
    -- Your full tab UI here.
    -- Read from specialState.view and mutate via specialState.set/update/toggle.
    ui.Text("TODO: implement tab content")
end

--luacheck: ignore 212
local function DrawQuickSnippet(ui, specialState, colors, fieldMedium)
    -- Abbreviated UI for the Quick Setup tab (optional).
    -- Typically shows only the most relevant option(s).
    ui.Text("TODO: implement quick content")
end

-- =============================================================================
-- PUBLIC API (generic special module contract)
-- =============================================================================

public.definition.apply = apply
public.definition.revert = revert

-- State management — wired directly from lib.createSpecialState
public.specialState       = managedSpecialState

--- Draw the full tab content (Framework renders the enable checkbox above this).
--luacheck: ignore 122
function public.DrawTab(ui, specialState, theme)
    local colors      = theme and theme.colors
    local headerColor = (colors and colors.info) or {1, 1, 1, 1}
    local fieldMedium = (theme and theme.FIELD_MEDIUM) or DEFAULT_FIELD_MEDIUM
    ui.Spacing()
    DrawMainContent(ui, specialState, colors, headerColor, fieldMedium)
end

--- Draw quick-access content for the Quick Setup tab.
--luacheck: ignore 122
function public.DrawQuickContent(ui, specialState, theme)
    local colors      = theme and theme.colors
    local fieldMedium = (theme and theme.FIELD_MEDIUM) or DEFAULT_FIELD_MEDIUM
    DrawQuickSnippet(ui, specialState, colors, fieldMedium)
end

-- =============================================================================
-- Wiring
-- =============================================================================

local loader = reload.auto_single()

modutil.once_loaded.game(function()
    loader.load(function()
        import_as_fallback(rom.game)
        registerHooks()
        if lib.isEnabled(config, public.definition.modpack) then apply() end
    end)
end)

-- =============================================================================
-- STANDALONE UI (renders when coordinator is not installed)
-- =============================================================================

local showWindow = false

local function warnIfStandaloneBypassedState(before)
    lib.warnIfSpecialConfigBypassedState(
        public.definition.name,
        config.DebugMode,
        specialState,
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
        public.DrawQuickContent(rom.ImGui, specialState, nil)
        warnIfStandaloneBypassedState(beforeQuick)
        if specialState.isDirty() then specialState.flushToConfig() end
        rom.ImGui.Spacing()
        rom.ImGui.Separator()
        local beforeTab = lib.captureSpecialConfigSnapshot(config, public.definition.stateSchema)
        public.DrawTab(rom.ImGui, specialState, nil)
        warnIfStandaloneBypassedState(beforeTab)
        if specialState.isDirty() then specialState.flushToConfig() end
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
