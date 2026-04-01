---@meta _
---@diagnostic disable: lowercase-global

local internal = RunDirectorBoonBans_Internal
local godInfo = internal.godInfo
local lib = rom.mods["adamant-ModpackLib"]
local store = internal.store

local band = bit32.band
local t_insert = table.insert

local function GetRunState()
    return internal.GetRunState()
end

local function IsBanManagerActive()
    return internal.IsBanManagerActive()
end

local function Log(fmt, ...)
    lib.log(internal.definition.id, store.read("DebugMode") == true, fmt, ...)
end

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
    for name, value in pairs(restores) do
        MetaUpgradeData[name].IneligibleForCirceRemoval = value
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

local function wrapNPCChoice(funcName)
    modutil.mod.Path.Wrap(funcName, function(base, source, args, screen)
        if IsBanManagerActive() and args.UpgradeOptions then
            local allowed = {}
            local banned = {}
            local configCache = {}

            for _, option in ipairs(args.UpgradeOptions) do
                if option.GameStateRequirements == nil or IsGameStateEligible(source, option.GameStateRequirements) then
                    local info = internal.FindTraitInfo(option.ItemName, nil)
                    local isBanned = false
                    if info then
                        local cfg = configCache[info.god] or internal.GetBanConfig(info.god)
                        configCache[info.god] = cfg
                        if band(cfg, info.mask) ~= 0 then
                            isBanned = true
                        end
                    end

                    if not isBanned then
                        t_insert(allowed, option)
                    else
                        t_insert(banned, option)
                    end
                end
            end

            if #allowed > 0 and (store.read("EnablePadding") or funcName == "CirceBlessingChoice") then
                if #allowed < GetTotalLootChoices() then
                    local pool = {}
                    for _, bannedOption in ipairs(banned) do
                        t_insert(pool, bannedOption)
                    end
                    local seen = {}
                    for _, allowedOption in ipairs(allowed) do
                        seen[allowedOption.ItemName] = true
                    end

                    while #allowed < GetTotalLootChoices() and #pool > 0 do
                        local idx = math.random(1, #pool)
                        local pick = pool[idx]
                        if pick and not seen[pick.ItemName] then
                            t_insert(allowed, pick)
                            seen[pick.ItemName] = true
                        end
                        pool[idx] = pool[#pool]
                        pool[#pool] = nil
                    end
                end
                args.UpgradeOptions = allowed
            elseif #allowed > 0 then
                args.UpgradeOptions = allowed
            end

            if #banned > 0 then
                Log("[Micro] NPC Choice (%s): Allowed %d, Banned %d", funcName, #allowed, #banned)
            end
        end
        return base(source, args, screen)
    end)
end

modutil.mod.Path.Wrap("GetEligibleSpells", function(base, screen, args)
    local eligible = base(screen, args)
    if not IsBanManagerActive() then return eligible end

    local allowed = {}
    local banned = {}
    local configCache = {}

    for _, spellName in ipairs(eligible) do
        local info = internal.FindTraitInfo(spellName, nil)
        local isBanned = false
        if info then
            local cfg = configCache[info.god] or internal.GetBanConfig(info.god)
            configCache[info.god] = cfg
            if band(cfg, info.mask) ~= 0 then
                isBanned = true
            end
        end

        if not isBanned then
            t_insert(allowed, spellName)
        else
            t_insert(banned, spellName)
        end
    end

    Log("[Micro] GetEligibleSpells: Allowed %d, Banned %d", #allowed, #banned)

    if #allowed == 0 then return eligible end

    if #allowed < GetTotalLootChoices() and store.read("EnablePadding") then
        local pool = { table.unpack(banned) }
        local seen = {}
        for _, allowedSpell in ipairs(allowed) do
            seen[allowedSpell] = true
        end
        while #allowed < GetTotalLootChoices() and #pool > 0 do
            local idx = math.random(1, #pool)
            local pick = pool[idx]
            if pick and not seen[pick] then
                t_insert(allowed, pick)
                seen[pick] = true
            end
            pool[idx] = pool[#pool]
            pool[#pool] = nil
        end
    end
    return allowed
end)

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
        Log("[Micro] AddTraitToHero: Found godKey %s from (trait: %s)", godKey, traitData.Name)
        if not godKey then
            local info = internal.FindTraitInfo(traitData.Name, nil)
            if info then
                godKey = internal.GetRootKey(info.god)
            end
        end
        local traitUpgrade = args.SkipSetup or args.SkipActivatedTraitUpdate or args.SkipNewTraitHighlight

        if godKey and state.BoonPickCounts and not traitUpgrade then
            state.BoonPickCounts[godKey] = (state.BoonPickCounts[godKey] or 0) + 1
            Log("[Micro] AddTraitToHero: %s. God: %s. New Count: %d", traitData.Name, tostring(godKey),
                state.BoonPickCounts[godKey])
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
    local chances = base(loot)
    local state = GetRunState()
    if IsBanManagerActive() and CurrentRun and state.ImproveFirstNBoonRarity > 0 and loot.GodLoot then
        chances.Common, chances.Rare, chances.Epic = 0.0, 0.0, 1.0
    end
    return chances
end)

local npcFunctions = {
    "ArachneCostumeChoice", "NarcissusBenefitChoice", "EchoChoice",
    "MedeaCurseChoice", "CirceBlessingChoice", "IcarusBenefitChoice",
}
for _, func in ipairs(npcFunctions) do
    wrapNPCChoice(func)
end
