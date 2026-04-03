local meta = {}

local internal = RunDirectorBoonBans_Internal

local function Log(fmt, ...)
    lib.log(internal.definition.id, store.read("DebugMode") == true, fmt, ...)
end

-- =============================================================================
-- 1. CONFIGURATION CONSTANTS
-- =============================================================================

local GROUP_CORE       = "Core"
local GROUP_BONUS      = "Bonus"
local GROUP_HAMMERS    = "Hammers"
local GROUP_UW_NPC     = "UW NPC"
local GROUP_SF_NPC     = "SF NPC"
local GROUP_KEEPSAKES  = "Keepsakes"

local MAX_GOD_TIERS    = 5
local MAX_HAMMER_TIERS = 3
local MAX_HERMES_TIERS = 2

-- =============================================================================
-- 2. DYNAMIC BIT COUNTER
-- =============================================================================

local function GetBitCount(source, defaultPrefix)
    if not source then return 8 end
    local count = 0

    if source.type == "LootSet" then
        -- Step 1: Try to find the God's table first (e.g., LootSetData["Apollo"])
        -- The files show LootSetData.Apollo exists, and ApolloUpgrade is inside it.
        local container = LootSetData[defaultPrefix]
        local data

        if container and container[source.key] then
            data = container[source.key] -- Found: LootSetData.Apollo.ApolloUpgrade
        else
            -- Step 2: Fallback for loose tables (or if inside LootSetData.Loot)
            data = LootSetData[source.key] or (LootSetData.Loot and LootSetData.Loot[source.key])
        end

        if data then
            if data.WeaponUpgrades then count = count + #data.WeaponUpgrades end
            if data.Traits then count = count + #data.Traits end

            -- Handle SubKeys (like Chaos PermanentTraits/TemporaryTraits)
            if source.subKey and data[source.subKey] then
                count = count + #data[source.subKey]
            end
        end
    elseif source.type == "UnitSet" then
        -- Count NPC Traits (Arachne, Narcissus, etc.)
        local unit = UnitSetData[source.unitKey]
        if unit and unit[source.configKey] and unit[source.configKey].Traits then
            count = #unit[source.configKey].Traits
        end
    elseif source.type == "SpellData" then
        -- Count Selene Spells
        for _ in pairs(SpellData) do count = count + 1 end
    elseif source.type == "WeaponUpgrade" then
        -- Count Hammer Traits by Prefix match
        local data = LootSetData.Loot and LootSetData.Loot.WeaponUpgrade and LootSetData.Loot.WeaponUpgrade.Traits
        if data then
            local prefixes = source.prefixes or { defaultPrefix }
            for _, trait in ipairs(data) do
                for _, p in ipairs(prefixes) do
                    if string.find(trait, p, 1, true) == 1 then
                        count = count + 1
                        break
                    end
                end
            end
        end
    elseif source.type == "MetaUpgrade" then
        -- Count Cards/Shrine options (Circe)
        local data = _G[source.dataSource]
        if data then
            for k, _ in pairs(data) do
                local isValid = true
                if source.exclude and source.exclude[k] then isValid = false end
                if isValid then count = count + 1 end
            end
        end
    elseif source.type == "Keepsake" then
        if source.key == "HadesKeepsake" then
            local unit = UnitSetData["NPC_Hades"]
            if unit and unit["NPC_Hades_Field_01"] and unit["NPC_Hades_Field_01"].Traits then
                count = #unit["NPC_Hades_Field_01"].Traits
            end
        end
    end

    -- DEBUG: Keep this to verify the fix in the console!
    Log("BitCheck: %-12s | Type: %-13s | Count: %d",
        defaultPrefix or "??",
        source.type,
        count)

    -- Safety: Ensure we never return 0 bits, or the mask logic will break
    return count > 0 and count or 1
end

local function GetOrdinal(n)
    local s = tostring(n)
    if n % 100 == 11 or n % 100 == 12 or n % 100 == 13 then return s .. "th" end
    local last = n % 10
    if last == 1 then return s .. "st" end
    if last == 2 then return s .. "nd" end
    if last == 3 then return s .. "rd" end
    return s .. "th"
end
-- =============================================================================
-- 3. DATA DEFINITIONS
-- =============================================================================

-- [A] OLYMPIANS (Auto-generates 4 Tiers)
local baseOlympians = {
    { name = "Aphrodite",  color = "AphroditeDamage" },
    { name = "Apollo",     color = "ApolloDamageLight" },
    { name = "Ares",       color = "AresDamageLight" },
    { name = "Demeter",    color = "DemeterDamage" },
    { name = "Hephaestus", color = "HephaestusDamage" },
    { name = "Hera",       color = "HeraDamage" },
    { name = "Hestia",     color = "HestiaDamageLight" },
    { name = "Poseidon",   color = "PoseidonDamage" },
    { name = "Zeus",       color = "ZeusDamageLight" },
    { name = "Hermes",     color = "HermesVoice",      group = GROUP_BONUS, tiers = MAX_HERMES_TIERS }
}

