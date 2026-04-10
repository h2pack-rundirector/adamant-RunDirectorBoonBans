local internal = RunDirectorBoonBans_Internal
local uiData = internal.ui
local band = bit32.band
local bnot = bit32.bnot
local lshift = bit32.lshift

internal.uiNodes = {
    banPanels = {},
    banLists = {},
    banControls = {},
    bridalGlowPanels = {},
    domainTabs = {},
    rootViewTabs = {},
    rarityPanels = {},
    rarityBadges = {},
    forcePanels = {},
    npcRegionFilterPanel = nil,
    settingsPanel = nil,
}
local nodeCache = internal.uiNodes

local BANS_CONTROL_COLUMNS = {
    { name = "summary", start = 0, width = 120 },
    { name = "primary", start = 132, width = 88 },
    { name = "secondary", start = 228, width = 88 },
    { name = "filterLabel", start = 0, width = 48 },
    { name = "filterInput", start = 56, width = 180 },
    { name = "filterClear", start = 244, width = 72 },
    { name = "filterMode", start = 328 },
}

local BANS_PANEL_COLUMNS = {
    { name = "content", start = 0 },
}

local BRIDAL_GLOW_COLUMNS = {
    { name = "content", start = 0 },
}

local RARITY_COLUMNS = {
    { name = "label", start = 0 },
    { name = "control", start = 300, width = 120 },
}

local FORCE_COLUMNS = {
    { name = "label", start = 0 },
    { name = "control", start = 84, width = 220 },
    { name = "status", start = 320, width = 120 },
}

local SETTINGS_COLUMNS = {
    { name = "content", start = 0 },
}

local NPC_FILTER_COLUMNS = {
    { name = "content", start = 0 },
}

local ROOT_DETAIL_HEADER_COLUMNS = {
    { name = "title", start = 0 },
    { name = "summary", start = 220 },
}

local function PrepareNode(node, label)
    lib.prepareUiNode(
        node,
        label,
        internal.definition.storage,
        internal.definition.customTypes)
    return node
end

function uiData.GetRarityBadgeNode(alias)
    if type(alias) ~= "string" or alias == "" then
        return nil
    end

    local node = nodeCache.rarityBadges[alias]
    if node then
        return node
    end

    node = PrepareNode({
        type = "rarityBadge",
        binds = { value = alias },
    }, "BoonBans rarityBadge " .. alias)
    nodeCache.rarityBadges[alias] = node
    return node
end

function uiData.DrawRarityBadgeNode(ui, alias, uiState, rowKey)
    local node = uiData.GetRarityBadgeNode(alias)
    if not node then
        return false
    end

    ui.PushID(rowKey or alias)
    local changed = lib.drawUiNode(ui, node, uiState, nil, internal.definition.customTypes)
    ui.PopID()
    return changed
end

function uiData.GetRarityPanelNode(root)
    if type(root) ~= "table" or type(root.id) ~= "string" or root.id == "" then
        return nil
    end

    local node = nodeCache.rarityPanels[root.id]
    if node then
        return node
    end

    local children = {}
    for lineIndex, row in ipairs(uiData.GetRarityRows(root)) do
        if type(row.alias) == "string" and row.alias ~= "" then
            children[#children + 1] = {
                type = "text",
                text = row.name or row.key or row.alias,
                panel = { column = "label", line = lineIndex, slots = { "value" } },
            }
            children[#children + 1] = {
                type = "rarityBadge",
                binds = { value = row.alias },
                panel = { column = "control", line = lineIndex },
            }
        end
    end

    node = PrepareNode({
        type = "panel",
        columns = RARITY_COLUMNS,
        children = children,
    }, "BoonBans rarityPanel " .. root.id)
    nodeCache.rarityPanels[root.id] = node
    return node
end

function uiData.GetBanListNode(scopeKey)
    if type(scopeKey) ~= "string" or scopeKey == "" then
        return nil
    end

    local node = nodeCache.banLists[scopeKey]
    if node then
        return node
    end

    local rootAlias = internal.GetBanRootAlias(scopeKey)
    local slotCount = #uiData.GetBanRows(scopeKey)
    if type(rootAlias) ~= "string" or rootAlias == "" or slotCount < 1 then
        return nil
    end

    node = PrepareNode({
        type = "packedCheckboxList",
        binds = { value = rootAlias },
        slotCount = slotCount,
    }, "BoonBans banList " .. scopeKey)
    nodeCache.banLists[scopeKey] = node
    return node
end

