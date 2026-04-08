local internal = RunDirectorBoonBans_Internal
local uiData = internal.ui

local band = bit32.band
local bnot = bit32.bnot
local bor = bit32.bor
local ImGuiCol = rom.ImGuiCol

local FORCE_DROPDOWN_OFFSET = 84
local FORCE_DROPDOWN_WIDTH = 220
local RARITY_CONTROL_OFFSET = 300

local function GetForceScopeState(scopeKey, uiState)
    local banned, total = uiData.GetScopeSummary(scopeKey, uiState)
    if banned == 0 then
        return nil, true
    end
    if total == 0 or banned ~= (total - 1) then
        return nil, false
    end

    local currentBans = internal.GetBanConfig(scopeKey, uiState)

    for _, boon in ipairs(uiData.GetScopeBoons(scopeKey)) do
        if band(currentBans, boon.Mask) == 0 then
            return boon.Key, false
        end
    end

    return nil, true
end

local function GetSpecialBoonDisplay(boon)
    return boon.SpecialDisplayLabel or uiData.GetBoonText(boon), boon.SpecialBadgeColor, boon.SpecialTooltip
end

function uiData.GetBoonText(boon)
    return boon.Name or boon.Key or ""
end

function uiData.DoesBoonPassBanFilter(boon, isBanned)
    local filterText = uiData.banFilterState.textLower or ""
    if filterText ~= "" then
        local boonText = boon.NameLower or string.lower(uiData.GetBoonText(boon))
        if not boonText:find(filterText, 1, true) then
            return false
        end
    end

    if uiData.banFilterState.mode == "banned" then
        return isBanned
    end
    if uiData.banFilterState.mode == "allowed" then
        return not isBanned
    end
    if uiData.banFilterState.mode == "special" then
        return uiData.IsSpecialBoon(boon)
    end
    return true
end

