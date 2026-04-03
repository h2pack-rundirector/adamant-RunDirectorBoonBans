---@meta _
---@diagnostic disable: lowercase-global

local internal = RunDirectorBoonBans_Internal
local godMeta = internal.godMeta

internal.godInfo = internal.godInfo or {}
local godInfo = internal.godInfo

local lshift = bit32.lshift
local t_insert = table.insert

local function GetRunState()
    return internal.GetRunState()
end

local function IsBanManagerActive()
    return lib.isEnabled(store, internal.definition.modpack)
end

local function Log(fmt, ...)
    lib.log(internal.definition.id, store.read("DebugMode") == true, fmt, ...)
end

local function GetRootKey(key)
    local meta = godMeta[key]
    if not meta then return key end
    if meta.duplicateOf then return GetRootKey(meta.duplicateOf) end
    return key
end

local function GetSourceColor(name)
    local meta = godMeta[name]
    local colorKey = meta and meta.colorKey
    local inGameColor = colorKey and game.Color[colorKey] or game.Color.Black
    return { inGameColor[1] / 255, inGameColor[2] / 255, inGameColor[3] / 255, inGameColor[4] / 255 }
end

local function PopulateGodInfo()
    for key in pairs(godInfo) do
        godInfo[key] = nil
    end
    godInfo.traitLookup = {}

    for key, _ in pairs(godMeta) do
        godInfo[key] = { color = GetSourceColor(key), boons = {} }
    end

    local function addBoonToRuntime(godKey, boonKey, index, overrideDisplayName)
        local traitData = TraitData[boonKey]
        local rarity = { isDuo = false, isLegendary = false, isElemental = false }
        if traitData then
            rarity.isDuo = traitData.IsDuoBoon or false
            rarity.isLegendary = (traitData.RarityLevels and traitData.RarityLevels.Legendary ~= nil) or false
            rarity.isElemental = traitData.IsElementalTrait or false
        end

        local bitMask = lshift(1, index)
        local displayName = overrideDisplayName or (traitData and game.GetDisplayName({ Text = boonKey })) or boonKey

        local boon = {
            Key = boonKey,
            God = godKey,
            Bit = index,
            Mask = bitMask,
            Name = displayName,
            Rarity = rarity
        }

        godInfo[godKey].boons = godInfo[godKey].boons or {}
        t_insert(godInfo[godKey].boons, boon)

        local entry = { god = godKey, bit = index, mask = bitMask }
        if not godInfo.traitLookup[boonKey] then
            godInfo.traitLookup[boonKey] = { entry }
        else
            t_insert(godInfo.traitLookup[boonKey], entry)
        end
    end

    for key, meta in pairs(godMeta) do
        if not meta.duplicateOf and meta.lootSource then
            local src = meta.lootSource

            if src.type == "LootSet" then
                local lootData = LootSetData[meta.key]
                if lootData and lootData[src.key] then
                    local upgradeData = lootData[src.key]
                    local index = 0
                    if upgradeData.WeaponUpgrades then
                        for _, boon in ipairs(upgradeData.WeaponUpgrades) do
                            addBoonToRuntime(key, boon, index)
                            index = index + 1
                        end
                    end
                    if upgradeData.Traits then
                        for _, boon in ipairs(upgradeData.Traits) do
                            addBoonToRuntime(key, boon, index)
                            index = index + 1
                        end
                    end
                    if upgradeData[src.subKey] then
                        for _, boon in ipairs(upgradeData[src.subKey]) do
                            addBoonToRuntime(key, boon, index)
                            index = index + 1
                        end
                    end
                end
            elseif src.type == "UnitSet" then
                if UnitSetData[src.unitKey] and UnitSetData[src.unitKey][src.configKey] then
                    local traitList = UnitSetData[src.unitKey][src.configKey].Traits
                    if traitList then
                        for i, boon in ipairs(traitList) do
                            addBoonToRuntime(key, boon, i - 1)
                        end
                    end
                end
            elseif src.type == "SpellData" then
                local spellNames = {}
                for spellName, _ in pairs(SpellData) do
                    t_insert(spellNames, spellName)
                end
                table.sort(spellNames)
                for i, spellName in ipairs(spellNames) do
                    local spellData = SpellData[spellName]
                    local name = game.GetDisplayName({ Text = spellData.TraitName })
                    addBoonToRuntime(key, spellName, i - 1, name)
                end
            elseif src.type == "WeaponUpgrade" then
                if LootSetData.Loot and LootSetData.Loot.WeaponUpgrade and LootSetData.Loot.WeaponUpgrade.Traits then
                    local daedalusTraits = LootSetData.Loot.WeaponUpgrade.Traits
                    local prefixes = meta.prefixes or { key }
                    local currentIndex = 0
                    for _, trait in ipairs(daedalusTraits) do
                        local match = false
                        for _, prefix in ipairs(prefixes) do
                            if string.find(trait, prefix, 1, true) == 1 then
                                match = true
                                break
                            end
                        end
                        if match then
                            addBoonToRuntime(key, trait, currentIndex)
                            currentIndex = currentIndex + 1
                        end
                    end
                end
            elseif src.type == "MetaUpgrade" then
                local dataSource = _G[src.dataSource]
                if dataSource then
                    local sortedKeys = {}
                    local orderMap = {}
                    if MetaUpgradeDefaultCardLayout then
                        for _, row in ipairs(MetaUpgradeDefaultCardLayout) do
                            for _, cardName in ipairs(row) do
                                if dataSource[cardName] then
                                    t_insert(sortedKeys, cardName)
                                    orderMap[cardName] = true
                                end
                            end
                        end
                    end

                    local remaining = {}
                    for cardName, _ in pairs(dataSource) do
                        if not orderMap[cardName] then
                            t_insert(remaining, cardName)
                        end
                    end
                    table.sort(remaining)
                    for _, cardName in ipairs(remaining) do
                        t_insert(sortedKeys, cardName)
                    end

                    local index = 0
                    for _, upgradeName in ipairs(sortedKeys) do
                        local isValid = true
                        if isValid and src.exclude and src.exclude[upgradeName] then
                            isValid = false
                        end
                        if isValid then
                            local displayName = game.GetDisplayName({ Text = upgradeName })
                            addBoonToRuntime(key, upgradeName, index, displayName)
                            index = index + 1
                        end
                    end
                end
            end
            internal.UpdateGodStats(key)
        end
    end

    for key, meta in pairs(godMeta) do
        if meta.duplicateOf then
            local parentKey = meta.duplicateOf
            local parentEntry = godInfo[parentKey]
            if parentEntry then
                for _, parentBoon in ipairs(parentEntry.boons) do
                    addBoonToRuntime(key, parentBoon.Key, parentBoon.Bit, parentBoon.Name)
                end
                internal.UpdateGodStats(key)
            end
        end
    end

    Log("[Micro] GodInfo Populated.")
