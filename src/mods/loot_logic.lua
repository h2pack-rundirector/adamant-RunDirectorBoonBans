---@meta _
---@diagnostic disable: lowercase-global

local internal = RunDirectorBoonBans_Internal
local godMeta = internal.godMeta

internal.godInfo = internal.godInfo or {}
local godInfo = internal.godInfo

local band = bit32.band

local function IsBanManagerActive()
    return internal.IsBanManagerActive()
end

local function Log(fmt, ...)
    lib.log(internal.definition.id, store.read("DebugMode") == true, fmt, ...)
end

local isKeepsakeOffering = false
local skipIsTraitEligible = false

local function ShuffleTable(t)
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

local function GeneratePriorityQueue(allowed, banned, godKey, currentTier, isHammer, priorityList, queueMaxSize)
    local queue = {}
    local duoLegendaryQueue = {}

    for _, pending in ipairs(allowed) do
        local pendingName = pending.ItemName or pending.Name or pending.TraitName
        if pendingName then
            if not isHammer then
                local trait = TraitData[pendingName]
                local isDuo = trait and (trait.IsDuoBoon == true)
                local isLegendary = trait and (trait.RarityLevels and trait.RarityLevels.Legendary ~= nil)

                if isDuo or isLegendary then
                    pending.rarity = isDuo and "Duo" or "Legendary"
                    table.insert(duoLegendaryQueue, pending)
                end
            end

            if #queue < queueMaxSize then
                table.insert(queue, pending)
            end
        end
    end

    if store.read("EnablePadding") and #banned > 0 then
        local usePriority = (store.read("Padding_UsePriority") ~= false)
        local prioritySet = {}
        if usePriority and priorityList then
            for _, name in ipairs(priorityList) do
                prioritySet[name] = true
            end
        end

        local highPrioPool = {}
        local lowPrioPool = {}

        for _, pending in ipairs(banned) do
            local pendingName = pending.ItemName or pending.Name or pending.TraitName
            local isHighPrio = usePriority and pendingName and prioritySet[pendingName]

            if isHighPrio then
                table.insert(highPrioPool, pending)
            else
                table.insert(lowPrioPool, pending)
            end
        end

        ShuffleTable(highPrioPool)
        ShuffleTable(lowPrioPool)

        local finalPool = {}
        local bias = math.max(0, math.min(100, store.read("Padding_PriorityChance") or 75)) / 100
        while #highPrioPool > 0 or #lowPrioPool > 0 do
            local pickHigh = false

            if #highPrioPool > 0 and #lowPrioPool > 0 then
                if math.random() < bias then
                    pickHigh = true
                end
            elseif #highPrioPool > 0 then
                pickHigh = true
            end

            if pickHigh then
                table.insert(finalPool, table.remove(highPrioPool))
            else
                table.insert(finalPool, table.remove(lowPrioPool))
            end
        end

        local avoidFuture = (store.read("Padding_AvoidFutureAllowed") ~= false)
        local allowDuos = (store.read("Padding_AllowDuos") == true)

        for _, pending in ipairs(finalPool) do
            local skipPadding = false

            if not isHammer then
                local pendingName = pending.ItemName or pending.Name or pending.TraitName

                if not allowDuos then
                    local trait = TraitData[pendingName]
                    if trait and (trait.IsDuoBoon or (trait.RarityLevels and trait.RarityLevels.Legendary)) then
                        skipPadding = true
                    end
                end

                if avoidFuture and not skipPadding and pendingName and godKey then
                    local info = internal.FindTraitInfo(pendingName, godKey)
                    if info then
                        local rootMeta = godMeta[godKey]
                        local maxTiers = (rootMeta and rootMeta.maxTiers) or 1
                        for tier = currentTier + 1, maxTiers do
                            local futureKey = (tier == 1) and godKey or (godKey .. tostring(tier))
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
                table.insert(queue, pending)
            end
        end
    end

    if store.read("DebugMode") and #queue > 0 then
        Log("[Micro] PriorityQueue generated. Items: %d", #queue)
    end

    return queue, duoLegendaryQueue
end

modutil.mod.Path.Wrap("GetEligibleUpgrades", function(base, upgradeOptions, lootData, upgradeChoiceData)
    if not IsBanManagerActive() then return base(upgradeOptions, lootData, upgradeChoiceData) end

    local currentGodKey = internal.GetGodFromLootsource(lootData.Name)
    local isHammer = (lootData.Name == "WeaponUpgrade")

    local count = (internal.GetOrRecalcBoonCounts()[currentGodKey] or 0)
    local targetTier = count + 1

    Log("[Micro] Inspecting Loot: %s (God: %s, Tier: %d)", lootData.Name, tostring(currentGodKey), targetTier)

    if currentGodKey then
        local metaKey = (targetTier == 1) and currentGodKey or (currentGodKey .. tostring(targetTier))
        if not godMeta[metaKey] then
            Log("[Micro] Early exit for %s (Tier %d not configured)", tostring(currentGodKey), targetTier)
            return base(upgradeOptions, lootData, upgradeChoiceData)
        end
    end

    skipIsTraitEligible = true
    local fullList = base(upgradeOptions, lootData, upgradeChoiceData) or {}
    skipIsTraitEligible = false

    local allowed = {}
    local banned = {}
    local configCache = {}

    for _, option in ipairs(fullList) do
        local name = option and (option.ItemName or option.Name or option.TraitName)
        if name then
            local info = internal.FindTraitInfo(name, currentGodKey, targetTier)
            local isBanned = false
            if info then
                local cfg = configCache[info.god] or internal.GetBanConfig(info.god)
                configCache[info.god] = cfg
                if band(cfg, info.mask) ~= 0 then
                    isBanned = true
                end
            end

            if not isBanned then
                table.insert(allowed, option)
            else
                table.insert(banned, option)
            end
        end
    end

    Log("[Micro] Loot Result: Passed %d, Banned %d", #allowed, #banned)

    if #allowed == 0 then return fullList end

    local queue, duoLegendaryQueue = GeneratePriorityQueue(
        allowed,
        banned,
        currentGodKey,
        targetTier,
        isHammer,
        lootData.PriorityUpgrades,
        GetTotalLootChoices()
    )

    if store.read("DebugMode") then
        Log("Generated Priority Queue:")
        for i, queued in ipairs(queue) do
            Log("  %d. %s (Rarity: %s)", i, queued.ItemName, tostring(queued.rarity))
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

    Log("[Micro] Applying forced Epic rarity to specific traits (if present in loot).")

    local currentGodKey = internal.GetGodFromLootsource(lootData.Name)
    local targetTier = 1
    if currentGodKey then
        targetTier = (internal.GetOrRecalcBoonCounts()[currentGodKey] or 0) + 1
    end

    for _, item in ipairs(lootData.UpgradeOptions) do
        local name = item.ItemName or item.Name
        local info = internal.FindTraitInfo(name, nil)

        if info and info.god then
            local rootKey = internal.GetRootKey(info.god)
            if godMeta[rootKey] and godMeta[rootKey].rarityVar then
                local tierKey = rootKey
                if currentGodKey == rootKey and targetTier > 1 then
                    tierKey = rootKey .. tostring(targetTier)
                end

                local banConfig = internal.GetBanConfig(tierKey)
                local isBanned = band(banConfig, info.mask) ~= 0
                if not isBanned then
                    local rarityValue = internal.GetRarityValue(rootKey, info.bit)
                    if rarityValue > 0 then
                        local rarityMap = { [1] = "Common", [2] = "Rare", [3] = "Epic" }
                        local targetRarity = rarityMap[rarityValue]
                        if targetRarity then
                            item.Rarity = targetRarity
                            item.ForceRarity = true
                            Log("[Rarity] Forced %s on %s", targetRarity, name)
                        end
                    end
                end
            end
        end
    end

    local priorityQueue = CurrentRun._banManager_DuoLegendaryQueue
    if not priorityQueue or #priorityQueue == 0 then
        CurrentRun._banManager_DuoLegendaryQueue = nil
        return
    end

    local existingItems = {}
    for i, option in ipairs(lootData.UpgradeOptions) do
        existingItems[option.ItemName] = i
    end

    local maxChoices = GetTotalLootChoices()
    local slotsToEnforce = math.min(#priorityQueue, maxChoices)

    for i = 1, slotsToEnforce do
        local queueItem = priorityQueue[i]
        if not existingItems[queueItem.ItemName] then
            local targetSlot = #lootData.UpgradeOptions
            if targetSlot < maxChoices then
                targetSlot = targetSlot + 1
            end

            local newOption = {
                ItemName = queueItem.ItemName,
                Type = "Trait",
                Rarity = queueItem.rarity,
                ForceRarity = true,
            }
            lootData.UpgradeOptions[targetSlot] = newOption
            existingItems[queueItem.ItemName] = targetSlot

            Log("[Micro] Forced missing item '%s' into Slot %d", queueItem.ItemName, targetSlot)
        end
    end

    lootData.BlockReroll = false
    CurrentRun._banManager_DuoLegendaryQueue = nil
end)

modutil.mod.Path.Wrap("IsTraitEligible", function(base, traitData, args)
    if not IsBanManagerActive() or skipIsTraitEligible then return base(traitData, args) end

    local info = internal.FindTraitInfo(traitData.Name, nil)
    if info then
        if isKeepsakeOffering and info.god == "Hades" and godMeta[info.god].duplicateOf == nil then
            if godInfo["HadesKeepsake"] then
                local cfg = internal.GetBanConfig("HadesKeepsake")
                if band(cfg, info.mask) ~= 0 then return false end
                return base(traitData, args)
            end
        end

        if band(internal.GetBanConfig(info.god), info.mask) ~= 0 then
            Log("[Micro] IsTraitEligible BLOCKED: %s", traitData.Name)
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
