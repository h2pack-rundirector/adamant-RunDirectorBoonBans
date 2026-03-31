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

-- State Flags
local isKeepsakeOffering = false
local skipIsTraitEligible = false


-- Helper to shuffle a table in place
local function ShuffleTable(t)
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

local function GetOccupiedSlots()
    local occupied = {}
    if CurrentRun and CurrentRun.Hero and CurrentRun.Hero.Traits then
        for _, trait in pairs(CurrentRun.Hero.Traits) do
            if trait.Slot then 
                occupied[trait.Slot] = true 
            end
        end
    end

    if config.DebugMode then
        local slots = {"Melee", "Secondary", "Ranged", "Rush", "Mana"} -- Standard Slots
        local occupiedList = {}
        for _, slot in ipairs(slots) do
            if occupied[slot] then table.insert(occupiedList, slot) end
        end
        Log("[Micro] Occupied Slots: %s", table.concat(occupiedList, ", "))
    end

    return occupied
end

-- Generator now accepts 'priorityList' (string array of Boon Names)
local function GeneratePriorityQueue(allowed, banned, godKey, currentTier, isHammer, priorityList, queueMaxSize)
    local queue = {}
    local duoLegendaryQueue = {}

    -- 1. HIGH PRIORITY: Forced Allowed Options
    for _, p in ipairs(allowed) do
        local pname = p.ItemName or p.Name or p.TraitName
        if pname then
            -- [OPTIMIZATION] Skip TraitData lookups entirely for Hammers
            if not isHammer then
                local trait = TraitData[pname]
                local isDuo = trait and (trait.IsDuoBoon == true)
                local isLegendary = trait and (trait.RarityLevels and trait.RarityLevels.Legendary ~= nil)

                if isDuo or isLegendary then
                    p.rarity = isDuo and "Duo" or "Legendary"
                    table.insert(duoLegendaryQueue, p)
                end
            end

            if #queue < queueMaxSize then
                table.insert(queue, p)
            end
        end
    end

    -- 2. LOW PRIORITY: Padding Logic
    if config.EnablePadding and #banned > 0 then

        -- Config: Use Priority Logic?
        local usePriority = (config.Padding_UsePriority ~= false)
        local prioritySet = {}
        if usePriority and priorityList then
            for _, name in ipairs(priorityList) do prioritySet[name] = true end
        end

        local highPrioPool = {}
        local lowPrioPool = {}

        for _, p in ipairs(banned) do
            local pname = p.ItemName or p.Name or p.TraitName
            local isHighPrio = usePriority and pname and prioritySet[pname]

            if isHighPrio then
                table.insert(highPrioPool, p)
            else
                table.insert(lowPrioPool, p)
            end
        end

        -- SHUFFLE POOLS
        ShuffleTable(highPrioPool)
        ShuffleTable(lowPrioPool)

        local finalPool = {}
        local bias = config.Padding_PriorityChance or 0.75

        -- FILL STRATEGY: Weighted Mix
        while #highPrioPool > 0 or #lowPrioPool > 0 do
             local pickHigh = false

             if #highPrioPool > 0 and #lowPrioPool > 0 then
                 if math.random() < bias then pickHigh = true end
             elseif #highPrioPool > 0 then
                 pickHigh = true
             end

             if pickHigh then
                 table.insert(finalPool, table.remove(highPrioPool))
             else
                 table.insert(finalPool, table.remove(lowPrioPool))
             end
        end

        -- APPLY FINAL FILTERS
        local avoidFuture = (config.Padding_AvoidFutureAllowed ~= false)
        local allowDuos   = (config.Padding_AllowDuos == true)

        for _, p in ipairs(finalPool) do
            local skipPadding = false

            -- [OPTIMIZATION] Fast-lane for Hammers. Skip all logic.
            if not isHammer then
                local pname = p.ItemName or p.Name or p.TraitName

                -- Filter 1: No-Spoilers (Don't pad with Duos/Legendaries)
                if not allowDuos then
                    local trait = TraitData[pname]
                    if trait and (trait.IsDuoBoon or (trait.RarityLevels and trait.RarityLevels.Legendary)) then
                        skipPadding = true
                    end
                end

                -- Filter 2: Future-Proofing
                if avoidFuture and not skipPadding and pname and godKey then
                    local info = internal.FindTraitInfo(pname, godKey)
                    if info then
                        local rootMeta = godMeta[godKey]
                        local maxTiers = (rootMeta and rootMeta.maxTiers) or 1
                        for t = currentTier + 1, maxTiers do
                            local futureKey = (t == 1) and godKey or (godKey .. tostring(t))
                            if godMeta[futureKey] then
                                local futureConfig = internal.GetBanConfig(futureKey)
                                if band(futureConfig, info.mask) == 0 then
                                    skipPadding = true
                                    break
                                end
                            end
                        end
                    end
                end
            end

            if not skipPadding and #queue < queueMaxSize then
                table.insert(queue, p)
            end
        end
    end

    if config.DebugMode and #queue > 0 then
        Log("[Micro] PriorityQueue generated. Items: %d", #queue)
    end

    return queue, duoLegendaryQueue
end

-- local POMPrefix = "StackUpgrade"
modutil.mod.Path.Wrap("GetEligibleUpgrades", function(base, upgradeOptions, lootData, upgradeChoiceData)
    if not IsBanManagerActive() then return base(upgradeOptions, lootData, upgradeChoiceData) end

    -- local isPOM = (string.sub(lootData.Name, 1, #POMPrefix) == POMPrefix)
    -- if isPOM then
    --     -- For PoM, we want to skip all ban logic and just return the full list.
    --     if config.DebugMode then
    --         print("RunDirector: [Micro] Skipping ban logic for PoM upgrade.")
    --     end
    --     return base(upgradeOptions, lootData, upgradeChoiceData)
    -- end

    local currentGodKey = internal.GetGodFromLootsource(lootData.Name)
    local isHammer = (lootData.Name == "WeaponUpgrade")

    local currentRunPicks = internal.GetOrRecalcBoonCounts()
    local count = currentRunPicks[currentGodKey] or 0
    local targetTier = count + 1

    if config.DebugMode then
        Log("[Micro] Inspecting Loot: %s (God: %s, Tier: %d)", lootData.Name, tostring(currentGodKey), targetTier)
    end

    if currentGodKey then
        local metaKey = (targetTier == 1) and currentGodKey or (currentGodKey .. tostring(targetTier))
        if not godMeta[metaKey] then
             if config.DebugMode then
                Log("[Micro] Early exit for %s (Tier %d not configured)", tostring(currentGodKey), targetTier)
             end
             return base(upgradeOptions, lootData, upgradeChoiceData)
        end
    end
    
    skipIsTraitEligible = true
    local fullList = base(upgradeOptions, lootData, upgradeChoiceData) or {}
    skipIsTraitEligible = false

    local allowed, banned = {}, {}
    local configCache = {}

    for _, opt in ipairs(fullList) do
        local name = opt and (opt.ItemName or opt.Name or opt.TraitName)
        if name then
            local info = internal.FindTraitInfo(name, currentGodKey, targetTier)
            local isBanned = false
            if info then
                local cfg = configCache[info.god] or internal.GetBanConfig(info.god)
                configCache[info.god] = cfg
                if band(cfg, info.mask) ~= 0 then isBanned = true end
            end

            if not isBanned then
                table.insert(allowed, opt)
            else
                table.insert(banned, opt)
            end
        end
    end

    if config.DebugMode then
        Log("[Micro] Loot Result: Passed %d, Banned %d", #allowed, #banned)
    end

    if #allowed == 0 then return fullList end

    local priorityList = lootData.PriorityUpgrades
    local queue, duoLegendaryQueue = GeneratePriorityQueue(allowed, banned, currentGodKey, targetTier, isHammer, priorityList, GetTotalLootChoices())
    if config.DebugMode then
        Log("Generated Priority Queue:")
        for i, q in ipairs(queue) do
            Log("  %d. %s (Rarity: %s)", i, q.ItemName, tostring(q.rarity))
        end
    end
    CurrentRun._banManager_DuoLegendaryQueue = duoLegendaryQueue

    return queue
end)

modutil.mod.Path.Wrap("GetReplacementTraits", function(base, traitNames, onlyFromLootName)
    skipIsTraitEligible = true
    local result = base(traitNames, onlyFromLootName)
    skipIsTraitEligible = false
    return result
end)

modutil.mod.Path.Wrap("SetTraitsOnLoot", function(base, lootData, args)
    -- 1. LET VANILLA RUN (The "First Draft")
    -- This populates lootData.UpgradeOptions with valid, randomized loot.

    local restoreChance = nil
    if IsBanManagerActive() and CurrentRun.Hero.BoonData then
        restoreChance = CurrentRun.Hero.BoonData.ReplaceChance
        CurrentRun.Hero.BoonData.ReplaceChance = 0.0 
    end

    base(lootData, args)

    if restoreChance ~= nil then
        CurrentRun.Hero.BoonData.ReplaceChance = restoreChance
    end

    if not IsBanManagerActive() then return end

    -- 1. FORCE RARITY: Upgrade the rarity of specific traits based on config (if they are present in the loot).
    if config.DebugMode then
        Log("[Micro] Applying forced Epic rarity to specific traits (if present in loot).")
    end
    --Keep this code block. It does rarity forcing and ignores tiers for rarity. The next block respects tiers.
    -- for _, item in ipairs(lootData.UpgradeOptions) do
    --     local name = item.ItemName or item.Name
        
    --     -- Safe to use nil because base boons are unambiguously tied to one god
    --     local info = internal.FindTraitInfo(name, nil)
        
    --     if info and info.god then
    --         local rootKey = internal.GetRootKey(info.god)
            
    --         -- Check if this Olympian supports Rarity Config
    --         if godMeta[rootKey] and godMeta[rootKey].rarityVar then
                
    --             -- Directly check the rarity value, ignoring tier and ban status
    --             local rVal = internal.GetRarityValue(rootKey, info.bit)
    --             if rVal > 0 then
    --                 local rarityMap = { [1]="Common", [2]="Rare", [3]="Epic" }
    --                 local targetRarity = rarityMap[rVal]
                    
    --                 if targetRarity then
    --                     item.Rarity = targetRarity
    --                     item.ForceRarity = true 
                        
    --                     if config.DebugMode then
    --                         print(string.format("RunDirector: [Rarity] Forced %s on %s", targetRarity, name))
    --                     end
    --                 end
    --             end
    --         end
    --     end
    -- end

    -- Resolve the exact god and tier for this specific menu
    local currentGodKey = internal.GetGodFromLootsource(lootData.Name)
    local targetTier = 1
    if currentGodKey then
        local currentRunPicks = internal.GetOrRecalcBoonCounts()
        targetTier = (currentRunPicks[currentGodKey] or 0) + 1
    end

    for _, item in ipairs(lootData.UpgradeOptions) do
        local name = item.ItemName or item.Name
        
        -- Safe to use nil because base boons are unambiguously tied to one god
        local info = internal.FindTraitInfo(name, nil)
        
        if info and info.god then
            local rootKey = internal.GetRootKey(info.god)
            
            -- Check if this Olympian supports Rarity Config
            if godMeta[rootKey] and godMeta[rootKey].rarityVar then
                
                -- Construct the tier-specific key to check the correct ban list
                local tierKey = rootKey
                if currentGodKey == rootKey and targetTier > 1 then
                    tierKey = rootKey .. tostring(targetTier)
                end
                
                local banConfig = internal.GetBanConfig(tierKey) 
                local isBanned = band(banConfig, info.mask) ~= 0

                -- Only apply rarity if the boon is ALLOWED in this tier
                if not isBanned then
                    local rVal = internal.GetRarityValue(rootKey, info.bit)
                    if rVal > 0 then
                        local rarityMap = { [1]="Common", [2]="Rare", [3]="Epic" }
                        local targetRarity = rarityMap[rVal]
                        
                        if targetRarity then
                            item.Rarity = targetRarity
                            item.ForceRarity = true 
                            
                            if config.DebugMode then
                                Log("[Rarity] Forced %s on %s", targetRarity, name)
                            end
                        end
                    end
                end
            end
        end
    end

    -- 2. GET THE ORDERS: Retrieve the Strict Queue
    local priorityQueue = CurrentRun._banManager_DuoLegendaryQueue

    if not priorityQueue or #priorityQueue == 0 then 
        CurrentRun._banManager_DuoLegendaryQueue = nil -- Clean up
        return 
    end

    -- 3. ANALYZE THE DRAFT
    -- Map existing items so we know what we have
    local existingItems = {}
    for i, opt in ipairs(lootData.UpgradeOptions) do
        existingItems[opt.ItemName] = i
    end

    -- 4. FORCE STRICT ITEMS (The "Correction")
    -- We only enforce the Top N items, where N is the menu size (usually 3).
    local maxChoices = GetTotalLootChoices() -- 3
    local slotsToEnforce = math.min(#priorityQueue, maxChoices)

    for i = 1, slotsToEnforce do
        local queueItem = priorityQueue[i]
        
        -- We only intervene for "Forced" items (Duos / Legendaries) that are MISSING.
        -- Normal items are allowed to be skipped by RNG (that's the "Fairness").
        if not existingItems[queueItem.ItemName] then
            
            -- We need to insert this item.
            -- Strategy: Overwrite the last slot (Slot 3), unless we have empty space.
            local targetSlot = #lootData.UpgradeOptions
            if targetSlot < maxChoices then
                targetSlot = targetSlot + 1
            end

            -- If we are overwriting, try not to overwrite another Forced item (rare edge case)
            -- But usually, Slot 3 is fair game.
            
            -- Construct the forced option
            local newOption = {
                ItemName = queueItem.ItemName,
                Type = "Trait",
                Rarity = queueItem.rarity, -- "Duo" or "Legendary"
                ForceRarity = true -- Helper flag
            }
            
            -- INJECT IT
            lootData.UpgradeOptions[targetSlot] = newOption
            
            -- Update map so we don't try to add it twice
            existingItems[queueItem.ItemName] = targetSlot
            
            if config.DebugMode then
                Log("[Micro] Forced missing item '%s' into Slot %d", queueItem.ItemName, targetSlot)
            end
        end
    end

    -- 5. FINAL CLEANUP
    -- Ensure rerolls are allowed (since we might have just fixed a broken menu)
    lootData.BlockReroll = false
    CurrentRun._banManager_DuoLegendaryQueue = nil
end)

modutil.mod.Path.Wrap("IsTraitEligible", function(base, traitData, args)
    if not IsBanManagerActive() or skipIsTraitEligible  then return base(traitData, args) end
    
    local info = internal.FindTraitInfo(traitData.Name, nil)
    if info then
        -- Handle Keepsake context (Hades vs HadesKeepsake logic)
        if isKeepsakeOffering and info.god == "Hades" and godMeta[info.god].duplicateOf == nil then
             local keepsakeVar = godInfo["HadesKeepsake"]
             if keepsakeVar then
                 local cfg = internal.GetBanConfig("HadesKeepsake")
                 if band(cfg, info.mask) ~= 0 then return false end
                 return base(traitData, args)
             end
        end

        if band(internal.GetBanConfig(info.god), info.mask) ~= 0 then 
            if config.DebugMode then
                Log("[Micro] IsTraitEligible BLOCKED: %s", traitData.Name)
            end
            return false 
        end
    end
    return base(traitData, args)
end)

modutil.mod.Path.Wrap("GiveRandomHadesBoonAndBoostBoons", function(base, args)
    isKeepsakeOffering = true
    local result = base(args)
    isKeepsakeOffering = false
    return result
end)