local function BuildBanControlsPanelSpec(scopeKey)
    local displayValues = {}
    for _, filterMode in ipairs(uiData.BAN_FILTER_MODES) do
        displayValues[filterMode.id] = filterMode.label
    end

    return {
        type = "panel",
        columns = BANS_CONTROL_COLUMNS,
        children = {
            {
                type = "banSummary",
                scopeKey = scopeKey,
                panel = { column = "summary", line = 1, slots = { "value" } },
            },
            {
                type = "button",
                label = "Ban All",
                onClick = function(uiState)
                    internal.BanAllGodBans(scopeKey, uiState)
                end,
                panel = { column = "primary", line = 1, slots = { "control" } },
            },
            {
                type = "button",
                label = "Reset",
                onClick = function(uiState)
                    internal.ResetGodBans(scopeKey, uiState)
                end,
                panel = { column = "secondary", line = 1, slots = { "control" } },
            },
            {
                type = "text",
                text = "Filter:",
                panel = { column = "filterLabel", line = 2, slots = { "value" } },
            },
            {
                type = "inputText",
                binds = { value = uiData.BAN_FILTER_TEXT_ALIAS },
                panel = { column = "filterInput", line = 2, slots = { "control" } },
            },
            {
                type = "button",
                label = "Clear",
                onClick = function(uiState)
                    uiState.reset(uiData.BAN_FILTER_TEXT_ALIAS)
                    uiState.reset(uiData.BAN_FILTER_MODE_ALIAS)
                end,
                panel = { column = "filterClear", line = 2, slots = { "control" } },
            },
            {
                type = "radio",
                binds = { value = uiData.BAN_FILTER_MODE_ALIAS },
                label = "",
                values = { "all", "banned", "allowed", "special" },
                displayValues = displayValues,
                geometry = {
                    slots = {
                        { name = "option:1", line = 1, start = 0 },
                        { name = "option:2", line = 1, start = 56 },
                        { name = "option:3", line = 1, start = 136 },
                        { name = "option:4", line = 1, start = 220 },
                    },
                },
                panel = { column = "filterMode", line = 2 },
            },
        },
    }
end

function uiData.GetBanControlsPanelNode(scopeKey)
    if type(scopeKey) ~= "string" or scopeKey == "" then
        return nil
    end

    local node = nodeCache.banControls[scopeKey]
    if node then
        return node
    end

    node = PrepareNode(BuildBanControlsPanelSpec(scopeKey), "BoonBans banControls " .. scopeKey)
    nodeCache.banControls[scopeKey] = node
    return node
end

