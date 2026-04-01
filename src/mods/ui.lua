local internal = RunDirectorBoonBans_Internal
local godMeta = internal.godMeta
local godInfo = internal.godInfo
local lib = rom.mods["adamant-ModpackLib"]

local ImGuiCol = rom.ImGuiCol
local DEFAULT_GOD_COLOR = { 1, 1, 1, 1 }
local DEFAULT_THEME_COLORS = {
    info = { 1, 1, 1, 1 },
    success = { 0.2, 1.0, 0.2, 1.0 },
    warning = { 1.0, 0.8, 0.0, 1.0 },
    error = { 1.0, 0.3, 0.3, 1.0 },
}
local BADGE_COLORS = {
    duo = { 0.82, 1.0, 0.38, 1.0 },
    legendary = { 1.0, 0.56, 0.0, 1.0 },
    infusion = { 1.0, 0.29, 1.0, 1.0 },
}
local RARITY_COLORS = {
    [0] = { 0.5, 0.5, 0.5, 1.0 },
    [1] = { 1.0, 1.0, 1.0, 1.0 },
    [2] = { 0.0, 0.54, 1.0, 1.0 },
    [3] = { 0.62, 0.07, 1.0, 1.0 },
}
local NPC_REGION_OPTIONS = {
    { label = "Neither",    value = 1 },
    { label = "Underworld", value = 2 },
    { label = "Surface",    value = 3 },
    { label = "Both",       value = 4 },
}
local OLYMPIAN_GROUPS = { "Core" }
local OTHER_GROUPS = { "Bonus", "Hammers" }
local NPC_GROUPS = { "UW NPC", "SF NPC", "Keepsakes" }

local openGodName = nil
local activeBoonTab = ""
local sortedGodKeysByGroup = nil

local function GetThemeColors(theme)
    return (theme and theme.colors) or DEFAULT_THEME_COLORS
end

local function DrawColoredText(ui, color, text)
    ui.TextColored(color[1], color[2], color[3], color[4], text)
end

local function DrawStepInput(ui, specialState, label, configKey, minValue, maxValue, step)
    step = step or 1
    local value = specialState.view[configKey] or minValue
    value = math.max(minValue, math.min(maxValue, value))

    ui.PushID(configKey)
    if ui.Button("-") and value > minValue then
        specialState.set(configKey, value - step)
    end
    ui.SameLine()
    ui.Text(label .. ": " .. tostring(value))
    ui.SameLine()
    if ui.Button("+") and value < maxValue then
        specialState.set(configKey, value + step)
    end
    ui.PopID()
end

local function DrawBadge(ui, text, color, tooltip)
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

local rarityStates = {
    [0] = { txt = " - ", desc = "Default (Game Logic)" },
    [1] = { txt = " C ", desc = "Force Common" },
    [2] = { txt = " R ", desc = "Force Rare" },
    [3] = { txt = " E ", desc = "Force Epic" },
}

local function DrawRarityButton(ui, currentValue)
    local state = rarityStates[currentValue] or rarityStates[0]
    local color = RARITY_COLORS[currentValue] or RARITY_COLORS[0]
    ui.PushStyleColor(ImGuiCol.Button, color[1], color[2], color[3], 0.3)
    ui.PushStyleColor(ImGuiCol.ButtonHovered, color[1], color[2], color[3], 0.6)
    ui.PushStyleColor(ImGuiCol.ButtonActive, color[1], color[2], color[3], 0.9)
    ui.PushStyleColor(ImGuiCol.Text, 1, 1, 1, 1)
    local clicked = ui.Button(state.txt)
    ui.PopStyleColor(4)
    if ui.IsItemHovered() then
        ui.SetTooltip(state.desc)
    end
    if clicked then
        return (currentValue + 1) % 4
    end
end

local function IsRegionMatch(group, regionValue)
    if regionValue == 4 then return true end
    if group == "UW NPC" then
        return regionValue == 2
    end
    if group == "SF NPC" then
        return regionValue == 3
    end
    return true
end

local function IsGodPoolFilteringActive()
    local godPool = rom.mods["adamant-RunDirectorGodPool"]
    if not godPool or not godPool.store or not godPool.definition or type(godPool.isGodEnabledInPool) ~= "function" then
        return false, nil
    end
    if not lib.isEnabled(godPool.store, godPool.definition.modpack) then
        return false, nil
    end
    return true, godPool
end

local function IsGodVisibleInGodPool(godKey, godPool)
    local root = internal.GetRootKey and internal.GetRootKey(godKey) or godKey
    return godPool.isGodEnabledInPool(root)
end

