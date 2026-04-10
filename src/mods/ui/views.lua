local internal = RunDirectorBoonBans_Internal
local uiData = internal.ui

function uiData.GetBoonText(boon)
    return boon.Name or boon.Key or ""
end

function uiData.GetBanFilterText(uiState)
    return tostring(uiState and uiState.view and uiState.view[uiData.BAN_FILTER_TEXT_ALIAS] or "")
end

function uiData.GetBanFilterTextLower(uiState)
    return string.lower(uiData.GetBanFilterText(uiState))
end

function uiData.GetBanFilterMode(uiState)
    local mode = tostring(uiState and uiState.view and uiState.view[uiData.BAN_FILTER_MODE_ALIAS] or "all")
    if uiData.BAN_FILTER_MODE_SET[mode] == true then
        return mode
    end
    return "all"
end

function uiData.DoesBoonPassBanFilter(boon, isBanned, uiState)
    local filterText = uiData.GetBanFilterTextLower(uiState)
    if filterText ~= "" then
        local boonText = boon.NameLower or string.lower(uiData.GetBoonText(boon))
        if not boonText:find(filterText, 1, true) then
            return false
        end
    end

    local filterMode = uiData.GetBanFilterMode(uiState)
    if filterMode == "banned" then
        return isBanned
    end
    if filterMode == "allowed" then
        return not isBanned
    end
    if filterMode == "special" then
        return uiData.IsSpecialBoon(boon)
    end
    return true
end

function uiData.BuildBanRows(scopeKey)
    local rows = {}
    for _, boon in ipairs(uiData.GetScopeBoons(scopeKey)) do
        table.insert(rows, {
            key = boon.Key,
            name = uiData.GetBoonText(boon),
            alias = internal.GetBanAlias(scopeKey, boon.Key),
            tooltip = boon.SpecialTooltip,
            panelKeys = {
                toggle = boon.Key .. "::toggle",
                label = boon.Key .. "::label",
            },
            boon = boon,
        })
    end
    return rows
end

function uiData.GetBanRows(scopeKey)
    local rows = uiData.banRowsByScope[scopeKey]
    if not rows then
        rows = uiData.BuildBanRows(scopeKey)
        uiData.banRowsByScope[scopeKey] = rows
    end
    return rows
end

function uiData.BuildRarityRows(root)
    local rows = {}
    for _, boon in ipairs(uiData.GetScopeBoons(root.primaryScopeKey)) do
        if uiData.IsRarityEligibleBoon(boon) then
            table.insert(rows, {
                key = boon.Key,
                name = uiData.GetBoonText(boon),
                alias = internal.GetRarityAlias(root.primaryScopeKey, boon.Key),
            })
        end
    end
    return rows
end

function uiData.GetRarityRows(root)
    local rows = uiData.rarityRowsByRoot[root.id]
    if not rows then
        rows = uiData.BuildRarityRows(root)
        uiData.rarityRowsByRoot[root.id] = rows
    end
    return rows
end

function uiData.DrawForceView(ui, root, uiState)
    local panelNode = uiData.GetForcePanelNode(root)
    if panelNode then
        ui.PushID("force_" .. root.id)
        if lib.drawUiNode(ui, panelNode, uiState, nil, internal.definition.customTypes) then
            for _, scope in ipairs(root.scopes) do
                internal.UpdateGodStats(scope.key, uiState)
            end
        end
        ui.PopID()
    end
end

function uiData.DrawBansView(ui, root, scopeKey, uiState)
    uiData.EnsureBanFilterRoot(root, uiState)

    local initialBans = internal.GetBanConfig(scopeKey, uiState)
    local panelNode = uiData.GetBanPanelNode(scopeKey)
    if panelNode then
        ui.PushID("bans_" .. scopeKey)
        lib.drawUiNode(ui, panelNode, uiState, nil, internal.definition.customTypes)
        ui.PopID()
    end

    local currentBans = internal.GetBanConfig(scopeKey, uiState)
    if currentBans ~= initialBans then
        internal.UpdateGodStats(scopeKey, uiState)
    end
end

function uiData.DrawRarityView(ui, root, uiState)
    if root.isTiered then
        ui.TextDisabled("Rarity applies across all tiers for this root.")
        ui.Separator()
    end

    local rows = uiData.GetRarityRows(root)
    if #rows == 0 then
        ui.TextDisabled("No rarity-configurable boons for this root.")
        return
    end

    local panelNode = uiData.GetRarityPanelNode(root)
    if panelNode then
        ui.PushID("rarity_" .. root.id)
        lib.drawUiNode(ui, panelNode, uiState, nil, internal.definition.customTypes)
        ui.PopID()
    end
end

function uiData.ExpirePendingDanger()
    if uiData.pendingDanger and os.clock() >= uiData.pendingDanger.expiresAt then
        uiData.pendingDanger = nil
    end
end

function uiData.ArmDangerAction(actionId)
    uiData.pendingDanger = {
        action = actionId,
        expiresAt = os.clock() + uiData.CONFIRM_TIMEOUT,
    }
end

function uiData.DrawDangerAction(ui, actionId, buttonLabel, confirmLabel, onConfirm)
    uiData.ExpirePendingDanger()

    if uiData.pendingDanger and uiData.pendingDanger.action == actionId then
        if ui.Button(confirmLabel .. "##" .. actionId) then
            uiData.pendingDanger = nil
            onConfirm()
            return
        end
        ui.SameLine()
        if ui.Button("Cancel##" .. actionId) then
            uiData.pendingDanger = nil
            return
        end
        ui.SameLine()
        local remaining = math.max(0, uiData.pendingDanger.expiresAt - os.clock())
        ui.TextDisabled(string.format("Confirmation expires in %.1fs", remaining))
        return
    end

    if ui.Button(buttonLabel .. "##" .. actionId) then
        uiData.ArmDangerAction(actionId)
    end
end

function uiData.DrawNpcRegionFilter(ui, uiState)
    local panelNode = uiData.GetNpcRegionFilterPanelNode()
    if panelNode then
        ui.PushID("npc_region_filter")
        lib.drawUiNode(ui, panelNode, uiState, nil, internal.definition.customTypes)
        ui.PopID()
    end
end

function uiData.DrawBridalGlowView(ui, root, uiState)
    local panelNode = uiData.GetBridalGlowPanelNode(root)
    if panelNode then
        ui.PushID("bridal_glow_" .. root.id)
        lib.drawUiNode(ui, panelNode, uiState, nil, internal.definition.customTypes)
        ui.PopID()
    end
end

function uiData.DrawSettingsTab(ui, uiState)
    local panelNode = uiData.GetSettingsPanelNode()
    if panelNode then
        ui.PushID("settings")
        lib.drawUiNode(ui, panelNode, uiState, nil, internal.definition.customTypes)
        ui.PopID()
    end
end
