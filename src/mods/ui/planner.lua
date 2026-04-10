local internal = RunDirectorBoonBans_Internal
local uiData = internal.ui

local band = bit32.band

function uiData.BuildBanListGeometry(scopeKey, currentBans, uiState)
    return lib.buildIndexedHiddenSlotGeometry(uiData.GetBanRows(scopeKey), "item:", {
        isHidden = function(row)
            local boon = row and row.boon or nil
            local isBanned = boon and band(currentBans or 0, boon.Mask) ~= 0 or false
            return not (boon and uiData.DoesBoonPassBanFilter(boon, isBanned, uiState))
        end,
        line = function(_, _, visibleIndex, hidden)
            if hidden then
                return nil
            end
            return visibleIndex
        end,
    })
end

function uiData.GetBanListGeometry(scopeKey, currentBans, uiState)
    local signature = table.concat({
        tostring(scopeKey or ""),
        tostring(uiData.GetBanFilterMode(uiState)),
        tostring(currentBans or 0),
        tostring(uiData.GetBanFilterTextLower(uiState)),
    }, "|")

    local cached = uiData.banPanelLayoutsByScope[scopeKey]
    if cached and cached.signature == signature then
        return cached.runtimeGeometry, cached.visibleCount
    end

    local runtimeGeometry, visibleCount = uiData.BuildBanListGeometry(scopeKey, currentBans, uiState)
    uiData.banPanelLayoutsByScope[scopeKey] = {
        signature = signature,
        runtimeGeometry = runtimeGeometry,
        visibleCount = visibleCount,
    }
    return runtimeGeometry, visibleCount
end