local function GetSortedGodKeysByGroup()
    if sortedGodKeysByGroup then
        return sortedGodKeysByGroup
    end

    for godKey, meta in pairs(godMeta) do
        local group = meta.uiGroup or "Other"
        if not sortedGodKeysByGroup then
            sortedGodKeysByGroup = {}
        end
        sortedGodKeysByGroup[group] = sortedGodKeysByGroup[group] or {}
        table.insert(sortedGodKeysByGroup[group], godKey)
    end

    for _, list in pairs(sortedGodKeysByGroup) do
        table.sort(list, function(a, b)
            return (godMeta[a].sortIndex or 999) < (godMeta[b].sortIndex or 999)
        end)
    end

    return sortedGodKeysByGroup
end

local function DrawGodAccordion(ui, specialState, godName)
    local data = godInfo[godName]
    local meta = godMeta[godName]
    if not data or not meta then return false end

    local color = data.color or DEFAULT_GOD_COLOR
    local display = meta.displayTextKey or godName

    ui.PushStyleColor(ImGuiCol.Header, color[1], color[2], color[3], 0.2)
    ui.PushStyleColor(ImGuiCol.HeaderHovered, color[1], color[2], color[3], 0.5)
    ui.PushStyleColor(ImGuiCol.HeaderActive, color[1], color[2], color[3], 0.7)
    local open = ui.CollapsingHeader(display)
    ui.PopStyleColor(3)

    ui.SameLine()
    ui.Text(data.banLabel or "")

    if open then
        ui.Indent()
        local currentBans = internal.GetBanConfig(godName, specialState)
        local dirty = false

        ui.PushID(godName)
        if ui.Button("Ban All") then
            if internal.BanAllGodBans(godName, specialState) then
                currentBans = internal.GetBanConfig(godName, specialState)
                dirty = true
            end
        end
        ui.SameLine()
        if ui.Button("Reset") then
            if internal.ResetGodBans(godName, specialState) then
                currentBans = internal.GetBanConfig(godName, specialState)
                dirty = true
            end
        end
        ui.PopID()

        ui.Separator()

        for _, boon in ipairs(data.boons or {}) do
            local isBanned = bit32.band(currentBans, boon.Mask) ~= 0
            ui.PushID(boon.Name or boon.Key)
            local checked, changed = ui.Checkbox("##Ban", isBanned)
            if changed then
                if checked then
                    currentBans = bit32.bor(currentBans, boon.Mask)
                else
                    currentBans = bit32.band(currentBans, bit32.bnot(boon.Mask))
                end
                dirty = true
                isBanned = checked
            end
            ui.SameLine()

            local drawnVisual = false
            if boon.Rarity.isDuo then
                DrawBadge(ui, " D ", BADGE_COLORS.duo, "Duo Boon")
                drawnVisual = true
            elseif boon.Rarity.isLegendary then
                DrawBadge(ui, " L ", BADGE_COLORS.legendary, "Legendary Boon")
                drawnVisual = true
            elseif boon.Rarity.isElemental then
                DrawBadge(ui, " I ", BADGE_COLORS.infusion, "Elemental Infusion")
                drawnVisual = true
            elseif meta.rarityVar and not isBanned then
                local rarityValue = internal.GetRarityValue(godName, boon.Bit, specialState)
                local newRarity = DrawRarityButton(ui, rarityValue)
                if newRarity ~= nil then
                    if internal.SetRarityValue(godName, boon.Bit, newRarity, specialState) then
                        dirty = true
                    end
                end
                drawnVisual = true
            end

            if drawnVisual then
                ui.SameLine()
            end
            ui.Text(boon.Name or boon.Key)
            ui.PopID()
        end

        if dirty then
            internal.SetBanConfig(godName, currentBans, specialState)
            internal.RecalculateBannedCounts(specialState)
        end

        ui.Unindent()
    end

    return open
end

local function DrawBanList(ui, specialState, targetGroups, headingColor)
    local groups = GetSortedGodKeysByGroup()
    local godPoolFiltering, godPool = IsGodPoolFilteringActive()
    local regionValue = specialState.view.ViewRegion or 4
    local equippedWeapon = GetEquippedWeapon and GetEquippedWeapon() or ""

    for _, group in ipairs(targetGroups) do
        local list = groups[group]
        if list and #list > 0 and IsRegionMatch(group, regionValue) then
            local drewEntry = false
            for _, godName in ipairs(list) do
                local shouldDraw = true
                if group == "Hammers" then
                    local root = internal.GetRootKey and internal.GetRootKey(godName) or godName
                    shouldDraw = equippedWeapon:find(root, 1, true) ~= nil
                elseif group == "Core" and godPoolFiltering then
                    shouldDraw = IsGodVisibleInGodPool(godName, godPool)
                end

                local canRenderAccordion = shouldDraw and (not openGodName or openGodName == godName)
                if canRenderAccordion then
                    if not drewEntry and #targetGroups > 1 then
                        DrawColoredText(ui, headingColor, group)
                    end
                    drewEntry = true
                    if not openGodName then
                        if DrawGodAccordion(ui, specialState, godName) then
                            openGodName = godName
                        end
                    elseif openGodName == godName then
                        if not DrawGodAccordion(ui, specialState, godName) then
                            openGodName = nil
                        end
                    end
                end
            end
            if drewEntry and not openGodName then
                ui.Separator()
            end
        end
    end
