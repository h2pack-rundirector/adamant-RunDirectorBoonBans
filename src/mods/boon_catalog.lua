local internal = RunDirectorBoonBans_Internal
local godMeta = internal.godMeta

internal.baseBoonCatalog = nil
internal.packedBanBits = nil
internal.packedRarityBits = nil
internal.packedStorageBits = nil

local bit32 = require("bit32")
local lshift = bit32.lshift

local function BuildBoonEntry(godKey, boonKey, index, overrideDisplayName)
    local traitData = TraitData[boonKey]
    local rarity = {
        isDuo = false,
        isLegendary = false,
        isElemental = false,
        blockStacking = false,
    }
    if traitData then
        rarity.isDuo = traitData.IsDuoBoon or false
        rarity.isLegendary = (traitData.RarityLevels and traitData.RarityLevels.Legendary ~= nil) or false
        rarity.isElemental = traitData.IsElementalTrait or false
        rarity.blockStacking = traitData.BlockStacking == true
    end

    local displayName = overrideDisplayName or (traitData and game.GetDisplayName({ Text = boonKey })) or boonKey
    local boon = {
        Key = boonKey,
        God = godKey,
        Bit = index,
        Mask = lshift(1, index),
        Name = displayName,
        NameLower = string.lower(displayName),
        Rarity = rarity,
        IsBridalGlowEligible = false,
    }

    if rarity.isDuo then
        boon.IsSpecial = true
        boon.IsRarityEligible = false
        boon.SpecialDisplayLabel = "[D] " .. displayName
        boon.SpecialTooltip = "Duo Boon"
        boon.SpecialBadgeText = " D "
        boon.SpecialBadgeColor = { 0.82, 1.0, 0.38, 1.0 }
    elseif rarity.isLegendary then
        boon.IsSpecial = true
        boon.IsRarityEligible = false
        boon.SpecialDisplayLabel = "[L] " .. displayName
        boon.SpecialTooltip = "Legendary Boon"
        boon.SpecialBadgeText = " L "
        boon.SpecialBadgeColor = { 1.0, 0.56, 0.0, 1.0 }
    elseif rarity.isElemental then
        boon.IsSpecial = true
        boon.IsRarityEligible = false
        boon.SpecialDisplayLabel = "[I] " .. displayName
        boon.SpecialTooltip = "Elemental Infusion"
        boon.SpecialBadgeText = " I "
        boon.SpecialBadgeColor = { 1.0, 0.29, 1.0, 1.0 }
    else
        boon.IsSpecial = false
        boon.IsRarityEligible = true
        boon.SpecialDisplayLabel = displayName
    end

    boon.IsBridalGlowEligible = boon.IsRarityEligible == true and rarity.blockStacking ~= true
    return boon
end

local function BuildRootEntry()
    return {
        boons = {},
        boonByKey = {},
    }
end

