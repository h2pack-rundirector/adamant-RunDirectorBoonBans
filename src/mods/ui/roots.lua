local internal = RunDirectorBoonBans_Internal
local godMeta = internal.godMeta
local godInfo = internal.godInfo
local uiData = internal.ui

local band = bit32.band
local bnot = bit32.bnot
local lshift = bit32.lshift

function uiData.BuildRootDescriptors()
    if uiData.rootDescriptors then
        return
    end

    uiData.rootDescriptors = {}
    uiData.rootIdByScopeKey = {}
    uiData.rootsByMainTab = {
        ["Olympians"] = {},
        ["Other Gods"] = {},
        ["Hammers"] = {},
        ["NPCs"] = {},
    }

    for godKey, meta in pairs(godMeta) do
        local isTierDuplicate = type(meta.tier) == "number" and meta.tier > 1
        if not isTierDuplicate then
            local tabName = uiData.TAB_BY_GROUP[meta.uiGroup]
            if tabName then
                local desc = {
                    id = godKey,
                    rootKey = godKey,
                    primaryScopeKey = godKey,
                    group = meta.uiGroup,
                    displayLabel = uiData.GetRootDisplayLabel(godKey, meta),
                    isTiered = meta.maxTiers ~= nil,
                    hasRarity = meta.rarityVar ~= nil,
                    sortIndex = meta.sortIndex or 999,
                    scopes = {},
                    views = {},
                }

                if desc.isTiered then
                    table.insert(desc.scopes, {
                        key = godKey,
                        tier = meta.tier or 1,
                        label = uiData.GetOrdinal(meta.tier or 1),
                    })
                    uiData.rootIdByScopeKey[godKey] = godKey

                    for scopeKey, scopeMeta in pairs(godMeta) do
                        if scopeMeta.duplicateOf == godKey and type(scopeMeta.tier) == "number" then
                            table.insert(desc.scopes, {
                                key = scopeKey,
                                tier = scopeMeta.tier,
                                label = uiData.GetOrdinal(scopeMeta.tier),
                            })
                            uiData.rootIdByScopeKey[scopeKey] = godKey
                        end
                    end

                    table.sort(desc.scopes, function(a, b)
                        if a.tier == b.tier then
                            return a.key < b.key
                        end
                        return a.tier < b.tier
                    end)

                    table.insert(desc.views, {
                        id = uiData.FORCE_VIEW_ID,
                        label = "Force",
                        kind = "force",
                    })
                    for _, scope in ipairs(desc.scopes) do
                        table.insert(desc.views, {
                            id = scope.key,
                            label = scope.label,
                            kind = "bans",
                            scopeKey = scope.key,
                        })
                    end
                    if desc.hasRarity then
                        table.insert(desc.views, {
                            id = uiData.RARITY_VIEW_ID,
                            label = "Rarity",
                            kind = "rarity",
                        })
                        if godKey == "Hera" then
                            table.insert(desc.views, {
                                id = uiData.BRIDAL_GLOW_VIEW_ID,
                                label = "Bridal Glow Target",
                                kind = "bridal_glow",
                            })
                        end
                    end
                else
                    table.insert(desc.scopes, {
                        key = godKey,
                        label = "Bans",
                    })
                    uiData.rootIdByScopeKey[godKey] = godKey
                    if desc.hasRarity then
                        table.insert(desc.views, {
                            id = uiData.DIRECT_BANS_VIEW_ID,
                            label = "Bans",
                            kind = "bans",
                            scopeKey = godKey,
                        })
                        table.insert(desc.views, {
                            id = uiData.RARITY_VIEW_ID,
                            label = "Rarity",
                            kind = "rarity",
                        })
                    end
                end

                uiData.rootDescriptors[godKey] = desc
                table.insert(uiData.rootsByMainTab[tabName], desc)
            end
        end
    end

    for _, list in pairs(uiData.rootsByMainTab) do
        table.sort(list, function(a, b)
            local groupA = uiData.GROUP_ORDER[a.group] or 999
            local groupB = uiData.GROUP_ORDER[b.group] or 999
            if groupA ~= groupB then
                return groupA < groupB
            end
            if a.sortIndex ~= b.sortIndex then
                return a.sortIndex < b.sortIndex
            end
            return a.displayLabel < b.displayLabel
        end)
    end