end

local function HandleTabSwitch(tabName)
    if activeBoonTab ~= tabName then
        activeBoonTab = tabName
        openGodName = nil
    end
end

local function DrawNpcRegionFilter(ui, specialState)
    ui.Text("Show NPC Boons:")
    local currentRegion = specialState.view.ViewRegion or 4
    for index, option in ipairs(NPC_REGION_OPTIONS) do
        if ui.RadioButton(option.label, currentRegion == option.value) then
            specialState.set("ViewRegion", option.value)
            currentRegion = option.value
        end
        if index < #NPC_REGION_OPTIONS then
            ui.SameLine()
        end
    end
end

local function DrawSettingsTab(ui, specialState)
    local view = specialState.view
    local padVal, padChanged = ui.Checkbox("Enable Padding", view.EnablePadding == true)
    if padChanged then specialState.set("EnablePadding", padVal) end
    ui.TextDisabled("Fills up menus to ensure enough options are available.")

    if view.EnablePadding == true then
        ui.Indent()
        local priorityVal, priorityChanged = ui.Checkbox("Prioritize Core Boons", view.Padding_UsePriority ~= false)
        if priorityChanged then specialState.set("Padding_UsePriority", priorityVal) end

        local futureVal, futureChanged = ui.Checkbox("Avoid 'Future Allowed' Items",
            view.Padding_AvoidFutureAllowed ~= false)
        if futureChanged then specialState.set("Padding_AvoidFutureAllowed", futureVal) end

        local duoVal, duoChanged = ui.Checkbox("Allow Banned Duos/Legendaries", view.Padding_AllowDuos == true)
        if duoChanged then specialState.set("Padding_AllowDuos", duoVal) end
        ui.Unindent()
    end

    ui.Separator()
    DrawStepInput(ui, specialState, "Improve N Boon Rarity to Epic", "ImproveFirstNBoonRarity", 0, 15, 1)
    ui.TextDisabled("(Improve the rarity of offered boons unless specifically forced by config.)")

    ui.Separator()
    if ui.Button("RESET ALL BANS (Global)") then
        if internal.ResetAllBans(specialState) then
            internal.RecalculateBannedCounts(specialState)
        end
    end
    if ui.Button("RESET ALL RARITY (Global)") then
        internal.ResetAllRarity(specialState)
    end
end

local function DrawMainContent(ui, specialState, headingColor)
    if ui.BeginTabBar("BoonSubTabs") then
        if ui.BeginTabItem("Olympians") then
            HandleTabSwitch("Olympians")
            DrawBanList(ui, specialState, OLYMPIAN_GROUPS, headingColor)
            ui.EndTabItem()
        end
        if ui.BeginTabItem("Other Gods & Hammers") then
            HandleTabSwitch("Hammers")
            DrawBanList(ui, specialState, OTHER_GROUPS, headingColor)
            ui.EndTabItem()
        end
        if ui.BeginTabItem("NPCs") then
            HandleTabSwitch("NPCs")
            if not openGodName then
                DrawNpcRegionFilter(ui, specialState)
                ui.Separator()
            end
            DrawBanList(ui, specialState, NPC_GROUPS, headingColor)
            ui.EndTabItem()
        end
        if ui.BeginTabItem("Settings") then
            HandleTabSwitch("Settings")
            DrawSettingsTab(ui, specialState)
            ui.EndTabItem()
        end
        ui.EndTabBar()
    end
end

function internal.DrawTab(ui, specialState, theme)
    local colors = GetThemeColors(theme)
    DrawMainContent(ui, specialState, colors.info)
end

function internal.DrawQuickContent(ui, specialState, theme)
    local colors = GetThemeColors(theme)
    local enabledCount = 0
    for _, info in pairs(godInfo) do
        if type(info) == "table" and info.banned and info.total then
            enabledCount = enabledCount + info.banned
        end
    end
    DrawColoredText(ui, colors.info, "Boon Bans")
    ui.Text(string.format("%d total bans configured", enabledCount))
    local padVal, padChanged = ui.Checkbox("Padding Enabled##QuickBoonBans", specialState.view.EnablePadding == true)
    if padChanged then
        specialState.set("EnablePadding", padVal)
    end
end