local function AddEntryBoon(entry, boon)
    entry.boons[#entry.boons + 1] = boon
    entry.boonByKey[boon.Key] = boon
end

local function AddLootSetBoons(entry, godKey, meta, src)
    local lootData = LootSetData[meta.key]
    if not lootData or not lootData[src.key] then
        return
    end

    local upgradeData = lootData[src.key]
    local index = 0
    if upgradeData.WeaponUpgrades then
        for _, boonKey in ipairs(upgradeData.WeaponUpgrades) do
            AddEntryBoon(entry, BuildBoonEntry(godKey, boonKey, index))
            index = index + 1
        end
    end
    if upgradeData.Traits then
        for _, boonKey in ipairs(upgradeData.Traits) do
            AddEntryBoon(entry, BuildBoonEntry(godKey, boonKey, index))
            index = index + 1
        end
    end
    if src.subKey and upgradeData[src.subKey] then
        for _, boonKey in ipairs(upgradeData[src.subKey]) do
            AddEntryBoon(entry, BuildBoonEntry(godKey, boonKey, index))
            index = index + 1
        end
    end
end

local function AddUnitSetBoons(entry, godKey, src)
    if not UnitSetData[src.unitKey] or not UnitSetData[src.unitKey][src.configKey] then
        return
    end
    local traitList = UnitSetData[src.unitKey][src.configKey].Traits
    if not traitList then
        return
    end
    for index, boonKey in ipairs(traitList) do
        AddEntryBoon(entry, BuildBoonEntry(godKey, boonKey, index - 1))
    end
end

local function AddSpellBoons(entry, godKey)
    local spellNames = {}
    for spellName in pairs(SpellData) do
        spellNames[#spellNames + 1] = spellName
    end
    table.sort(spellNames)

    for index, spellName in ipairs(spellNames) do
        local spellData = SpellData[spellName]
        local displayName = spellData and spellData.TraitName and game.GetDisplayName({ Text = spellData.TraitName }) or spellName
        AddEntryBoon(entry, BuildBoonEntry(godKey, spellName, index - 1, displayName))
    end
end

local function AddWeaponUpgradeBoons(entry, godKey, meta)
    local traits = LootSetData.Loot and LootSetData.Loot.WeaponUpgrade and LootSetData.Loot.WeaponUpgrade.Traits
    if not traits then
        return
    end

    local prefixes = meta.prefixes or { godKey }
    local index = 0
    for _, trait in ipairs(traits) do
        local matches = false
        for _, prefix in ipairs(prefixes) do
            if string.find(trait, prefix, 1, true) == 1 then
                matches = true
                break
            end
        end
        if matches then
            AddEntryBoon(entry, BuildBoonEntry(godKey, trait, index))
            index = index + 1
        end
    end
end

local function AddMetaUpgradeBoons(entry, godKey, src)
    local dataSource = _G[src.dataSource]
    if not dataSource then
        return
    end

    local sortedKeys = {}
    local orderMap = {}
    if MetaUpgradeDefaultCardLayout then
        for _, row in ipairs(MetaUpgradeDefaultCardLayout) do
            for _, cardName in ipairs(row) do
                if dataSource[cardName] then
                    sortedKeys[#sortedKeys + 1] = cardName
                    orderMap[cardName] = true
                end
            end
        end
    end

    local remaining = {}
    for cardName in pairs(dataSource) do
        if not orderMap[cardName] then
            remaining[#remaining + 1] = cardName
        end
    end
    table.sort(remaining)
    for _, cardName in ipairs(remaining) do
        sortedKeys[#sortedKeys + 1] = cardName
    end

    local index = 0
    for _, upgradeName in ipairs(sortedKeys) do
        if not (src.exclude and src.exclude[upgradeName]) then
            local displayName = game.GetDisplayName({ Text = upgradeName })
            AddEntryBoon(entry, BuildBoonEntry(godKey, upgradeName, index, displayName))
            index = index + 1
        end
    end
end

local function BuildBaseBoonCatalog()
    local catalog = {}
    for godKey, meta in pairs(godMeta) do
        if not meta.duplicateOf and meta.lootSource then
            local entry = BuildRootEntry()
            local src = meta.lootSource

            if src.type == "LootSet" then
                AddLootSetBoons(entry, godKey, meta, src)
            elseif src.type == "UnitSet" then
                AddUnitSetBoons(entry, godKey, src)
            elseif src.type == "SpellData" then
                AddSpellBoons(entry, godKey)
            elseif src.type == "WeaponUpgrade" then
                AddWeaponUpgradeBoons(entry, godKey, meta)
            elseif src.type == "MetaUpgrade" then
                AddMetaUpgradeBoons(entry, godKey, src)
            end

            catalog[godKey] = entry
        end
    end
    return catalog
end

function internal.GetOrBuildBaseBoonCatalog()
    if not internal.baseBoonCatalog then
        internal.baseBoonCatalog = BuildBaseBoonCatalog()
    end
    return internal.baseBoonCatalog
end

function internal.MakeRarityAlias(rarityVar, boonKey)
    if type(rarityVar) ~= "string" or rarityVar == "" then
        return nil
    end
    if type(boonKey) ~= "string" or boonKey == "" then
        return nil
    end
    return rarityVar .. "__" .. boonKey
end

function internal.GetRarityAlias(scopeKey, boonKey)
    local meta = godMeta[scopeKey]
    local rarityVar = meta and meta.rarityVar or nil
    if not rarityVar or not internal.GetOrBuildPackedRarityBits()[rarityVar] then
        return nil
    end
    return internal.MakeRarityAlias(rarityVar, boonKey)
end

function internal.MakeBanAlias(packedVar, boonKey)
    if type(packedVar) ~= "string" or packedVar == "" then
        return nil
    end
    if type(boonKey) ~= "string" or boonKey == "" then
        return nil
    end
    return packedVar .. "__" .. boonKey
end

function internal.GetBanRootAlias(scopeKey)
    local meta = godMeta[scopeKey]
    local packedConfig = meta and meta.packedConfig or nil
    return packedConfig and packedConfig.var or nil
end

function internal.GetBanAlias(scopeKey, boonKey)
    local packedVar = internal.GetBanRootAlias(scopeKey)
    if not packedVar or not internal.GetOrBuildPackedBanBits()[packedVar] then
        return nil
    end
    return internal.MakeBanAlias(packedVar, boonKey)
end

local function GetCatalogSourceKey(metaKey, meta)
    if type(meta) ~= "table" then
        return metaKey
    end
    return meta.duplicateOf or metaKey
end

local function BuildPackedBanBits()
    local bitsByPackedVar = {}
    local catalog = internal.GetOrBuildBaseBoonCatalog()

    for metaKey, meta in pairs(godMeta) do
        local packedVar = meta and meta.packedConfig and meta.packedConfig.var or nil
        local catalogKey = GetCatalogSourceKey(metaKey, meta)
        local entry = packedVar and catalog[catalogKey] or nil
        if packedVar and entry and entry.boons and #entry.boons > 0 then
            local bits = {}
            for _, boon in ipairs(entry.boons) do
                bits[#bits + 1] = {
                    alias = internal.MakeBanAlias(packedVar, boon.Key),
                    label = boon.Name,
                    offset = boon.Bit,
                    width = 1,
                    type = "bool",
                    default = false,
                }
            end
            if #bits > 0 then
                bitsByPackedVar[packedVar] = bits
            end
        end
    end

    return bitsByPackedVar
end

function internal.GetOrBuildPackedBanBits()
    if not internal.packedBanBits then
        internal.packedBanBits = BuildPackedBanBits()
    end
    return internal.packedBanBits
end

function internal.GetOrBuildPackedRarityBits()
    if internal.packedRarityBits then
        return internal.packedRarityBits
    end

    local bitsByPackedVar = {}
    local catalog = internal.GetOrBuildBaseBoonCatalog()
    for godKey, entry in pairs(catalog) do
        local meta = godMeta[godKey]
        if meta and meta.rarityVar then
            local bits = {}
            for _, boon in ipairs(entry.boons) do
                if boon.IsRarityEligible ~= false then
                    bits[#bits + 1] = {
                        alias = internal.MakeRarityAlias(meta.rarityVar, boon.Key),
                        label = boon.Name,
                        offset = boon.Bit * 2,
                        width = 2,
                        type = "int",
                        min = 0,
                        max = 3,
                    }
                end
            end
            if #bits > 0 then
                bitsByPackedVar[meta.rarityVar] = bits
            end
        end
    end

    internal.packedRarityBits = bitsByPackedVar
    return bitsByPackedVar
end

function internal.GetOrBuildPackedStorageBits()
    if not internal.packedStorageBits then
        local bitsByPackedVar = {}
        for packedVar, bits in pairs(internal.GetOrBuildPackedBanBits()) do
            bitsByPackedVar[packedVar] = bits
        end
        for packedVar, bits in pairs(internal.GetOrBuildPackedRarityBits()) do
            bitsByPackedVar[packedVar] = bits
        end
        internal.packedStorageBits = bitsByPackedVar
    end
    return internal.packedStorageBits
end

function internal.GetPackedStorageBits(rootAlias)
    return internal.GetOrBuildPackedStorageBits()[rootAlias]
end