-- [B] WEAPONS (Auto-generates 2 Tiers)
local baseWeapons = {
    { key = "Staff",  display = "Staff" },
    { key = "Dagger", display = "Blades" },
    { key = "Axe",    display = "Axe" },
    { key = "Torch",  display = "Torch" },
    { key = "Lob",    display = "Skull" },
    { key = "Suit",   display = "Coat" },
}

-- [C] SINGLES (NPCs & Simple Items)
local baseSingles = {
    -- Underworld
    { key = "Arachne",       color = "ArachneVoice",      group = GROUP_UW_NPC },
    { key = "Narcissus",     color = "NarcissusVoice",    group = GROUP_UW_NPC },
    { key = "Echo",          color = "EchoVoice",         group = GROUP_UW_NPC },
    { key = "Hades",         color = "HadesVoice",        group = GROUP_UW_NPC,    configKey = "NPC_Hades_Field_01" },
    -- Surface
    { key = "Medea",         color = "MedeaVoice",        group = GROUP_SF_NPC },
    { key = "Circe",         color = "CirceVoice",        group = GROUP_SF_NPC },
    { key = "Icarus",        color = "IcarusVoice",       group = GROUP_SF_NPC },
    { key = "Dionysus",      color = "DionysusDamage",    group = GROUP_SF_NPC },
    -- Bonus
    { key = "Selene",        color = "SeleneVoice",       group = GROUP_BONUS,     lootSourceType = "SpellData" },
    { key = "Artemis",       color = "ArtemisDamage",     group = GROUP_BONUS,     configKey = "NPC_Artemis_Field_01" },
    { key = "Athena",        color = "AthenaDamageLight", group = GROUP_BONUS,     configKey = "NPC_Athena_01" },
    -- Keepsake
    { key = "HadesKeepsake", color = "HadesVoice",        group = GROUP_KEEPSAKES, duplicateOf = "Hades",             lootSourceType = "Keepsake" }
}

-- [D] SPECIALS (Complex Loot Sources)
local baseSpecials = {
    {
        metaKey = "ChaosBuffs",
        key = "Chaos",
        display = "Chaos Buffs",
        color = "ChaosVoice",
        group = GROUP_BONUS,
        packedVar = "PackedChaosBuff",
        lootSource = { type = "LootSet", key = "TrialUpgrade", subKey = "PermanentTraits" }
    },
    {
        metaKey = "ChaosCurses",
        key = "Chaos",
        display = "Chaos Curses",
        color = "ChaosVoice",
        group = GROUP_BONUS,
        packedVar = "PackedChaosCurse",
        lootSource = { type = "LootSet", key = "TrialUpgrade", subKey = "TemporaryTraits" }
    },
    {
        metaKey = "CirceBNB",
        key = "CirceBNB",
        display = "Black Night Banishment",
        color = "CirceVoice",
        group = GROUP_SF_NPC,
        packedVar = "PackedCirceBNB",
        lootSource = { type = "MetaUpgrade", dataSource = "MetaUpgradeData", exclude = { BaseMetaUpgrade = true } }
    },
    {
        metaKey = "CirceCRD",
        key = "CirceCRD",
        display = "Red Citrine Divination",
        color = "CirceVoice",
        group = GROUP_SF_NPC,
        packedVar = "PackedCirceCRD",
        lootSource = { type = "MetaUpgrade", dataSource = "MetaUpgradeCardData", exclude = { BaseMetaUpgrade = true, BaseBonusMetaUpgrade = true } }
    },
    {
        metaKey = "Judgement1",
        key = "Judgement1",
        display = "First Biome Judgement",
        color = "HadesVoice",
        group = GROUP_BONUS,
        packedVar = "PackedJudgement1",
        lootSource = { type = "MetaUpgrade", dataSource = "MetaUpgradeCardData", exclude = { BaseMetaUpgrade = true, BaseBonusMetaUpgrade = true } }
    },
    {
        metaKey = "Judgement2",
        key = "Judgement2",
        display = "Second Biome Judgement",
        color = "HadesVoice",
        group = GROUP_BONUS,
        packedVar = "PackedJudgement2",
        lootSource = { type = "MetaUpgrade", dataSource = "MetaUpgradeCardData", exclude = { BaseMetaUpgrade = true, BaseBonusMetaUpgrade = true } }
    },
    {
        metaKey = "Judgement3",
        key = "Judgement3",
        display = "Third Biome Judgement",
        color = "HadesVoice",
        group = GROUP_BONUS,
        packedVar = "PackedJudgement3",
        lootSource = { type = "MetaUpgrade", dataSource = "MetaUpgradeCardData", exclude = { BaseMetaUpgrade = true, BaseBonusMetaUpgrade = true } }
    }
}

-- =============================================================================
-- 4. EXPANSION LOGIC
-- =============================================================================

local currentSortIndex = 1

local function RegisterGod(key, data)
    meta[key] = data
    meta[key].sortIndex = currentSortIndex
    currentSortIndex = currentSortIndex + 1