function uiData.BuildRarityRows(root)
    local rows = {}
    for _, boon in ipairs(uiData.GetScopeBoons(root.primaryScopeKey)) do
        if uiData.IsRarityEligibleBoon(boon) then
            table.insert(rows, {
                key = boon.Key,
                name = uiData.GetBoonText(boon),
                bit = boon.Bit,
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

local RARITY_BADGE_NODE = {
    type = "rarityBadge",
}

lib.prepareWidgetNode(RARITY_BADGE_NODE, "BoonBans rarityBadge", internal.definition.customTypes)

function uiData.DrawRarityStepper(ui, root, row, uiState, options)
    options = options or {}
    local rarityWidget = internal.definition.customTypes
        and internal.definition.customTypes.widgets
        and internal.definition.customTypes.widgets.rarityBadge
    if not rarityWidget then return end
    local syntheticBound = {
        value = {
            get = function(_) return internal.GetRarityValue(root.primaryScopeKey, row.bit, uiState) end,
            set = function(_, val) internal.SetRarityValue(root.primaryScopeKey, row.bit, val, uiState) end,
        },
    }
    ui.PushID("rarity_" .. row.key)
    if not options.compact then
        ui.Text(row.name)
        ui.SameLine(RARITY_CONTROL_OFFSET)
    end
    rarityWidget.draw(ui, RARITY_BADGE_NODE, syntheticBound)
    ui.PopID()
end

function uiData.DrawBanFilterControls(ui, root)
    local winW = ui.GetWindowWidth()
    ui.Text("Filter:")
    ui.SameLine()
    ui.PushItemWidth(winW * 0.26)
    local newText, changed = ui.InputText("##BoonFilter_" .. root.id, uiData.banFilterState.text or "", 128)
    ui.PopItemWidth()
    if changed then
        uiData.banFilterState.text = newText
        uiData.banFilterState.textLower = string.lower(newText or "")
    end

    for _, filterMode in ipairs(uiData.BAN_FILTER_MODES) do
        ui.SameLine()
        if ui.RadioButton(filterMode.label, uiData.banFilterState.mode == filterMode.id) then
            uiData.banFilterState.mode = filterMode.id
        end
    end
end

function uiData.DrawForceView(ui, root, uiState)
    for _, scope in ipairs(root.scopes) do
        local forcedKey, isNone = GetForceScopeState(scope.key, uiState)
        local preview = isNone and "None" or "<custom>"
        local selectedKey = forcedKey

        if forcedKey then
            local forcedBoon = uiData.FindBoonByKey(scope.key, forcedKey)
            if forcedBoon then
                preview = GetSpecialBoonDisplay(forcedBoon)
                selectedKey = forcedKey
            end
        end

        ui.PushID("force_" .. scope.key)
        ui.TextDisabled(scope.label)
        ui.SameLine(FORCE_DROPDOWN_OFFSET)
        ui.PushItemWidth(FORCE_DROPDOWN_WIDTH)
        if ui.BeginCombo("##ForceSelect", preview) then
            if ui.Selectable("None", isNone) then
                if internal.ResetGodBans(scope.key, uiState) then
                    selectedKey = nil
                    forcedKey = nil
                end
            end
            for _, boon in ipairs(uiData.GetScopeBoons(scope.key)) do
                local label, accentColor = GetSpecialBoonDisplay(boon)
                if accentColor then
                    ui.PushStyleColor(ImGuiCol.Text, accentColor[1], accentColor[2], accentColor[3], accentColor[4])
                end
                if ui.Selectable(label, boon.Key == selectedKey) then
                    uiData.ApplyForceOne(scope.key, boon.Key, uiState)
                    selectedKey = boon.Key
                    forcedKey = boon.Key
                end
                if accentColor then
                    ui.PopStyleColor()
                end
            end
            ui.EndCombo()
        end
        ui.PopItemWidth()

        if forcedKey then
            local forcedBoon = uiData.FindBoonByKey(scope.key, forcedKey)
            if forcedBoon and root.hasRarity and uiData.IsRarityEligibleBoon(forcedBoon) then
                ui.SameLine()
                uiData.DrawRarityStepper(ui, root, {
                    key = scope.key .. "::" .. forcedBoon.Key,
                    bit = forcedBoon.Bit,
                }, uiState, {
                    compact = true,
                })
            elseif forcedBoon then
                local _, badgeColor, badgeTooltip = GetSpecialBoonDisplay(forcedBoon)
                if badgeColor then
                    ui.SameLine()
                    uiData.DrawBadge(ui, forcedBoon.SpecialBadgeText or " ? ", badgeColor, badgeTooltip)
                end
            end
        end

        ui.PopID()
    end
end

function uiData.DrawBansView(ui, root, scopeKey, uiState)
    uiData.EnsureBanFilterRoot(root)

    local currentBans = internal.GetBanConfig(scopeKey, uiState)
    local scopeBanned, scopeTotal = uiData.GetScopeSummary(scopeKey, uiState)
    local dirty = false
    local anyVisible = false

    ui.TextDisabled(uiData.FormatCountLabel(scopeBanned, scopeTotal))
    ui.SameLine()
    if ui.Button("Ban All##" .. scopeKey) then
        if internal.BanAllGodBans(scopeKey, uiState) then
            currentBans = internal.GetBanConfig(scopeKey, uiState)
            dirty = true
        end
    end
    ui.SameLine()
    if ui.Button("Reset##" .. scopeKey) then
        if internal.ResetGodBans(scopeKey, uiState) then
            currentBans = internal.GetBanConfig(scopeKey, uiState)
            dirty = true
        end
    end
    ui.Separator()

    uiData.DrawBanFilterControls(ui, root)
    ui.Separator()

    for _, boon in ipairs(uiData.GetScopeBoons(scopeKey)) do
        local isBanned = band(currentBans, boon.Mask) ~= 0
        if uiData.DoesBoonPassBanFilter(boon, isBanned) then
            anyVisible = true
            ui.PushID(scopeKey .. "::" .. boon.Key)
            local checked, changed = ui.Checkbox("##Ban", isBanned)
            if changed then
                if checked then
                    currentBans = bor(currentBans, boon.Mask)
                else
                    currentBans = band(currentBans, bnot(boon.Mask))
                end
                dirty = true
            end
            ui.SameLine()

            local drewVisual = false
            if boon.IsSpecial and boon.SpecialBadgeColor then
                uiData.DrawBadge(ui, boon.SpecialBadgeText or " ? ", boon.SpecialBadgeColor, boon.SpecialTooltip)
                drewVisual = true
            end

            if drewVisual then
                ui.SameLine()
            end
            ui.Text(uiData.GetBoonText(boon))
            ui.PopID()
        end
    end

    if dirty then
        if internal.SetBanConfig(scopeKey, currentBans, uiState) then
            internal.UpdateGodStats(scopeKey, uiState)
        end
    end

    if not anyVisible then
        ui.TextDisabled("No boons match the current filter.")
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

    for _, row in ipairs(rows) do
        uiData.DrawRarityStepper(ui, root, row, uiState)
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

function uiData.DrawNpcRegionFilter(ui)
    ui.Text("Filter NPC Sources:")
    local currentRegion = store.read("ViewRegion") or 4
    for index, option in ipairs(uiData.NPC_REGION_OPTIONS) do
        if ui.RadioButton(option.label, currentRegion == option.value) then
            store.write("ViewRegion", option.value)
            currentRegion = option.value
        end
        if index < #uiData.NPC_REGION_OPTIONS then
            ui.SameLine()
        end
    end
end

local function GetBridalGlowEligibleRoots()
    if uiData.bridalGlowEligibleRoots then
        return uiData.bridalGlowEligibleRoots
    end

    local roots = uiData.GetVisibleRoots("Olympians")
    local cached = {}
    for i, root in ipairs(roots) do
        cached[i] = root
    end
    uiData.bridalGlowEligibleRoots = cached
    return cached
end

local function GetBridalGlowEligibleBoons(root)
    if not root then
        return uiData.EMPTY_LIST
    end

    local cached = uiData.bridalGlowBoonsByRoot[root.id]
    if cached then
        return cached
    end

    local boons = {}
    for _, boon in ipairs(uiData.GetScopeBoons(root.primaryScopeKey)) do
        if uiData.IsBridalGlowEligibleBoon(boon) then
            boon.BridalGlowLabel = boon.BridalGlowLabel or uiData.GetBoonText(boon)
            table.insert(boons, boon)
        end
    end
    uiData.bridalGlowBoonsByRoot[root.id] = boons
    return boons
end

local function FindBridalGlowRootForTarget(roots, selectedBoonKey)
    if not selectedBoonKey or selectedBoonKey == "" then
        return nil
    end

    for _, root in ipairs(roots) do
        local boon = uiData.FindBoonByKey(root.primaryScopeKey, selectedBoonKey)
        if boon and uiData.IsBridalGlowEligibleBoon(boon) then
            return root
        end
    end
    return nil
end

local function EnsureBridalGlowRootSelection(roots, selectedBoonKey)
    local transientRootKey = uiData.bridalGlowSelection.rootKey
    if transientRootKey then
        for _, root in ipairs(roots) do
            if root.rootKey == transientRootKey then
                return root
            end
        end
    end

    local matchedRoot = FindBridalGlowRootForTarget(roots, selectedBoonKey)
    if matchedRoot then
        uiData.bridalGlowSelection.rootKey = matchedRoot.rootKey
        return matchedRoot
    end

    local fallback = roots[1]
    uiData.bridalGlowSelection.rootKey = fallback and fallback.rootKey or nil
    return fallback
end

function uiData.DrawBridalGlowControls(ui, uiState)
    local paneHeight = 220
    local godPaneWidth = 200
    ui.TextDisabled("Choose the Olympian god and boon pool Bridal Glow can target.")

    local selectedBoonKey = uiState.view.BridalGlowTargetBoon or ""
    local eligibleRoots = GetBridalGlowEligibleRoots()
    if #eligibleRoots == 0 then
        ui.TextDisabled("No eligible Olympian gods are currently available.")
        return
    end

    local selectedRoot = EnsureBridalGlowRootSelection(eligibleRoots, selectedBoonKey)
    local selectedRootKey = selectedRoot and selectedRoot.rootKey or nil

    local currentTarget = nil
    if selectedBoonKey ~= "" then
        for _, root in ipairs(eligibleRoots) do
            currentTarget = uiData.FindBoonByKey(root.primaryScopeKey, selectedBoonKey)
            if currentTarget and uiData.IsBridalGlowEligibleBoon(currentTarget) then
                currentTarget.BridalGlowLabel = currentTarget.BridalGlowLabel or uiData.GetBoonText(currentTarget)
                break
            end
            currentTarget = nil
        end
    end

    local eligibleBoons = GetBridalGlowEligibleBoons(selectedRoot)

    if currentTarget then
        ui.Text("Current Target:")
        ui.SameLine()
        ui.TextDisabled(currentTarget.BridalGlowLabel)
    else
        ui.TextDisabled("Current Target: Random")
    end

    ui.BeginChild("##BridalGlowGodList", godPaneWidth, paneHeight, true)
    ui.TextDisabled("Eligible Gods")
    ui.Separator()
    for _, root in ipairs(eligibleRoots) do
        if ui.Selectable(root.displayLabel, root.rootKey == selectedRootKey) then
            uiData.bridalGlowSelection.rootKey = root.rootKey
            selectedRoot = root
            selectedRootKey = root.rootKey
            eligibleBoons = GetBridalGlowEligibleBoons(selectedRoot)
        end
    end
    ui.EndChild()

    ui.SameLine()
    ui.BeginChild("##BridalGlowBoonList", 0, paneHeight, true)
    ui.TextDisabled("Eligible Boons")
    ui.Separator()
    if ui.Selectable("Random", selectedBoonKey == "") then
        selectedBoonKey = ""
        internal.SetBridalGlowTargetBoonKey(nil, uiState)
    end
    for _, boon in ipairs(eligibleBoons) do
        if ui.Selectable(boon.BridalGlowLabel, boon.Key == selectedBoonKey) then
            selectedBoonKey = boon.Key
            internal.SetBridalGlowTargetBoonKey(boon.Key, uiState)
        end
    end
    ui.EndChild()
end

function uiData.DrawSettingsTab(ui, uiState)
    local view = uiState.view
    local padVal, padChanged = ui.Checkbox("Enable Padding", view.EnablePadding == true)
    if padChanged then uiState.set("EnablePadding", padVal) end
    ui.TextDisabled("Fills up menus to ensure enough options are available.")

    if view.EnablePadding == true then
        ui.Indent()
        uiData.DrawStepInput(ui, uiState, "Prioritize Core Boons for First N", "Padding_PrioritizeCoreForFirstN", 0, 15, 1)
        ui.TextDisabled("(0 = disabled, N = prefer core boons in padding for the first N picks from each god.)")

        local futureVal, futureChanged = ui.Checkbox("Avoid 'Future Allowed' Items",
            view.Padding_AvoidFutureAllowed ~= false)
        if futureChanged then uiState.set("Padding_AvoidFutureAllowed", futureVal) end

        local duoVal, duoChanged = ui.Checkbox("Allow Banned Duos/Legendaries", view.Padding_AllowDuos == true)
        if duoChanged then uiState.set("Padding_AllowDuos", duoVal) end
        ui.Unindent()
    end

    ui.Separator()
    uiData.DrawStepInput(ui, uiState, "Improve N Boon Rarity to Epic", "ImproveFirstNBoonRarity", 0, 15, 1)
    ui.TextDisabled("(Improve the rarity of offered boons unless specifically forced by config.)")

    ui.Separator()
    uiData.DrawDangerAction(ui, "reset_all_bans", "RESET ALL BANS (Global)", "Confirm RESET ALL BANS", function()
        if internal.ResetAllBans(uiState) then
            internal.RecalculateBannedCounts(uiState)
        end
    end)
    uiData.DrawDangerAction(ui, "reset_all_rarity", "RESET ALL RARITY (Global)", "Confirm RESET ALL RARITY", function()
        internal.ResetAllRarity(uiState)
    end)
end
