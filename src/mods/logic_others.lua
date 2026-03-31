---@meta _
---@diagnostic disable: lowercase-global
-- MICRO LOGIC: Boon Banning, Tiers, & Padding

local internal = RunDirectorBoonBans_Internal
local godMeta = internal.godMeta
local lib = rom.mods["adamant-ModpackLib"]

-- Initialize Runtime Info Table if missing
internal.godInfo = internal.godInfo or {}
local godInfo = internal.godInfo

-- Local Helpers
local band, lshift, rshift, bor, bnot = bit32.band, bit32.lshift, bit32.rshift, bit32.bor, bit32.bnot
local t_insert = table.insert


local function GetRunState()
    return internal.GetRunState()
end

local function IsBanManagerActive()
    return lib.isEnabled(config, internal.definition.modpack)
end

local function Log(fmt, ...)
    lib.log(internal.definition.id, config.DebugMode, fmt, ...)
end


--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

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

-- Calculates the banned count and total count for a single god.
local function UpdateGodStats(godKey)
    local entry = godInfo[godKey]
    if not entry or not entry.boons then return end

    local godConfig = internal.GetBanConfig(godKey)
    local count = 0
    
    for _, boon in ipairs(entry.boons) do
        if band(godConfig, boon.Mask) ~= 0 then
            count = count + 1
        end
    end
    
    entry.banned = count
    entry.total = #entry.boons
    entry.banLabel = string.format("(%d/%d Banned)", count, #entry.boons)
end
--------------------------------------------------------------------------------
-- BAN MANAGEMENT API (UI Wrappers)
--------------------------------------------------------------------------------

local function ResetGodBans(god)
    if godMeta[god] and godInfo[god] then
        -- Use Utils to safely clear bans without touching Pool Flag (Bit 31)
        internal.SetBanConfig(god, 0)
        godInfo[god].banned = 0
        
        if config.DebugMode then
            Log("[Micro] Reset bans for %s", god)
        end
    end
end

local function BanAllGodBans(god)
    local meta = godMeta[god]
    if meta and meta.packedConfig and godInfo[god] then
        -- Create a mask of 1s for the size of bits (e.g. 22 bits = 0x3FFFFF)
        local mask = lshift(1, meta.packedConfig.bits) - 1
        internal.SetBanConfig(god, mask)
        godInfo[god].banned = godInfo[god].total
        
        if config.DebugMode then
            Log("[Micro] Banned ALL for %s", god)
        end
    end
end

local function ResetAllBans()
    for god, _ in pairs(godInfo) do ResetGodBans(god) end
    if config.DebugMode then
        Log("[Micro] Global Ban Reset triggered.")
    end
end

local function RecalculateBannedCounts()
    for godKey, _ in pairs(godInfo) do
        UpdateGodStats(godKey)
    end
    if config.DebugMode then
        Log("[Micro] Recalculated all ban counts.")
    end
end
--------------------------------------------------------------------------------
-- POPULATE GOD INFO (Runtime Data Generation)
--------------------------------------------------------------------------------

local function PopulateGodInfo()
    godInfo.traitLookup = {}

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
            Key = boonKey, God = godKey, Bit = index, Mask = bitMask, 
            Name = displayName, Rarity = rarity 
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

    -- PASS 1: Load "Source" Gods
    for key, meta in pairs(godMeta) do
        -- Ensure entry exists
        if not godInfo[key] then
            godInfo[key] = { color = GetSourceColor(key), boons = {} }
        end

        if not meta.duplicateOf and meta.lootSource then
            local src = meta.lootSource
            
            if src.type == "LootSet" then
                local lootData = LootSetData[meta.key]
                if lootData and lootData[src.key] then
                    local upgradeData = lootData[src.key]
                    local index = 0
                    if upgradeData.WeaponUpgrades then
                        for _, boon in ipairs(upgradeData.WeaponUpgrades) do
                            addBoonToRuntime(key, boon, index); index = index + 1
                        end
                    end
                    if upgradeData.Traits then
                        for _, boon in ipairs(upgradeData.Traits) do
                            addBoonToRuntime(key, boon, index); index = index + 1
                        end
                    end
                    if upgradeData[src.subKey] then
                        for _, boon in ipairs(upgradeData[src.subKey]) do
                            addBoonToRuntime(key, boon, index); index = index + 1
                        end
                    end
                end

            elseif src.type == "UnitSet" then
                if UnitSetData[src.unitKey] and UnitSetData[src.unitKey][src.configKey] then
                    local traitList = UnitSetData[src.unitKey][src.configKey].Traits
                    if traitList then
                        for i, boon in ipairs(traitList) do
                            addBoonToRuntime(key, boon, i-1)
                        end
                    end
                end

            elseif src.type == "SpellData" then
                local spellNames = {}
                for spellName, _ in pairs(SpellData) do t_insert(spellNames, spellName) end
                table.sort(spellNames)
                for i, spellName in ipairs(spellNames) do
                    local spellData = SpellData[spellName]
                    local name = game.GetDisplayName({ Text = spellData.TraitName })
                    addBoonToRuntime(key, spellName, i-1, name)
                end

            elseif src.type == "WeaponUpgrade" then
                 if LootSetData.Loot and LootSetData.Loot.WeaponUpgrade and LootSetData.Loot.WeaponUpgrade.Traits then
                    local daedalusTraits = LootSetData.Loot.WeaponUpgrade.Traits
                    local prefixes = meta.prefixes or { key }
                    
                    local currentIndex = 0
                    for _, trait in ipairs(daedalusTraits) do
                        local match = false
                        for _, p in ipairs(prefixes) do
                            if string.find(trait, p, 1, true) == 1 then
                                match = true; break
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
                    
                    -- [NEW] FALLBACK ALPHABETICAL
                    -- Catch any keys (like Shrine Upgrades) that aren't in the layout
                    local remaining = {}
                    for k, _ in pairs(dataSource) do
                        if not orderMap[k] then
                            t_insert(remaining, k)
                        end
                    end
                    table.sort(remaining)
                    
                    for _, k in ipairs(remaining) do
                        t_insert(sortedKeys, k)
                    end

                    local index = 0
                    for _, upgradeName in ipairs(sortedKeys) do
                        local data = dataSource[upgradeName]
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
            UpdateGodStats(key)
        end
    end

    -- PASS 2: Load "Duplicate" Gods
    for key, meta in pairs(godMeta) do
        if meta.duplicateOf then
            local parentKey = meta.duplicateOf
            local parentEntry = godInfo[parentKey]
            
            if parentEntry then
                -- godInfo[key] initialized at top of loop
                for _, parentBoon in ipairs(parentEntry.boons) do
                    addBoonToRuntime(key, parentBoon.Key, parentBoon.Bit, parentBoon.Name)
                end
                UpdateGodStats(key)
            end
        end
    end

    if config.DebugMode then
        Log("[Micro] GodInfo Populated.")
    end
end

--------------------------------------------------------------------------------
-- TRAIT SELECTION LOGIC
--------------------------------------------------------------------------------

function internal.GetOrRecalcBoonCounts()
    local state = GetRunState()
    local PickCounts = state.BoonPickCounts

    if PickCounts then
        return PickCounts
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

    -- 1. Resolve Target Entry
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
    if not targetEntry then targetEntry = list[1] end

    -- 2. Determine Tier (THE OPTIMIZATION)
    local targetTier = knownTier
    
    if not targetTier then
        -- Only calculate if we weren't told the Tier
        local rootKey = GetRootKey(targetEntry.god)
        local pickCounts = internal.GetOrRecalcBoonCounts()
        local currentPicks = pickCounts[rootKey] or 0
        targetTier = currentPicks + 1
    end

    -- 3. Find Matching Mask
    for i = 1, #list do
        local entry = list[i]
        local meta = godMeta[entry.god]
        local entryTier = meta.tier or 1
        
        -- Note: We use the entry's own god root for comparison logic if needed,
        -- but usually we just match the tier requirement.
        if entryTier == targetTier then
            -- Optional: Ensure we are matching the correct God family if filtered
            if not filterGodKey or GetRootKey(entry.god) == filterGodKey then
                return entry
            end
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- CIRCE SPECIFIC LOGIC
--------------------------------------------------------------------------------
modutil.mod.Path.Wrap("CirceRemoveShrineUpgrades", function(base, args)
    if not IsBanManagerActive() then return base(args) end
    local restores = {}
    if godInfo["CirceBNB"] then
        local configVal = internal.GetBanConfig("CirceBNB")
        for _, vow in ipairs(godInfo["CirceBNB"].boons) do
            local name = vow.Key
            local isBanned = band(configVal, vow.Mask) ~= 0
            if MetaUpgradeData[name] and isBanned then
                restores[name] = MetaUpgradeData[name].IneligibleForCirceRemoval
                MetaUpgradeData[name].IneligibleForCirceRemoval = true
            end
        end
    end
    base(args)
    for name, val in pairs(restores) do
        MetaUpgradeData[name].IneligibleForCirceRemoval = val
    end
end)

modutil.mod.Path.Wrap("CirceRandomMetaUpgrade", function(base, args)
    if not IsBanManagerActive() then return base(args) end
    local restores = {}
    local metaState = GameState.MetaUpgradeState or {}
    if godInfo["CirceCRD"] then
        local configVal = internal.GetBanConfig("CirceCRD")
        for _, card in ipairs(godInfo["CirceCRD"].boons) do
            local name = card.Key
            local isBanned = band(configVal, card.Mask) ~= 0
            if metaState[name] and not metaState[name].Equipped and isBanned then
                metaState[name].Equipped = true
                restores[name] = true
            end
        end
    end
    base(args)
    for name, _ in pairs(restores) do
        metaState[name].Equipped = false
    end
end)

modutil.mod.Path.Wrap("AddRandomMetaUpgrades", function(base, numCards, args)
    if not IsBanManagerActive() then return base(numCards, args) end
    if numCards and numCards ~= GetTotalHeroTraitValue("PostBossCards") then return base(numCards, args) end

    local restores = {}
    local metaState = GameState.MetaUpgradeState or {}
    local currentBiome = CurrentRun.ClearedBiomes or 0
    local judgementKey = "Judgement" .. tostring(math.min(currentBiome, 3))
    -- print("RunDirector: [Micro] AddRandomMetaUpgrades - Current Biome: " .. tostring(currentBiome) .. ", Target Key: " .. judgementKey .. ", NumCards: " .. tostring(numCards))
    if godInfo[judgementKey] then
        local configVal = internal.GetBanConfig(judgementKey)
        for _, card in ipairs(godInfo[judgementKey].boons) do
            local name = card.Key
            local isBanned = band(configVal, card.Mask) ~= 0
            if metaState[name] and not metaState[name].Equipped and isBanned then
                metaState[name].Equipped = true
                restores[name] = true
            end
        end
    end
    base(numCards, args)
    for name, _ in pairs(restores) do
        metaState[name].Equipped = false
    end
end)

--------------------------------------------------------------------------------
-- GAME HOOKS
--------------------------------------------------------------------------------
local function wrapNPCChoice(funcName)
    modutil.mod.Path.Wrap(funcName, function(base, source, args, screen)

        if IsBanManagerActive() and args.UpgradeOptions then
            local allowed, banned = {}, {}
            local configCache = {} 

            for _, option in ipairs(args.UpgradeOptions) do
                if option.GameStateRequirements == nil or IsGameStateEligible(source, option.GameStateRequirements) then
                    local info = internal.FindTraitInfo(option.ItemName, nil)
                    local isBanned = false
                    if info then
                        local cfg = configCache[info.god] or internal.GetBanConfig(info.god)
                        configCache[info.god] = cfg
                        if band(cfg, info.mask) ~= 0 then isBanned = true end
                    end

                    if not isBanned then t_insert(allowed, option)
                    else t_insert(banned, option) end
                end
            end
			
            if #allowed > 0 and (config.EnablePadding or funcName == "CirceBlessingChoice") then
                if #allowed < GetTotalLootChoices() then
                    local pool = {}
                    for _, b in ipairs(banned) do t_insert(pool, b) end
                    local seen = {}
                    for _, a in ipairs(allowed) do seen[a.ItemName] = true end
                    
                    while #allowed < GetTotalLootChoices() and #pool > 0 do
                        local idx = math.random(1, #pool)
                        local pick = pool[idx]
                        if pick and not seen[pick.ItemName] then
                            t_insert(allowed, pick)
                            seen[pick.ItemName] = true
                        end
                        pool[idx] = pool[#pool]; pool[#pool] = nil
                    end
                end
                args.UpgradeOptions = allowed
            elseif #allowed > 0 then
                 args.UpgradeOptions = allowed
            end
            
            if config.DebugMode and #banned > 0 then
                Log("[Micro] NPC Choice (%s): Allowed %d, Banned %d", funcName, #allowed, #banned)
            end
        end
        return base(source, args, screen)
    end)
end

modutil.mod.Path.Wrap("GetEligibleSpells", function(base, screen, args)
    local eligible = base(screen, args)
    if not IsBanManagerActive() then return eligible end

    local allowed, banned = {}, {}
    local configCache = {}

    for _, spellName in ipairs(eligible) do
        local info = internal.FindTraitInfo(spellName, nil)
        local isBanned = false
        if info then
            local cfg = configCache[info.god] or internal.GetBanConfig(info.god)
            configCache[info.god] = cfg
            if band(cfg, info.mask) ~= 0 then isBanned = true end
        end
        
        if not isBanned then t_insert(allowed, spellName)
        else t_insert(banned, spellName) end
    end
    
    if config.DebugMode then
        Log("[Micro] GetEligibleSpells: Allowed %d, Banned %d", #allowed, #banned)
    end

    if #allowed == 0 then return eligible end

    if #allowed < GetTotalLootChoices() and config.EnablePadding then
        local pool = {table.unpack(banned)}
        local seen = {}
        for _, a in ipairs(allowed) do seen[a] = true end
        while #allowed < GetTotalLootChoices() and #pool > 0 do
            local idx = math.random(1, #pool)
            local pick = pool[idx]
            if pick and not seen[pick] then
                t_insert(allowed, pick); seen[pick] = true
            end
            pool[idx] = pool[#pool]; pool[#pool] = nil
        end
    end
    return allowed
end)

function internal.GetGodFromLootsource(lootKey)
    for godKey, meta in pairs(godMeta) do
        if meta.lootSource and meta.lootSource.key == lootKey then
            if lootKey == "WeaponUpgrade" then
                local currentWeapon = GetEquippedWeapon()
                if string.find(currentWeapon, godKey, 1, true) then
                    return internal.GetRootKey(godKey)
                end
            else
                return internal.GetRootKey(godKey)
            end
        end
    end
    return nil
end


modutil.mod.Path.Wrap("OpenUpgradeChoiceMenu", function(base, source, args)
  if IsBanManagerActive() and source and source.Name then
    internal.ActiveGodKey = internal.GetGodFromLootsource(source.Name)
  end
  base(source, args)
end)

modutil.mod.Path.Wrap("AddTraitToHero", function(base, args)
    local result = base(args)
    local traitData = args.TraitData
    local state = GetRunState()
    
    if IsBanManagerActive() and traitData then
        internal.GetOrRecalcBoonCounts()
        local godKey = internal.ActiveGodKey
        if config.DebugMode then
            Log("[Micro] AddTraitToHero: Found godKey %s from (trait: %s)", godKey, traitData.Name)
        end
        if not godKey then
            local info = internal.FindTraitInfo(traitData.Name, nil)
            if info then godKey = GetRootKey(info.god) end
        end
        local TraitUpgrade = args.SkipSetup or args.SkipActivatedTraitUpdate or args.SkipNewTraitHighlight 

        if godKey and state.BoonPickCounts then
            if not TraitUpgrade then
                state.BoonPickCounts[godKey] = (state.BoonPickCounts[godKey] or 0) + 1
                if config.DebugMode then
                    Log("[Micro] AddTraitToHero: %s. God: %s. New Count: %d", traitData.Name, tostring(godKey), state.BoonPickCounts[godKey])
                end
            end
        end
        internal.ActiveGodKey = nil
    end
    
    if IsBanManagerActive() and traitData then
        if CurrentRun and state.ImproveFirstNBoonRarity and IsGodTrait(traitData.Name) then
            state.ImproveFirstNBoonRarity = math.max(0, state.ImproveFirstNBoonRarity - 1)
        end
    end
    return result
end)


modutil.mod.Path.Wrap("GetRarityChances", function(base, loot)
    local ch = base(loot)
    local state = GetRunState()
    if IsBanManagerActive() and CurrentRun and state.ImproveFirstNBoonRarity>0 and loot.GodLoot then
        ch.Common, ch.Rare, ch.Epic = 0.0, 0.0 , 1.0
    end
    return ch
end)

-- modutil.mod.Path.Wrap("UpdateTimers", function(base, elapsed)
--     if CurrentRun == nil then
--         return
--     end

--     base(elapsed)

--     if config.DebugMode then
--         print(string.format("RunDirector: [Micro] UpdateTimers - Elapsed: %.2f, TotalTime: %.2f", elapsed, CurrentRun.GameplayTime))
--     end

--     	if CurrentRun.ActiveBiomeTimer and not IsBiomeTimerPaused() then
-- 		CurrentRun.BiomeTime = CurrentRun.BiomeTime - elapsed
-- 		local threshold = 30
-- 		if CurrentRun.BiomeTime <= threshold and (CurrentRun.BiomeTime + elapsed) > threshold then
-- 			BiomeTimerAboutToExpirePresentation(threshold )
-- 		elseif CurrentRun.BiomeTime <= 0 and (CurrentRun.BiomeTime + elapsed) > 0 then
-- 			BiomeTimerExpiredPresentation()
-- 		end
-- 	end
-- end)



PopulateGodInfo()

local npcFunctions = {
    "ArachneCostumeChoice", "NarcissusBenefitChoice", "EchoChoice", 
    "MedeaCurseChoice", "CirceBlessingChoice", "IcarusBenefitChoice"
}
for _, func in ipairs(npcFunctions) do wrapNPCChoice(func) end

-- EXPORTS
internal.ResetGodBans = ResetGodBans
internal.BanAllGodBans = BanAllGodBans
internal.ResetAllBans = ResetAllBans
internal.GetRootKey = GetRootKey
internal.RecalculateBannedCounts = RecalculateBannedCounts
