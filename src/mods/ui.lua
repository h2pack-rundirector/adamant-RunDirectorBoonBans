local internal = RunDirectorBoonBans_Internal
local godMeta = internal.godMeta
local godInfo = internal.godInfo

local ImGuiCol = rom.ImGuiCol

local activeColors = {
    title = { 1, 1, 1, 1 },
    info = { 0.6, 0.8, 1.0, 1.0 },
    success = { 0.2, 1.0, 0.2, 1.0 },
    warning = { 1.0, 0.8, 0.0, 1.0 },
    error = { 1.0, 0.3, 0.3, 1.0 },
    duo = { 0.82, 1.0, 0.38, 1.0 },
    legendary = { 1.0, 0.56, 0.0, 1.0 },
    infusion = { 1.0, 0.29, 1.0, 1.0 },
    rarityDefault = { 0.5, 0.5, 0.5, 1.0 },
    rarityCommon = { 1.0, 1.0, 1.0, 1.0 },
    rarityRare = { 0.0, 0.54, 1.0, 1.0 },
    rarityEpic = { 0.62, 0.07, 1.0, 1.0 },
}

local openGodName = nil
local activeBoonTab = ""

local function ApplyThemeColors(theme)
    if theme and theme.colors then
        activeColors.title = theme.colors.info or activeColors.title
        activeColors.info = theme.colors.info or activeColors.info
        activeColors.success = theme.colors.success or activeColors.success
        activeColors.warning = theme.colors.warning or activeColors.warning
        activeColors.error = theme.colors.error or activeColors.error
    end
end

local function DrawColoredText(ui, color, text)
    ui.TextColored(color[1], color[2], color[3], color[4], text)
end

local function DrawStepInput(ui, label, configKey, minValue, maxValue, step)
    step = step or 1
    local value = config[configKey] or minValue
    value = math.max(minValue, math.min(maxValue, value))

    ui.PushID(configKey)
    if ui.Button("-") and value > minValue then
        config[configKey] = value - step
    end
    ui.SameLine()
    ui.Text(label .. ": " .. tostring(config[configKey] or value))
    ui.SameLine()
    if ui.Button("+") and value < maxValue then
        config[configKey] = value + step
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
    [0] = { txt = " - ", col = activeColors.rarityDefault, desc = "Default (Game Logic)" },
    [1] = { txt = " C ", col = activeColors.rarityCommon, desc = "Force Common" },
    [2] = { txt = " R ", col = activeColors.rarityRare, desc = "Force Rare" },
    [3] = { txt = " E ", col = activeColors.rarityEpic, desc = "Force Epic" },
}

local function DrawRarityButton(ui, currentValue)
    rarityStates[0].col = activeColors.rarityDefault
    rarityStates[1].col = activeColors.rarityCommon
    rarityStates[2].col = activeColors.rarityRare
    rarityStates[3].col = activeColors.rarityEpic

    local state = rarityStates[currentValue] or rarityStates[0]
    ui.PushStyleColor(ImGuiCol.Button, state.col[1], state.col[2], state.col[3], 0.3)
    ui.PushStyleColor(ImGuiCol.ButtonHovered, state.col[1], state.col[2], state.col[3], 0.6)
    ui.PushStyleColor(ImGuiCol.ButtonActive, state.col[1], state.col[2], state.col[3], 0.9)
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

local function IsRegionMatch(group)
    if config.ViewRegion == 4 then return true end
    if group == "UW NPC" then
        return config.ViewRegion == 2
    end
    if group == "SF NPC" then
        return config.ViewRegion == 3
    end
    return true
end

local function BuildBanGroups(targetGroups)
    local buckets = {}
    local groupSet = {}
    for _, group in ipairs(targetGroups) do
        buckets[group] = {}
        groupSet[group] = true
    end

    for godKey, meta in pairs(godMeta) do
        local group = meta.uiGroup or "Other"
        if groupSet[group] and IsRegionMatch(group) then
            if group == "Hammers" then
                local weapon = GetEquippedWeapon and GetEquippedWeapon() or ""
                local root = internal.GetRootKey and internal.GetRootKey(godKey) or godKey
                if weapon:find(root, 1, true) then
                    table.insert(buckets[group], godKey)
                end
            else
                table.insert(buckets[group], godKey)
            end
        end
    end

    for _, list in pairs(buckets) do
        table.sort(list, function(a, b)
            return (godMeta[a].sortIndex or 999) < (godMeta[b].sortIndex or 999)
        end)
    end

    return buckets
end

local function DrawGodAccordion(ui, godName)
    local data = godInfo[godName]
    local meta = godMeta[godName]
    if not data or not meta then return false end

    local color = data.color or { 1, 1, 1, 1 }
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
        local currentBans = internal.GetBanConfig(godName)
        local dirty = false

        ui.PushID(godName)
        if ui.Button("Ban All") then
            internal.BanAllGodBans(godName)
            dirty = true
        end
        ui.SameLine()
        if ui.Button("Reset") then
            internal.ResetGodBans(godName)
            dirty = true
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
                DrawBadge(ui, " D ", activeColors.duo, "Duo Boon")
                drawnVisual = true
            elseif boon.Rarity.isLegendary then
                DrawBadge(ui, " L ", activeColors.legendary, "Legendary Boon")
                drawnVisual = true
            elseif boon.Rarity.isElemental then
                DrawBadge(ui, " I ", activeColors.infusion, "Elemental Infusion")
                drawnVisual = true
            elseif meta.rarityVar and not isBanned then
                local rarityValue = internal.GetRarityValue(godName, boon.Bit)
                local newRarity = DrawRarityButton(ui, rarityValue)
                if newRarity ~= nil then
                    internal.SetRarityValue(godName, boon.Bit, newRarity)
                    dirty = true
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
            internal.SetBanConfig(godName, currentBans)
            internal.RecalculateBannedCounts()
        end

        ui.Unindent()
    end

    return open
