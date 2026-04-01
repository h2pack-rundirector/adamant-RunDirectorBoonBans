local internal = RunDirectorBoonBans_Internal
local godMeta = internal.godMeta
internal.godInfo = internal.godInfo or {}
local godInfo = internal.godInfo
local lib = rom.mods["adamant-ModpackLib"]
local store = internal.store

local band, lshift, rshift, bor, bnot = bit32.band, bit32.lshift, bit32.rshift, bit32.bor, bit32.bnot

local function Log(fmt, ...)
    lib.log(internal.definition.id, store.read("DebugMode") == true, fmt, ...)
end

local function ReadValue(key, specialState)
    if specialState then
        return specialState.get(key)
    end
    return store.read(key)
end

local function WriteValue(key, value, specialState)
    if not specialState then
        error("Boon Bans state writes require specialState", 0)
    end
    specialState.set(key, value)
end

function internal.SetBanConfig(godKey, value, specialState)
    local meta = godMeta[godKey]
    if not meta or not meta.packedConfig then return false end

    local mask = lshift(1, meta.packedConfig.bits) - 1
    local nextValue = band(value or 0, mask)
    local currentValue = ReadValue(meta.packedConfig.var, specialState) or 0
    if currentValue == nextValue then
        return false
    end
    WriteValue(meta.packedConfig.var, nextValue, specialState)
    return true
end

function internal.GetBanConfig(godKey, specialState)
    local meta = godMeta[godKey]
    if not meta or not meta.packedConfig then return 0 end

    local val = ReadValue(meta.packedConfig.var, specialState) or 0
    local mask = lshift(1, meta.packedConfig.bits) - 1
    return band(val, mask)
end

function internal.GetRunState()
    if not CurrentRun then return nil end
    if not CurrentRun.RunDirector_BoonBans_State then
        CurrentRun.RunDirector_BoonBans_State = {
            BoonPickCounts = {},
            ImproveFirstNBoonRarity = store.read("ImproveFirstNBoonRarity") or 0,
        }
    end
    return CurrentRun.RunDirector_BoonBans_State
end

function internal.GetRarityValue(godKey, bitIndex, specialState)
    local meta = godMeta[godKey]
    if not meta or not meta.rarityVar then return 0 end

    local packedVal = ReadValue(meta.rarityVar, specialState) or 0
    local shift = bitIndex * 2
    return band(rshift(packedVal, shift), 3)
end

function internal.SetRarityValue(godKey, bitIndex, newVal, specialState)
    local meta = godMeta[godKey]
    if not meta or not meta.rarityVar then return false end

    local current = ReadValue(meta.rarityVar, specialState) or 0
    local shift = bitIndex * 2
    local clearMask = bnot(lshift(3, shift))
    local cleared = band(current, clearMask)
    local nextValue = bor(cleared, lshift(newVal, shift))
    if nextValue == current then
        return false
    end
    WriteValue(meta.rarityVar, nextValue, specialState)
    return true
end

function internal.ResetAllRarity(specialState)
    local cleared = {}
    local changed = false
    for _, meta in pairs(godMeta) do
        if meta.rarityVar and not cleared[meta.rarityVar] then
            local current = ReadValue(meta.rarityVar, specialState) or 0
            if current ~= 0 then
                WriteValue(meta.rarityVar, 0, specialState)
                changed = true
            end
            cleared[meta.rarityVar] = true
        end
    end
    return changed
end

function internal.UpdateGodStats(godKey, specialState)
    local entry = godInfo[godKey]
    if not entry or not entry.boons then return false end

    local godConfig = internal.GetBanConfig(godKey, specialState)
    local count = 0
    for _, boon in ipairs(entry.boons) do
        if band(godConfig, boon.Mask) ~= 0 then
            count = count + 1
        end
    end

    entry.banned = count
    entry.total = #entry.boons
    entry.banLabel = string.format("(%d/%d Banned)", count, #entry.boons)
    return true
end

function internal.ResetGodBans(god, specialState)
    if godMeta[god] and godInfo[god] then
        local changed = internal.SetBanConfig(god, 0, specialState)
        if not changed then
            return false
        end
        godInfo[god].banned = 0
        Log("[Micro] Reset bans for %s", god)
        return true
    end
    return false
end

function internal.BanAllGodBans(god, specialState)
    local meta = godMeta[god]
    if meta and meta.packedConfig and godInfo[god] then
        local mask = lshift(1, meta.packedConfig.bits) - 1
        local changed = internal.SetBanConfig(god, mask, specialState)
        if not changed then
            return false
        end
        godInfo[god].banned = godInfo[god].total
        Log("[Micro] Banned ALL for %s", god)
        return true
    end
    return false
end

function internal.ResetAllBans(specialState)
    local changed = false
    for god, _ in pairs(godInfo) do
        if internal.ResetGodBans(god, specialState) then
            changed = true
        end
    end
    if changed then
        Log("[Micro] Global Ban Reset triggered.")
    end
    return changed
end

function internal.RecalculateBannedCounts(specialState)
    local changed = false
    for godKey, _ in pairs(godInfo) do
        if internal.UpdateGodStats(godKey, specialState) then
            changed = true
        end
    end
    if changed then
        Log("[Micro] Recalculated all ban counts.")
    end
    return changed
end

local function DeepCompare(a, b)
    if a == b then return true end
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return false end

    for key, value in pairs(a) do
        if not DeepCompare(value, b[key]) then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
end

function internal.ListContainsEquivalent(list, template)
    if type(list) ~= "table" then return false end
    for _, entry in ipairs(list) do
        if DeepCompare(entry, template) then
            return true
        end
    end
    return false
end
