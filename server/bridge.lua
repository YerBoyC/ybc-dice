-- All money goes through QBox or QBCore. Both expose the same player-object
-- functions (Functions.AddMoney / RemoveMoney), so only the way we fetch the
-- player differs.

Bridge = {}

local fw = Config.Framework
local QBCore

if fw == 'qb' then
    QBCore = exports['qb-core']:GetCoreObject()
elseif fw ~= 'qbox' then
    error(("[dice_game] Config.Framework must be 'qbox' or 'qb' (got %s)"):format(tostring(fw)))
end

local function getPlayer(src)
    if fw == 'qbox' then
        return exports.qbx_core:GetPlayer(src)
    end
    return QBCore.Functions.GetPlayer(src)
end

function Bridge.GetMoney(src)
    local p = getPlayer(src)
    local m = p and p.PlayerData and p.PlayerData.money
    return m and m[Config.Account] or 0
end

-- Returns true only if the money was actually taken
function Bridge.Remove(src, amount)
    local p = getPlayer(src)
    if not p or Bridge.GetMoney(src) < amount then return false end
    return p.Functions.RemoveMoney(Config.Account, amount, 'dice-bet') == true
end

function Bridge.Add(src, amount, reason)
    local p = getPlayer(src)
    if p then p.Functions.AddMoney(Config.Account, amount, reason or 'dice') end
end

-- Character name shown to the other player
function Bridge.GetDisplayName(src)
    local p = getPlayer(src)
    local ci = p and p.PlayerData and p.PlayerData.charinfo
    if ci and ci.firstname then
        return ('%s %s'):format(ci.firstname, ci.lastname or '')
    end
    return GetPlayerName(src) or ('Player %s'):format(src)
end
