local internal = RunDirectorBoonBans_Internal
local uiData = internal.ui

local function GetBridalGlowEligibleRoots(uiState)
    if uiData.bridalGlowEligibleRoots then
        return uiData.bridalGlowEligibleRoots
    end

    local roots = uiData.GetVisibleRoots("Olympians", uiState)
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

local function GetCurrentBridalGlowTarget(eligibleRoots, selectedBoonKey)
    if selectedBoonKey == nil or selectedBoonKey == "" then
        return nil
    end

    for _, root in ipairs(eligibleRoots) do
        local boon = uiData.FindBoonByKey(root.primaryScopeKey, selectedBoonKey)
        if boon and uiData.IsBridalGlowEligibleBoon(boon) then
            boon.BridalGlowLabel = boon.BridalGlowLabel or uiData.GetBoonText(boon)
            return boon
        end
    end
    return nil
end

public.definition.customTypes = {
    widgets = {
        banSummary = {
            binds = {},
            slots = { "value" },
            validate = function(node, _)
                if type(node.scopeKey) ~= "string" or node.scopeKey == "" then
                    node.scopeKey = nil
                end
            end,
            draw = function(ui, node, _, _, uiState)
                if not node.scopeKey then
                    return false
                end
                local banned, total = uiData.GetScopeSummary(node.scopeKey, uiState)
                local text = uiData.FormatCountLabel(banned, total)
                return lib.drawWidgetSlots(ui, node, {
                    {
                        name = "value",
                        draw = function(imgui, slot)
                            lib.alignSlotContent(imgui, slot,
                                type(imgui.CalcTextSize) == "function" and imgui.CalcTextSize(text) or #(tostring(text)))
                            imgui.TextDisabled(text)
                            return false
                        end,
                    },
                })
            end,
        },
        disabledText = {
            binds = {},
            slots = { "value" },
            validate = function(node, _)
                if type(node.text) ~= "string" then
                    node.text = tostring(node.text or "")
                end
            end,
            draw = function(ui, node)
                return lib.drawWidgetSlots(ui, node, {
                    {
                        name = "value",
                        draw = function(imgui)
                            imgui.TextDisabled(node.text or "")
                            return false
                        end,
                    },
                })
            end,
        },
        banList = {
            binds = {},
            slots = { "value" },
            validate = function(node, _)
                if type(node.scopeKey) ~= "string" or node.scopeKey == "" then
                    node.scopeKey = nil
                end
            end,
            draw = function(ui, node, _, _, uiState)
                if not node.scopeKey then
                    return false
                end

                local currentBans = internal.GetBanConfig(node.scopeKey, uiState)
                local listNode = uiData.GetBanListNode(node.scopeKey)
                local runtimeGeometry, visibleCount = uiData.GetBanListGeometry(node.scopeKey, currentBans, uiState)
                local changed = false

                if listNode then
                    ui.PushID("banList_" .. node.scopeKey)
                    changed = lib.drawUiNode(
                        ui,
                        listNode,
                        uiState,
                        nil,
                        internal.definition.customTypes,
                        runtimeGeometry)
                    ui.PopID()
                end

                if (visibleCount or 0) == 0 then
                    ui.TextDisabled("No boons match the current filter.")
                end

                return changed
            end,
        },
        bridalGlowSummary = {
            binds = {},
            slots = { "value" },
            validate = function(_, _) end,
            draw = function(ui, node, _, _, uiState)
                local _ = node
                local selectedBoonKey = uiState.view.BridalGlowTargetBoon or ""
                local eligibleRoots = GetBridalGlowEligibleRoots(uiState)
                local currentTarget = GetCurrentBridalGlowTarget(eligibleRoots, selectedBoonKey)

                return lib.drawWidgetSlots(ui, node, {
                    {
                        name = "value",
                        draw = function(imgui)
                            if currentTarget then
                                imgui.Text("Current Target:")
                                imgui.SameLine()
                                imgui.TextDisabled(currentTarget.BridalGlowLabel)
                            else
                                imgui.TextDisabled("Current Target: Random")
                            end
                            return false
                        end,
                    },
                })
            end,
        },
        bridalGlowPicker = {
            binds = {},
            slots = { "value" },
            validate = function(_, _) end,
            draw = function(ui, node, _, _, uiState)
                local _ = node
                local paneHeight = 220
                local godPaneWidth = 200
                local selectedBoonKey = uiState.view.BridalGlowTargetBoon or ""
                local eligibleRoots = GetBridalGlowEligibleRoots(uiState)
                if #eligibleRoots == 0 then
                    return lib.drawWidgetSlots(ui, node, {
                        {
                            name = "value",
                            draw = function(imgui)
                                imgui.TextDisabled("No eligible Olympian gods are currently available.")
                                return false
                            end,
                        },
                    })
                end

                local selectedRoot = EnsureBridalGlowRootSelection(eligibleRoots, selectedBoonKey)
                local selectedRootKey = selectedRoot and selectedRoot.rootKey or nil
                local eligibleBoons = GetBridalGlowEligibleBoons(selectedRoot)

                return lib.drawWidgetSlots(ui, node, {
                    {
                        name = "value",
                        draw = function(imgui)
                            imgui.BeginChild("##BridalGlowGodList", godPaneWidth, paneHeight, true)
                            imgui.TextDisabled("Eligible Gods")
                            imgui.Separator()
                            for _, root in ipairs(eligibleRoots) do
                                if imgui.Selectable(root.displayLabel, root.rootKey == selectedRootKey) then
                                    uiData.bridalGlowSelection.rootKey = root.rootKey
                                    selectedRoot = root
                                    selectedRootKey = root.rootKey
                                    eligibleBoons = GetBridalGlowEligibleBoons(selectedRoot)
                                end
                            end
                            imgui.EndChild()

                            imgui.SameLine()
                            imgui.BeginChild("##BridalGlowBoonList", 0, paneHeight, true)
                            imgui.TextDisabled("Eligible Boons")
                            imgui.Separator()
                            if imgui.Selectable("Random", selectedBoonKey == "") then
                                selectedBoonKey = ""
                                internal.SetBridalGlowTargetBoonKey(nil, uiState)
                            end
                            for _, boon in ipairs(eligibleBoons) do
                                if imgui.Selectable(boon.BridalGlowLabel, boon.Key == selectedBoonKey) then
                                    selectedBoonKey = boon.Key
                                    internal.SetBridalGlowTargetBoonKey(boon.Key, uiState)
                                end
                            end
                            imgui.EndChild()
                            return false
                        end,
                    },
                })
            end,
        },
        rarityBadge = {
            binds = { value = { storageType = "int" } },
            slots = { "decrement", "value", "increment" },
            defaultGeometry = {
                slots = {
                    { name = "decrement", start = 0 },
                    { name = "value", start = 10, width = 100, align = "center" },
                    { name = "increment", start = 100 },
                },
            },
            validate = function(_, _) end,
            draw = function(ui, node, bound)
                local uiMod = internal.ui
                local current = bound.value:get() or 0
                if current < 0 then current = 0 end
                if current > 3 then current = 3 end
                local label = uiMod.RARITY_LABELS[current] or "Auto"
                local color = uiMod.RARITY_COLORS[current] or uiMod.RARITY_COLORS[0]
                local nextValue = current
                lib.drawWidgetSlots(ui, node, {
                    {
                        name = "decrement",
                        draw = function(imgui)
                            if imgui.Button("-") and current > 0 then
                                nextValue = current - 1
                            end
                            return false
                        end,
                    },
                    {
                        name = "value",
                        sameLine = true,
                        draw = function(imgui, slot)
                            lib.alignSlotContent(imgui, slot,
                                type(imgui.CalcTextSize) == "function" and imgui.CalcTextSize(label) or #(tostring(label)))
                            uiMod.DrawColoredText(imgui, color, label)
                            return false
                        end,
                    },
                    {
                        name = "increment",
                        sameLine = true,
                        draw = function(imgui)
                            if imgui.Button("+") and current < 3 then
                                nextValue = current + 1
                            end
                            return false
                        end,
                    },
                })
                if nextValue ~= current then bound.value:set(nextValue) end
            end,
        },
        forceStatus = {
            binds = { value = { storageType = "int" } },
            slots = { "value" },
            validate = function(node, _)
                if type(node.scopeKey) ~= "string" or node.scopeKey == "" then
                    node.scopeKey = nil
                end
                if node.rarityScopeKey ~= nil and (type(node.rarityScopeKey) ~= "string" or node.rarityScopeKey == "") then
                    node.rarityScopeKey = nil
                end
            end,
            draw = function(ui, node, bound, _, uiState)
                if not node.scopeKey then
                    return false
                end
                local currentMask = bound.value:get() or 0
                local forcedBoon, isNone, isCustom = uiData.GetForcedBoonSelection(node.scopeKey, currentMask)
                local rarityScopeKey = node.rarityScopeKey
                local rarityAlias = rarityScopeKey
                    and forcedBoon
                    and uiData.IsRarityEligibleBoon(forcedBoon)
                    and internal.GetRarityAlias(rarityScopeKey, forcedBoon.Key)
                    or nil
                local text = forcedBoon and uiData.GetForcedBoonStatusText(forcedBoon) or ""

                return lib.drawWidgetSlots(ui, node, {
                    {
                        name = "value",
                        draw = function(imgui, slot)
                            if isNone or isCustom or not forcedBoon then
                                imgui.Text("")
                                return false
                            end

                            if rarityAlias then
                                return uiData.DrawRarityBadgeNode(
                                    imgui,
                                    rarityAlias,
                                    uiState,
                                    node.scopeKey .. "::" .. forcedBoon.Key)
                            end

                            lib.alignSlotContent(imgui, slot,
                                type(imgui.CalcTextSize) == "function" and imgui.CalcTextSize(text) or #(tostring(text)))
                            imgui.Text(text)
                            return false
                        end,
                    },
                })
            end,
        },
        paddingOptions = {
            binds = {},
            slots = { "value" },
            validate = function(_, _) end,
            draw = function(ui, node, _, _, uiState)
                if uiState.view.EnablePadding ~= true then
                    return false
                end
                return lib.drawWidgetSlots(ui, node, {
                    {
                        name = "value",
                        draw = function(imgui)
                            local changed = false
                            imgui.Indent()
                            local beforePrioritize = uiState.view.Padding_PrioritizeCoreForFirstN
                            uiData.DrawStepInput(imgui, uiState,
                                "Prioritize Core Boons for First N",
                                "Padding_PrioritizeCoreForFirstN", 0, 15, 1)
                            if uiState.view.Padding_PrioritizeCoreForFirstN ~= beforePrioritize then
                                changed = true
                            end
                            imgui.TextDisabled(
                                "(0 = disabled, N = prefer core boons in padding for the first N picks from each god.)")
                            local futureVal, futureChanged = imgui.Checkbox(
                                "Avoid 'Future Allowed' Items",
                                uiState.view.Padding_AvoidFutureAllowed ~= false)
                            if futureChanged then
                                uiState.set("Padding_AvoidFutureAllowed", futureVal)
                                changed = true
                            end
                            local duoVal, duoChanged = imgui.Checkbox(
                                "Allow Banned Duos/Legendaries",
                                uiState.view.Padding_AllowDuos == true)
                            if duoChanged then
                                uiState.set("Padding_AllowDuos", duoVal)
                                changed = true
                            end
                            imgui.Unindent()
                            return changed
                        end,
                    },
                })
            end,
        },
        dangerButton = {
            binds = {},
            slots = { "control" },
            validate = function(node, _)
                if type(node.actionId) ~= "string" or node.actionId == "" then
                    node.actionId = nil
                end
                if type(node.buttonLabel) ~= "string" or node.buttonLabel == "" then
                    node.buttonLabel = "Action"
                end
                if type(node.confirmLabel) ~= "string" or node.confirmLabel == "" then
                    node.confirmLabel = "Confirm"
                end
                if type(node.onConfirm) ~= "function" then
                    node.onConfirm = nil
                end
            end,
            draw = function(ui, node, _, _, uiState)
                if not node.actionId then
                    return false
                end
                uiData.ExpirePendingDanger()
                return lib.drawWidgetSlots(ui, node, {
                    {
                        name = "control",
                        draw = function(imgui)
                            local actionId = node.actionId
                            if uiData.pendingDanger and uiData.pendingDanger.action == actionId then
                                if imgui.Button(node.confirmLabel .. "##" .. actionId) then
                                    uiData.pendingDanger = nil
                                    if node.onConfirm then node.onConfirm(uiState) end
                                    return true
                                end
                                imgui.SameLine()
                                if imgui.Button("Cancel##" .. actionId) then
                                    uiData.pendingDanger = nil
                                    return true
                                end
                                imgui.SameLine()
                                local remaining = math.max(0, uiData.pendingDanger.expiresAt - os.clock())
                                imgui.TextDisabled(string.format("Confirmation expires in %.1fs", remaining))
                                return false
                            end
                            if imgui.Button(node.buttonLabel .. "##" .. actionId) then
                                uiData.ArmDangerAction(actionId)
                            end
                            return false
                        end,
                    },
                })
            end,
        },
        npcRegionFilter = {
            binds = {},
            slots = { "value" },
            validate = function(_, _) end,
            draw = function(ui, node, _, _, uiState)
                local _ = node
                local currentRegion = uiState.view[uiData.NPC_VIEW_REGION_ALIAS] or 4
                return lib.drawWidgetSlots(ui, node, {
                    {
                        name = "value",
                        draw = function(imgui)
                            local changed = false
                            imgui.Text("Filter NPC Sources:")
                            for index, option in ipairs(uiData.NPC_REGION_OPTIONS) do
                                if imgui.RadioButton(option.label, currentRegion == option.value) then
                                    uiState.set(uiData.NPC_VIEW_REGION_ALIAS, option.value)
                                    currentRegion = option.value
                                    changed = true
                                end
                                if index < #uiData.NPC_REGION_OPTIONS then
                                    imgui.SameLine()
                                end
                            end
                            return changed
                        end,
                    },
                })
            end,
        },
    }
}
