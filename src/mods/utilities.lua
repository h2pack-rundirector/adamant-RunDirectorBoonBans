local internal = RunDirectorBoonBans_Internal
local godMeta = internal.godMeta

local band, lshift, rshift, bor, bnot = bit32.band, bit32.lshift, bit32.rshift, bit32.bor, bit32.bnot

function internal.SetBanConfig(godKey, value)
    local meta = godMeta[godKey]
    if not meta or not meta.packedConfig then return end

    local mask = lshift(1, meta.packedConfig.bits) - 1
    config[meta.packedConfig.var] = band(value or 0, mask)
end

function internal.GetBanConfig(godKey)
    local meta = godMeta[godKey]
    if not meta or not meta.packedConfig then return 0 end

    local val = config[meta.packedConfig.var] or 0
    local mask = lshift(1, meta.packedConfig.bits) - 1
    return band(val, mask)
end

function internal.GetRunState()
    if not CurrentRun then return nil end
    if not CurrentRun.RunDirector_BoonBans_State then
        CurrentRun.RunDirector_BoonBans_State = {
            BoonPickCounts = {},
            ImproveFirstNBoonRarity = config.ImproveFirstNBoonRarity or 0,
        }
    end
    return CurrentRun.RunDirector_BoonBans_State
end

function internal.GetRarityValue(godKey, bitIndex)
    local meta = godMeta[godKey]
    if not meta or not meta.rarityVar then return 0 end

    local packedVal = config[meta.rarityVar] or 0
    local shift = bitIndex * 2
    return band(rshift(packedVal, shift), 3)
end

function internal.SetRarityValue(godKey, bitIndex, newVal)
    local meta = godMeta[godKey]
    if not meta or not meta.rarityVar then return end

    local current = config[meta.rarityVar] or 0
    local shift = bitIndex * 2
    local clearMask = bnot(lshift(3, shift))
    local cleared = band(current, clearMask)
    config[meta.rarityVar] = bor(cleared, lshift(newVal, shift))
end

function internal.ResetAllRarity()
    local cleared = {}
    for _, meta in pairs(godMeta) do
        if meta.rarityVar and not cleared[meta.rarityVar] then
            config[meta.rarityVar] = 0
            cleared[meta.rarityVar] = true
        end
    end
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