end

function internal.GetOrRecalcBoonCounts()
    local state = GetRunState()
    local pickCounts = state.BoonPickCounts
    if pickCounts then
        return pickCounts
    end

    local counts = {}
    if CurrentRun and CurrentRun.Hero and CurrentRun.Hero.Traits then
        for _, trait in pairs(CurrentRun.Hero.Traits) do
            if trait.Name then
                local infoList = godInfo.traitLookup[trait.Name]
                if infoList and infoList[1] then
                    local rootKey = GetRootKey(infoList[1].god)
                    counts[rootKey] = (counts[rootKey] or 0) + 1
                end
            end
        end
    end
    state.BoonPickCounts = counts
    return counts
end

function internal.FindTraitInfo(traitName, filterGodKey, knownTier)
    local list = godInfo.traitLookup[traitName]
    if not list then return nil end

    local targetEntry = nil
    if filterGodKey then
        for _, entry in ipairs(list) do
            local entryRoot = GetRootKey(entry.god)
            if entryRoot == filterGodKey then
                targetEntry = entry
                break
            end
        end
    end
    if not targetEntry then
        targetEntry = list[1]
    end

    local targetTier = knownTier
    if not targetTier then
        local rootKey = GetRootKey(targetEntry.god)
        local currentPicks = (internal.GetOrRecalcBoonCounts()[rootKey] or 0)
        targetTier = currentPicks + 1
    end

    for i = 1, #list do
        local entry = list[i]
        local meta = godMeta[entry.god]
        local entryTier = meta.tier or 1
        if entryTier == targetTier then
            if not filterGodKey or GetRootKey(entry.god) == filterGodKey then
                return entry
            end
        end
    end
    return nil
end

function internal.GetGodFromLootsource(lootKey)
    for godKey, meta in pairs(godMeta) do
        if meta.lootSource and meta.lootSource.key == lootKey then
            if lootKey == "WeaponUpgrade" then
                local currentWeapon = GetEquippedWeapon()
                if string.find(currentWeapon, godKey, 1, true) then
                    return GetRootKey(godKey)
                end
            else
                return GetRootKey(godKey)
            end
        end
    end
    return nil
end

internal.GetRootKey = GetRootKey
internal.IsBanManagerActive = IsBanManagerActive

PopulateGodInfo()
