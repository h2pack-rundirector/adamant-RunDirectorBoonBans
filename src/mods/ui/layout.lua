local internal = RunDirectorBoonBans_Internal
local uiData = internal.ui

function uiData.DrawDomainTab(ui, uiState, tabName)
    if tabName == "NPCs" then
        uiData.DrawNpcRegionFilter(ui, uiState)
        ui.Separator()
    end

    local visibleRoots, totalCount, godPoolFiltering = uiData.GetVisibleRoots(tabName, uiState)
    if tabName == "Olympians" and godPoolFiltering then
        ui.TextDisabled(string.format("Showing %d/%d Olympians enabled in God Pool.", #visibleRoots, totalCount))
        ui.Separator()
    end

    local selectedRoot = uiData.EnsureSelectedRoot(tabName, visibleRoots, uiState)
    if not selectedRoot then
        ui.TextDisabled("No entries available.")
        return
    end
    if selectedRoot.id == "Hera" and uiData.activeBridalGlowRootId ~= selectedRoot.id then
        uiData.InvalidateBridalGlowRootCache()
        uiData.activeBridalGlowRootId = selectedRoot.id
    end

    local domainNode = uiData.GetDomainTabsNode(tabName, visibleRoots, uiState)
    if domainNode then
        domainNode._activeTabKey = selectedRoot.id
        ui.PushID("domain_" .. tabName)
        local changed = lib.drawUiNode(ui, domainNode, uiState, nil, internal.definition.customTypes)
        ui.PopID()

        local activeRootId = domainNode._activeTabKey
        if type(activeRootId) == "string" and activeRootId ~= "" and activeRootId ~= selectedRoot.id then
            uiData.SelectRoot(tabName, activeRootId, uiState)
            selectedRoot = uiData.GetRootById(activeRootId) or selectedRoot
            if selectedRoot.id == "Hera" and uiData.activeBridalGlowRootId ~= selectedRoot.id then
                uiData.InvalidateBridalGlowRootCache()
                uiData.activeBridalGlowRootId = selectedRoot.id
            end
        end

        if changed and selectedRoot then
            for _, scope in ipairs(selectedRoot.scopes or uiData.EMPTY_LIST) do
                internal.UpdateGodStats(scope.key, uiState)
            end
        end
    end
end

function uiData.DrawMainContent(ui, uiState)
    if ui.BeginTabBar("BoonSubTabs") then
        for _, tabName in ipairs(uiData.MAIN_TABS) do
            if ui.BeginTabItem(tabName) then
                if tabName == "Settings" then
                    uiData.DrawSettingsTab(ui, uiState)
                else
                    uiData.DrawDomainTab(ui, uiState, tabName)
                end
                ui.EndTabItem()
            end
        end
        ui.EndTabBar()
    end
end

function internal.DrawTab(ui, uiState)
    uiData.RefreshFrameState()
    uiData.DrawMainContent(ui, uiState)
end

function internal.DrawQuickContent(ui, uiState, theme)
    local colors = uiData.GetThemeColors(theme)
    local totalBans = internal.GetTotalBansConfigured()
    local customizedRoots = uiData.GetCustomizedRootCount(uiState)
    uiData.DrawColoredText(ui, colors.info, "Boon Bans")
    ui.Text(string.format("%d total bans configured", totalBans))
    ui.Text(string.format("%d roots customized", customizedRoots))
    local padVal, padChanged = ui.Checkbox("Padding Enabled##QuickBoonBans", uiState.view.EnablePadding == true)
    if padChanged then
        uiState.set("EnablePadding", padVal)
    end
    uiData.DrawDangerAction(ui, "quick_reset_all", "Reset All", "Confirm Reset All", function()
        local bansChanged = internal.ResetAllBans(uiState)
        internal.ResetAllRarity(uiState)
        if bansChanged then
            internal.RecalculateBannedCounts(uiState)
        end
    end)
end