function uiData.GetBanPanelNode(scopeKey)
    if type(scopeKey) ~= "string" or scopeKey == "" then
        return nil
    end

    local node = nodeCache.banPanels[scopeKey]
    if node then
        return node
    end

    local children = {}
    children[#children + 1] = BuildBanControlsPanelSpec(scopeKey)
    children[#children].panel = { column = "content", line = 1 }
    children[#children + 1] = {
        type = "separator",
        panel = { column = "content", line = 2 },
    }
    children[#children + 1] = {
        type = "banList",
        scopeKey = scopeKey,
        panel = { column = "content", line = 3 },
    }

    node = PrepareNode({
        type = "panel",
        columns = BANS_PANEL_COLUMNS,
        children = children,
    }, "BoonBans banPanel " .. scopeKey)
    nodeCache.banPanels[scopeKey] = node
    return node
end

function uiData.GetBridalGlowPanelNode(root)
    if type(root) ~= "table" or type(root.id) ~= "string" or root.id == "" then
        return nil
    end

    local node = nodeCache.bridalGlowPanels[root.id]
    if node then
        return node
    end

    node = PrepareNode({
        type = "panel",
        columns = BRIDAL_GLOW_COLUMNS,
        children = {
            {
                type = "text",
                text = "Choose the Olympian god and boon pool Bridal Glow can target.",
                panel = { column = "content", line = 1, slots = { "value" } },
            },
            {
                type = "bridalGlowSummary",
                panel = { column = "content", line = 2, slots = { "value" } },
            },
            {
                type = "bridalGlowPicker",
                panel = { column = "content", line = 3, slots = { "value" } },
            },
        },
    }, "BoonBans bridalGlowPanel " .. root.id)
    nodeCache.bridalGlowPanels[root.id] = node
    return node
end

function uiData.GetRootViewsTabsNode(root)
    if type(root) ~= "table" or type(root.id) ~= "string" or root.id == "" then
        return nil
    end

    local node = nodeCache.rootViewTabs[root.id]
    if node then
        return node
    end

    local children = {}
    for index, view in ipairs(root.views or {}) do
        local child = nil
        if view.kind == "force" then
            child = uiData.GetForcePanelNode(root)
        elseif view.kind == "bans" then
            child = uiData.GetBanPanelNode(view.scopeKey or root.primaryScopeKey)
        elseif view.kind == "bridal_glow" then
            child = uiData.GetBridalGlowPanelNode(root)
        elseif view.kind == "rarity" then
            local rarityRows = uiData.GetRarityRows(root)
            if #rarityRows == 0 then
                child = {
                    type = "disabledText",
                    text = "No rarity-configurable boons for this root.",
                }
            elseif root.isTiered then
                child = {
                    type = "group",
                    children = {
                        {
                            type = "disabledText",
                            text = "Rarity applies across all tiers for this root.",
                        },
                        {
                            type = "separator",
                        },
                        uiData.GetRarityPanelNode(root),
                    },
                }
            else
                child = uiData.GetRarityPanelNode(root)
            end
        end

        if child then
            child.tabLabel = view.label
            child.tabId = tostring(index) .. "::" .. tostring(view.kind or view.label or "view")
            children[#children + 1] = child
        end
    end

    node = PrepareNode({
        type = "horizontalTabs",
        id = "RootViews##" .. root.id,
        children = children,
    }, "BoonBans rootViewsTabs " .. root.id)
    nodeCache.rootViewTabs[root.id] = node
    return node
end

function uiData.GetForcePanelNode(root)
    if type(root) ~= "table" or type(root.id) ~= "string" or root.id == "" then
        return nil
    end

    local node = nodeCache.forcePanels[root.id]
    if node then
        return node
    end

    local children = {}
    for lineIndex, scope in ipairs(root.scopes or {}) do
        local bindAlias = internal.GetBanRootAlias(scope.key)
        if bindAlias then
            children[#children + 1] = {
                type = "text",
                text = scope.label,
                panel = { column = "label", line = lineIndex, slots = { "value" } },
            }
            children[#children + 1] = {
                type = "mappedDropdown",
                binds = { value = bindAlias },
                getPreview = function(_, bound)
                    local currentMask = bound.value:get() or 0
                    local forcedBoon, isNone, isCustom = uiData.GetForcedBoonSelection(scope.key, currentMask)
                    return isNone and "None"
                        or isCustom and "<custom>"
                        or uiData.GetForcedBoonDisplayLabel(forcedBoon)
                end,
                getOptions = function(_, bound)
                    local meta = uiData.GetRootMeta(scope.key)
                    local packedConfig = meta and meta.packedConfig or nil
                    local fullMask = packedConfig and (lshift(1, packedConfig.bits) - 1) or 0
                    local currentMask = bound.value:get() or 0
                    local forcedBoon, isNone = uiData.GetForcedBoonSelection(scope.key, currentMask)
                    local options = {
                        {
                            label = "None",
                            selected = isNone == true,
                            onSelect = function(_, boundValue)
                                if currentMask ~= 0 then
                                    boundValue:set(0)
                                    return true
                                end
                                return false
                            end,
                        },
                    }
                    for _, boon in ipairs(uiData.GetScopeBoons(scope.key)) do
                        options[#options + 1] = {
                            label = uiData.GetForcedBoonDisplayLabel(boon),
                            selected = forcedBoon and boon.Key == forcedBoon.Key or false,
                            onSelect = function(_, boundValue)
                                local nextMask = band(fullMask, bnot(boon.Mask))
                                if nextMask ~= currentMask then
                                    boundValue:set(nextMask)
                                    return true
                                end
                                return false
                            end,
                        }
                    end
                    return options
                end,
                panel = { column = "control", line = lineIndex, slots = { "control" } },
            }
            children[#children + 1] = {
                type = "forceStatus",
                binds = { value = bindAlias },
                scopeKey = scope.key,
                rarityScopeKey = root.hasRarity and root.primaryScopeKey or nil,
                panel = { column = "status", line = lineIndex, slots = { "value" } },
            }
        end
    end

    node = PrepareNode({
        type = "panel",
        columns = FORCE_COLUMNS,
        children = children,
    }, "BoonBans forcePanel " .. root.id)
    nodeCache.forcePanels[root.id] = node
    return node
end

function uiData.GetSettingsPanelNode()
    if nodeCache.settingsPanel then
        return nodeCache.settingsPanel
    end

    local node = PrepareNode({
        type = "panel",
        columns = SETTINGS_COLUMNS,
        children = {
            {
                type = "checkbox",
                binds = { value = "EnablePadding" },
                label = "Enable Padding",
                panel = { column = "content", line = 1, slots = { "control" } },
            },
            {
                type = "disabledText",
                text = "Fills up menus to ensure enough options are available.",
                panel = { column = "content", line = 2, slots = { "value" } },
            },
            {
                type = "paddingOptions",
                panel = { column = "content", line = 3, slots = { "value" } },
            },
            {
                type = "separator",
                panel = { column = "content", line = 4 },
            },
            {
                type = "stepper",
                binds = { value = "ImproveFirstNBoonRarity" },
                label = "Improve N Boon Rarity to Epic",
                min = 0,
                max = 15,
                step = 1,
                panel = { column = "content", line = 5, slots = { "label", "decrement", "value", "increment" } },
            },
            {
                type = "disabledText",
                text = "(Improve the rarity of offered boons unless specifically forced by config.)",
                panel = { column = "content", line = 6, slots = { "value" } },
            },
            {
                type = "separator",
                panel = { column = "content", line = 7 },
            },
            {
                type = "dangerButton",
                actionId = "reset_all_bans",
                buttonLabel = "RESET ALL BANS (Global)",
                confirmLabel = "Confirm RESET ALL BANS",
                onConfirm = function(uiState)
                    if internal.ResetAllBans(uiState) then
                        internal.RecalculateBannedCounts(uiState)
                    end
                end,
                panel = { column = "content", line = 8, slots = { "control" } },
            },
            {
                type = "dangerButton",
                actionId = "reset_all_rarity",
                buttonLabel = "RESET ALL RARITY (Global)",
                confirmLabel = "Confirm RESET ALL RARITY",
                onConfirm = function(uiState)
                    internal.ResetAllRarity(uiState)
                end,
                panel = { column = "content", line = 9, slots = { "control" } },
            },
        },
    }, "BoonBans settingsPanel")
    nodeCache.settingsPanel = node
    return node
end

function uiData.GetNpcRegionFilterPanelNode()
    if nodeCache.npcRegionFilterPanel then
        return nodeCache.npcRegionFilterPanel
    end

    local node = PrepareNode({
        type = "panel",
        columns = NPC_FILTER_COLUMNS,
        children = {
            {
                type = "npcRegionFilter",
                panel = { column = "content", line = 1, slots = { "value" } },
            },
        },
    }, "BoonBans npcRegionFilterPanel")
    nodeCache.npcRegionFilterPanel = node
    return node
end

local function BuildRootDetailHeaderSpec(root, uiState)
    local headerChildren = {
        {
            type = "text",
            text = root.displayLabel,
            color = uiData.GetSourceColor(root.primaryScopeKey),
            panel = { column = "title", line = 1, slots = { "value" } },
        },
    }

    local headerSummary = uiData.GetRootHeaderSummary(root, uiState)
    if type(headerSummary) == "string" and headerSummary ~= "" then
        headerChildren[#headerChildren + 1] = {
            type = "disabledText",
            text = headerSummary,
            panel = { column = "summary", line = 1, slots = { "value" } },
        }
    end

    return {
        type = "panel",
        columns = ROOT_DETAIL_HEADER_COLUMNS,
        children = headerChildren,
    }
end

local function BuildRootDetailSpec(root, uiState)
    local children = {
        BuildRootDetailHeaderSpec(root, uiState),
        { type = "separator" },
    }

    if root.isTiered or root.hasRarity then
        children[#children + 1] = uiData.GetRootViewsTabsNode(root)
    else
        children[#children + 1] = uiData.GetBanPanelNode(root.primaryScopeKey)
    end

    return {
        type = "group",
        tabLabel = uiData.GetSelectorLabel(root, uiState),
        tabId = root.id,
        children = children,
    }
end

function uiData.GetDomainTabsNode(tabName, visibleRoots, uiState)
    if type(tabName) ~= "string" or tabName == "" then
        return nil
    end

    local signatureParts = { tabName }
    for _, root in ipairs(visibleRoots or uiData.EMPTY_LIST) do
        signatureParts[#signatureParts + 1] = root.id
        signatureParts[#signatureParts + 1] = uiData.GetSelectorLabel(root, uiState)
        signatureParts[#signatureParts + 1] = uiData.GetRootHeaderSummary(root, uiState) or ""
    end
    local signature = table.concat(signatureParts, "|")

    local cached = nodeCache.domainTabs[tabName]
    if cached and cached.signature == signature then
        return cached.node
    end

    local children = {}
    for _, root in ipairs(visibleRoots or uiData.EMPTY_LIST) do
        children[#children + 1] = BuildRootDetailSpec(root, uiState)
    end

    local node = PrepareNode({
        type = "verticalTabs",
        id = "BoonBansDomain##" .. tabName,
        sidebarWidth = 260,
        children = children,
    }, "BoonBans domainTabs " .. tabName)

    nodeCache.domainTabs[tabName] = {
        signature = signature,
        node = node,
    }
    return node
end