end

function uiData.GetRootsForTab(tabName)
    uiData.BuildRootDescriptors()
    return uiData.rootsByMainTab[tabName] or uiData.EMPTY_LIST
end

function uiData.GetVisibleRoots(tabName, uiState)
    local allRoots = uiData.GetRootsForTab(tabName)
    local visible = uiData.visibleRootsByMainTab[tabName]
    if not visible then
        visible = {}
        uiData.visibleRootsByMainTab[tabName] = visible
    end
    for i = #visible, 1, -1 do
        visible[i] = nil
    end
    local godPoolFiltering = false
    local godPool = nil

    if tabName == "Olympians" then
        godPoolFiltering, godPool = uiData.IsGodPoolFilteringActive()
    end

    local regionValue = uiData.NPC_REGION_OPTIONS[#uiData.NPC_REGION_OPTIONS].value
    if tabName == "NPCs" and uiState and uiState.view then
        regionValue = uiState.view[uiData.NPC_VIEW_REGION_ALIAS] or regionValue
    end

    for _, root in ipairs(allRoots) do
        local shouldDraw = true
        if tabName == "Olympians" and godPoolFiltering then
            shouldDraw = uiData.IsGodVisibleInGodPool(root.primaryScopeKey, godPool)
        elseif tabName == "NPCs" then
            shouldDraw = uiData.IsRegionMatch(root.group, regionValue)
        end

        if shouldDraw then
            table.insert(visible, root)
        end
    end

    return visible, #allRoots, godPoolFiltering
end

function uiData.GetRootById(rootId)
    uiData.BuildRootDescriptors()
    return uiData.rootDescriptors[rootId]
end

function uiData.InvalidateRootSummaryByScope(scopeKey)
    uiData.BuildRootDescriptors()
    local rootId = uiData.rootIdByScopeKey and uiData.rootIdByScopeKey[scopeKey]
    if not rootId then
        return
    end

    local root = uiData.rootDescriptors and uiData.rootDescriptors[rootId]
    if root then
        root.cachedSummaryLabel = nil
        root.cachedHeaderSummary = nil
        root.cachedChangedTierCount = nil
        root.cachedIsCustomized = nil
        root.cachedSelectorLabel = nil
        root.cachedSelectorEquipped = nil
        root.cachedSelectorSummary = nil
    end
    uiData.cachedCustomizedRootCount = nil
end

function uiData.IsEquippedHammerRoot(root)
    if root.group ~= "Hammers" then
        return false
    end
    local equippedWeapon = uiData.cachedEquippedWeaponName or ""
    return equippedWeapon ~= "" and equippedWeapon:find(root.rootKey, 1, true) ~= nil
end

function uiData.ResetBanFilter(rootId, uiState)
    uiData.banFilterState.rootId = rootId
    if uiState then
        uiState.reset(uiData.BAN_FILTER_TEXT_ALIAS)
        uiState.reset(uiData.BAN_FILTER_MODE_ALIAS)
    end
end

function uiData.SelectRoot(tabName, rootId, uiState)
    if uiData.selectedRootByMainTab[tabName] ~= rootId then
        uiData.selectedRootByMainTab[tabName] = rootId
        uiData.ResetBanFilter(rootId, uiState)
    end
end

function uiData.EnsureSelectedRoot(tabName, visibleRoots, uiState)
    local currentId = uiData.selectedRootByMainTab[tabName]
    for _, root in ipairs(visibleRoots) do
        if root.id == currentId then
            return root
        end
    end

    local fallback = nil
    if tabName == "Hammers" then
        for _, root in ipairs(visibleRoots) do
            if uiData.IsEquippedHammerRoot(root) then
                fallback = root
                break
            end
        end
    end
    if not fallback then
        fallback = visibleRoots[1]
    end
    if fallback then
        uiData.SelectRoot(tabName, fallback.id, uiState)
        return fallback
    end

    uiData.selectedRootByMainTab[tabName] = nil
    return nil
end

function uiData.EnsureBanFilterRoot(root, uiState)
    if uiData.banFilterState.rootId ~= root.id then
        uiData.ResetBanFilter(root.id, uiState)
    end
end

function uiData.GetScopeSummary(scopeKey, uiState)
    local entry = godInfo[scopeKey]
    if entry and type(entry.banned) == "number" and type(entry.total) == "number" then
        return entry.banned, entry.total
    end

    local total = 0
    local banned = 0
    local currentBans = internal.GetBanConfig(scopeKey, uiState)
    for _, boon in ipairs(uiData.GetScopeBoons(scopeKey)) do
        total = total + 1
        if band(currentBans, boon.Mask) ~= 0 then
            banned = banned + 1
        end
    end
    return banned, total
end

function uiData.GetChangedTierCount(root, uiState)
    if root.cachedChangedTierCount then
        return root.cachedChangedTierCount[1], root.cachedChangedTierCount[2]
    end

    local changed = 0
    local total = #root.scopes
    for _, scope in ipairs(root.scopes) do
        local scopeBanned = uiData.GetScopeSummary(scope.key, uiState)
        if scopeBanned > 0 then
            changed = changed + 1
        end
    end
    root.cachedChangedTierCount = { changed, total }
    return changed, total
end

function uiData.GetRootSummaryLabel(root, uiState)
    if root.cachedSummaryLabel then
        return root.cachedSummaryLabel
    end

    if root.isTiered then
        local changed, total = uiData.GetChangedTierCount(root, uiState)
        root.cachedSummaryLabel = string.format("(%d/%d tiers changed)", changed, total)
        return root.cachedSummaryLabel
    end

    local entry = godInfo[root.primaryScopeKey]
    if entry and entry.banLabel then
        root.cachedSummaryLabel = entry.banLabel
        return root.cachedSummaryLabel
    end

    local banned, total = uiData.GetScopeSummary(root.primaryScopeKey, uiState)
    root.cachedSummaryLabel = uiData.FormatCountLabel(banned, total)
    return root.cachedSummaryLabel
end

function uiData.GetSelectorLabel(root, uiState)
    local summary = uiData.GetRootSummaryLabel(root, uiState)
    local isEquipped = uiData.IsEquippedHammerRoot(root)

    if root.cachedSelectorLabel
        and root.cachedSelectorEquipped == isEquipped
        and root.cachedSelectorSummary == summary then
        return root.cachedSelectorLabel
    end

    local label = root.displayLabel
    if isEquipped then
        label = label .. " (Equipped)"
    end
    root.cachedSelectorEquipped = isEquipped
    root.cachedSelectorSummary = summary
    root.cachedSelectorLabel = label .. " " .. summary
    return root.cachedSelectorLabel
end

function uiData.GetRootHeaderSummary(root, uiState)
    if not root.isTiered then
        return nil
    end
    if root.cachedHeaderSummary then
        return root.cachedHeaderSummary
    end

    local parts = {}
    for _, scope in ipairs(root.scopes) do
        local banned, total = uiData.GetScopeSummary(scope.key, uiState)
        table.insert(parts, string.format("%s:%d/%d", scope.label, banned, total))
    end
    root.cachedHeaderSummary = table.concat(parts, "   ")
    return root.cachedHeaderSummary
end

function uiData.GetCustomizedRootCount(uiState)
    if uiData.cachedCustomizedRootCount ~= nil then
        return uiData.cachedCustomizedRootCount
    end

    local count = 0
    uiData.BuildRootDescriptors()

    for _, root in pairs(uiData.rootDescriptors or uiData.EMPTY_LIST) do
        if root.cachedIsCustomized == nil then
            root.cachedIsCustomized = false
            for _, scope in ipairs(root.scopes) do
                local banned = uiData.GetScopeSummary(scope.key, uiState)
                if banned > 0 then
                    root.cachedIsCustomized = true
                    break
                end
            end
        end
        if root.cachedIsCustomized then
            count = count + 1
        end
    end

    uiData.cachedCustomizedRootCount = count
    return count
end

function uiData.ApplyForceOne(scopeKey, boonKey, uiState)
    local boon = uiData.FindBoonByKey(scopeKey, boonKey)
    local meta = uiData.GetRootMeta(scopeKey)
    if not boon or not meta or not meta.packedConfig then
        return false
    end

    local fullMask = lshift(1, meta.packedConfig.bits) - 1
    local nextMask = band(fullMask, bnot(boon.Mask))
    local changed = internal.SetBanConfig(scopeKey, nextMask, uiState)
    if changed then
        internal.UpdateGodStats(scopeKey, uiState)
    end
    return changed
end