end

local function DrawBanList(ui, targetGroups)
    local buckets = BuildBanGroups(targetGroups)

    for _, group in ipairs(targetGroups) do
        local list = buckets[group]
        if list and #list > 0 then
            if #targetGroups > 1 then
                DrawColoredText(ui, activeColors.title, group)
            end
            for _, godName in ipairs(list) do
                if not openGodName then
                    if DrawGodAccordion(ui, godName) then
                        openGodName = godName
                    end
                elseif openGodName == godName then
                    if not DrawGodAccordion(ui, godName) then
                        openGodName = nil
                    end
                end
            end
            if not openGodName then
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

local function DrawNpcRegionFilter(ui)
    ui.Text("Show NPC Boons:")
    local options = {
        { label = "Neither", value = 1 },
        { label = "Underworld", value = 2 },
        { label = "Surface", value = 3 },
        { label = "Both", value = 4 },
    }
    for index, option in ipairs(options) do
        if ui.RadioButton(option.label, config.ViewRegion == option.value) then
            config.ViewRegion = option.value
        end
        if index < #options then
            ui.SameLine()
        end
    end
end

local function DrawSettingsTab(ui)
    local padVal, padChanged = ui.Checkbox("Enable Padding", config.EnablePadding)
    if padChanged then config.EnablePadding = padVal end
    ui.TextDisabled("Fills up menus to ensure enough options are available.")

    if config.EnablePadding then
        ui.Indent()
        local priorityVal, priorityChanged = ui.Checkbox("Prioritize Core Boons", config.Padding_UsePriority ~= false)
        if priorityChanged then config.Padding_UsePriority = priorityVal end

        local futureVal, futureChanged = ui.Checkbox("Avoid 'Future Allowed' Items", config.Padding_AvoidFutureAllowed ~= false)
        if futureChanged then config.Padding_AvoidFutureAllowed = futureVal end

        local duoVal, duoChanged = ui.Checkbox("Allow Banned Duos/Legendaries", config.Padding_AllowDuos == true)
        if duoChanged then config.Padding_AllowDuos = duoVal end
        ui.Unindent()
    end

    ui.Separator()
    DrawStepInput(ui, "Improve N Boon Rarity to Epic", "ImproveFirstNBoonRarity", 0, 15, 1)
    ui.TextDisabled("(Improve the rarity of offered boons unless specifically forced by config.)")

    ui.Separator()
    if ui.Button("RESET ALL BANS (Global)") then
        internal.ResetAllBans()
        internal.RecalculateBannedCounts()
    end
    if ui.Button("RESET ALL RARITY (Global)") then
        internal.ResetAllRarity()
    end
end

local function DrawMainContent(ui)
    if ui.BeginTabBar("BoonSubTabs") then
        if ui.BeginTabItem("Olympians") then
            HandleTabSwitch("Olympians")
            DrawBanList(ui, { "Core" })
            ui.EndTabItem()
        end
        if ui.BeginTabItem("Other Gods & Hammers") then
            HandleTabSwitch("Hammers")
            DrawBanList(ui, { "Bonus", "Hammers" })
            ui.EndTabItem()
        end
        if ui.BeginTabItem("NPCs") then
            HandleTabSwitch("NPCs")
            if not openGodName then
                DrawNpcRegionFilter(ui)
                ui.Separator()
            end
            DrawBanList(ui, { "UW NPC", "SF NPC", "Keepsakes" })
            ui.EndTabItem()
        end
        if ui.BeginTabItem("Settings") then
            HandleTabSwitch("Settings")
            DrawSettingsTab(ui)
            ui.EndTabItem()
        end
        ui.EndTabBar()
    end
end

function internal.DrawTab(ui, specialState, theme)
    ApplyThemeColors(theme)
    internal.withStateBackedConfig(specialState, function()
        DrawMainContent(ui)
    end)
end

function internal.DrawQuickContent(ui, specialState, theme)
    ApplyThemeColors(theme)
    internal.withStateBackedConfig(specialState, function()
        local enabledCount = 0
        for _, info in pairs(godInfo) do
            if type(info) == "table" and info.banned and info.total then
                enabledCount = enabledCount + info.banned
            end
        end
        DrawColoredText(ui, activeColors.title, "Boon Bans")
        ui.Text(string.format("%d total bans configured", enabledCount))
        local padVal, padChanged = ui.Checkbox("Padding Enabled##QuickBoonBans", config.EnablePadding)
        if padChanged then
            config.EnablePadding = padVal
        end
    end)
end
