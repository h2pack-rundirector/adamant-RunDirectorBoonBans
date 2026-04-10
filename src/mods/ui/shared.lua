local internal = RunDirectorBoonBans_Internal
local godMeta = internal.godMeta
local godInfo = internal.godInfo
local uiData = internal.ui

local ImGuiCol = rom.ImGuiCol

uiData.EMPTY_LIST = {}

uiData.DEFAULT_GOD_COLOR = { 1, 1, 1, 1 }
uiData.DEFAULT_THEME_COLORS = {
    info = { 1, 1, 1, 1 },
    success = { 0.2, 1.0, 0.2, 1.0 },
    warning = { 1.0, 0.8, 0.0, 1.0 },
    error = { 1.0, 0.3, 0.3, 1.0 },
}
uiData.BADGE_COLORS = {
    duo = { 0.82, 1.0, 0.38, 1.0 },
    legendary = { 1.0, 0.56, 0.0, 1.0 },
    infusion = { 1.0, 0.29, 1.0, 1.0 },
}
uiData.RARITY_COLORS = {
    [0] = { 0.7, 0.7, 0.7, 1.0 },
    [1] = { 1.0, 1.0, 1.0, 1.0 },
    [2] = { 0.0, 0.54, 1.0, 1.0 },
    [3] = { 0.62, 0.07, 1.0, 1.0 },
}
uiData.RARITY_LABELS = {
    [0] = "Auto",
    [1] = "Comm",
    [2] = "Rare",
    [3] = "Epic",
}
uiData.NPC_REGION_OPTIONS = {
    { label = "Neither", value = 1 },
    { label = "Underworld", value = 2 },
    { label = "Surface", value = 3 },
    { label = "Both", value = 4 },
}
uiData.MAIN_TABS = {
    "Olympians",
    "Other Gods",
    "Hammers",
    "NPCs",
    "Settings",
}
uiData.BRIDAL_GLOW_VIEW_ID = "__bridal_glow__"
uiData.TAB_BY_GROUP = {
    Core = "Olympians",
    Bonus = "Other Gods",
    Hammers = "Hammers",
    ["UW NPC"] = "NPCs",
    ["SF NPC"] = "NPCs",
    Keepsakes = "NPCs",
}
uiData.GROUP_ORDER = {
    Core = 1,
    Bonus = 2,
    Hammers = 3,
    ["UW NPC"] = 4,
    ["SF NPC"] = 5,
    Keepsakes = 6,
}
uiData.BAN_FILTER_MODES = {
    { id = "all", label = "All" },
    { id = "banned", label = "Banned" },
    { id = "allowed", label = "Allowed" },
    { id = "special", label = "Special" },
}
uiData.BAN_FILTER_MODE_SET = {
    all = true,
    banned = true,
    allowed = true,
    special = true,
}
uiData.BAN_FILTER_TEXT_ALIAS = "BanFilterText"
uiData.BAN_FILTER_MODE_ALIAS = "BanFilterMode"
uiData.NPC_VIEW_REGION_ALIAS = "NpcViewRegion"
uiData.DIRECT_BANS_VIEW_ID = "__bans__"
uiData.FORCE_VIEW_ID = "__force__"
uiData.RARITY_VIEW_ID = "__rarity__"
uiData.SIDEBAR_RATIO = 0.28
uiData.CONFIRM_TIMEOUT = 5.0
uiData.BAN_LABEL_START = 28

uiData.sliderIntDrafts = {}
uiData.rootDescriptors = nil
uiData.rootsByMainTab = nil
uiData.rootIdByScopeKey = nil
uiData.visibleRootsByMainTab = {}
uiData.bridalGlowEligibleRoots = nil
uiData.banRowsByScope = {}
uiData.banPanelLayoutsByScope = {}
uiData.rarityRowsByRoot = {}
uiData.bridalGlowBoonsByRoot = {}
uiData.selectedRootByMainTab = {}
uiData.banFilterState = {
    rootId = nil,
}
uiData.pendingDanger = nil
uiData.cachedEquippedWeaponName = ""
uiData.bridalGlowSelection = {
    rootKey = nil,
}
uiData.activeBridalGlowRootId = nil

function uiData.GetThemeColors(theme)
    return (theme and theme.colors) or uiData.DEFAULT_THEME_COLORS
end

function uiData.DrawColoredText(ui, color, text)
    ui.TextColored(color[1], color[2], color[3], color[4], text)
end

function uiData.GetOrdinal(n)
    local s = tostring(n)
    if n % 100 == 11 or n % 100 == 12 or n % 100 == 13 then return s .. "th" end
    local last = n % 10
    if last == 1 then return s .. "st" end
    if last == 2 then return s .. "nd" end
    if last == 3 then return s .. "rd" end
    return s .. "th"
end

function uiData.DrawStepInput(ui, uiState, label, configKey, minValue, maxValue, step)
    step = step or 1
    local value = uiState.view[configKey] or minValue
    value = math.max(minValue, math.min(maxValue, value))

    ui.PushID(configKey)
    if ui.Button("-") and value > minValue then
        uiState.set(configKey, value - step)
    end
    ui.SameLine()
    ui.Text(label .. ": " .. tostring(value))
    ui.SameLine()
    if ui.Button("+") and value < maxValue then
        uiState.set(configKey, value + step)
    end
    ui.PopID()
end