end

-- PROCESS OLYMPIANS
for _, def in ipairs(baseOlympians) do
    local tiers       = def.tiers or MAX_GOD_TIERS
    local group       = def.group or GROUP_CORE
    local loot        = def.name .. "Upgrade"

    local srcData     = { type = "LootSet", key = loot }
    local dynamicBits = GetBitCount(srcData, def.name)

    RegisterGod(def.name, {
        key = def.name,
        displayTextKey = def.name,
        colorKey = def.color,
        packedConfig = { var = "Packed" .. def.name .. "1", offset = 0, bits = dynamicBits },
        lootSource = srcData,
        uiGroup = group,
        tier = 1,
        maxTiers = tiers
    })

    for i = 2, tiers do
        local key = def.name .. i
        RegisterGod(key, {
            key = key,
            displayTextKey = key,
            colorKey = def.color,
            -- Tiers share the same bit count as Tier 1
            packedConfig = { var = "Packed" .. def.name .. i, offset = 0, bits = dynamicBits },
            lootSource = srcData,
            duplicateOf = def.name,
            uiGroup = group,
            tier = i
        })
    end
end

-- PROCESS WEAPONS
for _, def in ipairs(baseWeapons) do
    local loot = "WeaponUpgrade"
    local srcData = { type = "WeaponUpgrade", key = loot }
    local dynamicBits = GetBitCount(srcData, def.key)
    local tiers = def.tiers or MAX_HAMMER_TIERS

    RegisterGod(def.key, {
        key = def.key,
        displayTextKey = "1st " .. def.display,
        colorKey = "Brown",
        packedConfig = { var = "Packed" .. def.key .. "1", offset = 0, bits = dynamicBits },
        lootSource = srcData,
        uiGroup = GROUP_HAMMERS,
        tier = 1,
        maxTiers = tiers -- Save the structural constant for logic padding
    })

    for i = 2, tiers do
        local key = def.key .. tostring(i)
        RegisterGod(key, {
            key = key,
            displayTextKey = GetOrdinal(i) .. " " .. def.display,
            colorKey = "Brown",
            packedConfig = { var = "Packed" .. def.key .. tostring(i), offset = 0, bits = dynamicBits },
            lootSource = srcData,
            duplicateOf = def.key,
            uiGroup = GROUP_HAMMERS,
            tier = i
        })
    end
end

-- PROCESS SINGLES
for _, def in ipairs(baseSingles) do
    local sourceType = def.lootSourceType or "UnitSet"
    local sourceData = {}

    if sourceType == "UnitSet" then
        sourceData = {
            type = "UnitSet",
            unitKey = "NPC_" .. def.key,
            configKey = def.configKey or
                ("NPC_" .. def.key .. "_01")
        }
    elseif sourceType == "SpellData" then
        sourceData = { type = "SpellData" }
    elseif sourceType == "Keepsake" then
        sourceData = { type = "Keepsake", key = def.key }
    end

    local dynamicBits = GetBitCount(sourceData, def.key)

    RegisterGod(def.key, {
        key = def.key,
        displayTextKey = def.display or def.key,
        colorKey = def.color,
        packedConfig = { var = "Packed" .. def.key, offset = 0, bits = dynamicBits },
        lootSource = sourceData,
        duplicateOf = def.duplicateOf,
        uiGroup = def.group
    })
end

-- PROCESS SPECIALS
for _, def in ipairs(baseSpecials) do
    local dynamicBits = GetBitCount(def.lootSource, def.key)
    RegisterGod(def.metaKey, {
        key = def.key,
        displayTextKey = def.display,
        colorKey = def.color,
        uiGroup = def.group,
        packedConfig = { var = def.packedVar, offset = 0, bits = dynamicBits },
        lootSource = def.lootSource
    })
end


internal.godMeta = meta


-- =============================================================================
-- 5. RARITY MAPPING
-- =============================================================================
local rarityEligible = {
    Aphrodite  = "PackedRarityAphrodite",
    Apollo     = "PackedRarityApollo",
    Ares       = "PackedRarityAres",
    Demeter    = "PackedRarityDemeter",
    Hephaestus = "PackedRarityHephaestus",
    Hera       = "PackedRarityHera",
    Hestia     = "PackedRarityHestia",
    Poseidon   = "PackedRarityPoseidon",
    Zeus       = "PackedRarityZeus",

    Hermes     = "PackedRarityHermes",
    Artemis    = "PackedRarityArtemis",
    Athena     = "PackedRarityAthena",
    Dionysus   = "PackedRarityDionysus"
}

for key, varName in pairs(rarityEligible) do
    if meta[key] then
        meta[key].rarityVar = varName
    end
end

-- 2. Propagate to Tiers/Duplicates
for _, entry in pairs(meta) do
    if entry.duplicateOf then
        local parent = meta[entry.duplicateOf]
        -- If parent has rarity enabled, child gets it too
        if parent and parent.rarityVar then
            entry.rarityVar = parent.rarityVar
        end
    end
end