function uiData.DrawDeferredSliderInt(ui, uiState, label, configKey, minValue, maxValue, defaultValue)
    local liveValue = uiState.view[configKey]
    if liveValue == nil then
        liveValue = defaultValue or minValue
    end
    liveValue = math.max(minValue, math.min(maxValue, liveValue))

    local sliderValue = uiData.sliderIntDrafts[configKey]
    if sliderValue == nil then
        sliderValue = liveValue
    end

    ui.PushID(configKey)
    local nextValue, changed = ui.SliderInt(label, sliderValue, minValue, maxValue)
    if changed then
        uiData.sliderIntDrafts[configKey] = math.max(minValue, math.min(maxValue, nextValue))
    end
    if ui.IsItemDeactivatedAfterEdit() then
        local commitValue = uiData.sliderIntDrafts[configKey]
        if commitValue ~= nil and commitValue ~= liveValue then
            uiState.set(configKey, commitValue)
        end
        uiData.sliderIntDrafts[configKey] = nil
    elseif not ui.IsItemActive() then
        uiData.sliderIntDrafts[configKey] = nil
    end
    ui.PopID()
end

function uiData.DrawBadge(ui, text, color, tooltip)
    ui.PushStyleColor(ImGuiCol.Button, color[1], color[2], color[3], 0.2)
    ui.PushStyleColor(ImGuiCol.ButtonHovered, color[1], color[2], color[3], 0.2)
    ui.PushStyleColor(ImGuiCol.ButtonActive, color[1], color[2], color[3], 0.2)
    ui.PushStyleColor(ImGuiCol.Text, 1, 1, 1, 1)
    ui.Button(text)
    ui.PopStyleColor(4)
    if tooltip and ui.IsItemHovered() then
        ui.SetTooltip(tooltip)
    end
end

function uiData.IsRegionMatch(group, regionValue)
    if regionValue == 4 then return true end
    if group == "UW NPC" then
        return regionValue == 2
    end
    if group == "SF NPC" then
        return regionValue == 3
    end
    return true
end

function uiData.IsSpecialBoon(boon)
    return boon.IsSpecial == true
end

function uiData.IsRarityEligibleBoon(boon)
    return boon.IsRarityEligible ~= false
end

function uiData.IsBridalGlowEligibleBoon(boon)
    return boon.IsBridalGlowEligible == true
end

function uiData.FormatCountLabel(banned, total)
    return string.format("(%d/%d Banned)", banned, total)
end

function uiData.GetBanLabelStart()
    return uiData.BAN_LABEL_START
end

function uiData.GetScopeBoons(scopeKey)
    local entry = godInfo[scopeKey]
    if entry and entry.boons then
        return entry.boons
    end
    return uiData.EMPTY_LIST
end

function uiData.FindBoonByKey(scopeKey, boonKey)
    local entry = godInfo[scopeKey]
    if entry and entry.boonByKey then
        return entry.boonByKey[boonKey]
    end

    for _, boon in ipairs(uiData.GetScopeBoons(scopeKey)) do
        if boon.Key == boonKey then
            return boon
        end
    end
end

function uiData.GetForcedBoonSelection(scopeKey, packedMask)
    local boons = uiData.GetScopeBoons(scopeKey)
    local allowedBoon = nil
    local banned = 0
    local total = 0

    for _, boon in ipairs(boons) do
        total = total + 1
        if bit32.band(packedMask or 0, boon.Mask) ~= 0 then
            banned = banned + 1
        else
            allowedBoon = boon
        end
    end

    if banned == 0 then
        return nil, true, false
    end
    if total == 0 or banned ~= (total - 1) then
        return nil, false, true
    end
    return allowedBoon, false, false
end

function uiData.GetForcedBoonDisplayLabel(boon)
    if not boon then
        return ""
    end
    return boon.SpecialDisplayLabel or uiData.GetBoonText(boon)
end

function uiData.GetForcedBoonStatusText(boon)
    if not boon then
        return ""
    end
    return boon.SpecialBadgeText or uiData.GetForcedBoonDisplayLabel(boon)
end

function uiData.GetRootMeta(rootKey)
    return godMeta[rootKey]
end

function uiData.GetSourceColor(scopeKey)
    local entry = godInfo[scopeKey]
    if entry and type(entry.color) == "table" then
        return entry.color
    end
    return uiData.DEFAULT_GOD_COLOR
end

function uiData.IsGodPoolFilteringActive()
    local godPool = rom.mods["adamant-RunDirector_GodPool"]
    if not godPool or not godPool.store or not godPool.definition or type(godPool.isGodEnabledInPool) ~= "function" then
        return false, nil
    end
    if not lib.isEnabled(godPool.store, godPool.definition.modpack) then
        return false, nil
    end
    return true, godPool
end

function uiData.IsGodVisibleInGodPool(godKey, godPool)
    local root = internal.GetRootKey and internal.GetRootKey(godKey) or godKey
    return godPool.isGodEnabledInPool(root)
end

function uiData.GetEquippedWeaponName()
    if GetEquippedWeapon then
        return GetEquippedWeapon() or ""
    end
    return ""
end

function uiData.RefreshFrameState()
    uiData.cachedEquippedWeaponName = uiData.GetEquippedWeaponName()
end

function uiData.InvalidateBridalGlowRootCache()
    uiData.bridalGlowEligibleRoots = nil
end

function uiData.GetRootDisplayLabel(rootKey, meta)
    local display = meta.displayTextKey or rootKey
    if meta.maxTiers then
        display = display:gsub("^1st%s+", "")
    end
    return display
end
