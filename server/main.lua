-- All rolls, bets and payouts are decided here. The client only sends intents.
-- Money only moves in two-player bet games; solo rolls never touch it.

local invites   = {}  -- [targetSrc]  = { from = src, bet = n }
local outgoing  = {}  -- [fromSrc]    = targetSrc
local sessions  = {}  -- [sessionId]  = session
local inGame    = {}  -- [src]        = sessionId
local cooldowns = {}  -- [src]        = os.time() after which a new game is allowed
local nextId    = 0

math.randomseed(os.time() + GetGameTimer())

local function isOnline(src)
    return src ~= nil and GetPlayerName(src) ~= nil
end

local function notify(src, msg, kind)
    if isOnline(src) then
        TriggerClientEvent('dice:client:notify', src, msg, kind or 'info')
    end
end

local function cancelled(src, msg)
    if isOnline(src) then
        TriggerClientEvent('dice:client:cancelled', src, { message = msg, balance = Bridge.GetMoney(src) })
    end
end

local function distance(a, b)
    local pa, pb = GetPlayerPed(a), GetPlayerPed(b)
    if pa == 0 or pb == 0 then return math.huge end
    return #(GetEntityCoords(pa) - GetEntityCoords(pb))
end

local function busy(src)
    return inGame[src] ~= nil or invites[src] ~= nil or outgoing[src] ~= nil
end

local function clearInvite(target)
    local inv = invites[target]
    if inv then
        outgoing[inv.from] = nil
        invites[target] = nil
    end
    return inv
end

local function otherPlayer(s, src)
    return s.players[1] == src and s.players[2] or s.players[1]
end

local function money(n)
    return ('%s%s'):format(Config.Currency, n)
end

---------------------------------------------------------------------------
-- Sessions
---------------------------------------------------------------------------

local function endSession(s)
    sessions[s.id] = nil
    for _, p in ipairs(s.players) do
        inGame[p] = nil
        cooldowns[p] = os.time() + Config.Cooldown
    end
end

local function refundAll(s, msg)
    for _, p in ipairs(s.players) do
        if isOnline(p) then Bridge.Add(p, s.bet, 'dice-refund') end
    end
    for _, p in ipairs(s.players) do cancelled(p, msg) end
    endSession(s)
end

local function payout(s, winner)
    local pot = s.bet * 2
    local cut = math.floor(pot * Config.HouseCut / 100)
    local win = pot - cut
    Bridge.Add(winner, win, 'dice-win')
    return win
end

local function armTimeout(s)
    s.token = (s.token or 0) + 1
    local token = s.token
    SetTimeout(Config.RollTimeout * 1000, function()
        if sessions[s.id] and s.token == token and not s.resolving then
            refundAll(s, 'Nobody finished rolling in time. Both bets were refunded.')
        end
    end)
end

local function resolve(s)
    if not sessions[s.id] then return end -- ended while the dice were animating

    local a, b = s.players[1], s.players[2]
    local ta = s.rolls[a][1] + s.rolls[a][2]
    local tb = s.rolls[b][1] + s.rolls[b][2]

    if ta == tb then
        s.rolls = {}
        s.round = s.round + 1
        s.resolving = false
        for _, p in ipairs(s.players) do
            TriggerClientEvent('dice:client:tie', p, { round = s.round })
        end
        armTimeout(s)
        return
    end

    local winner, loser = a, b
    if tb > ta then winner, loser = b, a end

    local win = payout(s, winner)
    TriggerClientEvent('dice:client:result', winner, {
        won = true, amount = win, net = win - s.bet, balance = Bridge.GetMoney(winner),
    })
    TriggerClientEvent('dice:client:result', loser, {
        won = false, amount = s.bet, balance = Bridge.GetMoney(loser),
    })
    endSession(s)
end

local function forfeit(s, leaver, reason)
    local winner = otherPlayer(s, leaver)
    if isOnline(winner) then
        local win = payout(s, winner)
        cancelled(winner, ('%s'):format(reason:format(money(win))))
    end
    endSession(s)
end

---------------------------------------------------------------------------
-- Opening the table
---------------------------------------------------------------------------

RegisterNetEvent('dice:server:open', function(ids)
    local src = source
    if inGame[src] then return notify(src, 'You are already at a table.', 'error') end

    local players = {}
    if type(ids) == 'table' then
        for i = 1, math.min(#ids, 32) do
            local id = tonumber(ids[i])
            if id and id ~= src and isOnline(id) and not busy(id)
                and distance(src, id) <= Config.InviteDistance + 1.0 then
                players[#players + 1] = { id = id, name = Bridge.GetDisplayName(id) }
            end
        end
    end

    TriggerClientEvent('dice:client:open', src, {
        players  = players,
        balance  = Bridge.GetMoney(src),
        min      = Config.MinBet,
        max      = Config.MaxBet,
        currency = Config.Currency,
        distance = Config.InviteDistance,
        command  = Config.Command,
        revealMs = Config.RevealMs,
    })
end)

---------------------------------------------------------------------------
-- Invites
---------------------------------------------------------------------------

RegisterNetEvent('dice:server:invite', function(target, bet)
    local src = source
    target, bet = tonumber(target), tonumber(bet)

    if not target or not bet or bet % 1 ~= 0 then
        return notify(src, 'Enter a whole-number bet.', 'error')
    end
    if bet < Config.MinBet or bet > Config.MaxBet then
        return notify(src, ('Bets must be between %s and %s.'):format(money(Config.MinBet), money(Config.MaxBet)), 'error')
    end
    if target == src or not isOnline(target) then
        return notify(src, 'That player is not available.', 'error')
    end
    if (cooldowns[src] or 0) > os.time() then
        return notify(src, 'Give it a few seconds before starting another game.', 'error')
    end
    if busy(src) then
        return notify(src, 'You already have a game or invite open.', 'error')
    end
    if busy(target) then
        return notify(src, 'That player is busy right now.', 'error')
    end
    if distance(src, target) > Config.InviteDistance then
        return notify(src, 'That player is too far away.', 'error')
    end
    if Bridge.GetMoney(src) < bet then
        return notify(src, ('You do not have %s to bet.'):format(money(bet)), 'error')
    end

    local inv = { from = src, bet = bet }
    invites[target] = inv
    outgoing[src] = target

    TriggerClientEvent('dice:client:invite', target, {
        from = src, name = Bridge.GetDisplayName(src), bet = bet,
        timeout = Config.InviteTimeout, currency = Config.Currency,
        balance = Bridge.GetMoney(target),
    })
    TriggerClientEvent('dice:client:waiting', src, {
        name = Bridge.GetDisplayName(target), bet = bet, currency = Config.Currency,
    })

    SetTimeout(Config.InviteTimeout * 1000, function()
        if invites[target] == inv then
            clearInvite(target)
            cancelled(src, 'The invite expired.')
            cancelled(target, 'The invite expired.')
        end
    end)
end)

RegisterNetEvent('dice:server:respond', function(accept)
    local src = source
    local inv = clearInvite(src)
    if not inv then return end

    local from = inv.from

    if accept ~= true then
        return cancelled(from, ('%s declined the invite.'):format(Bridge.GetDisplayName(src)))
    end

    if not isOnline(from) or inGame[from] or inGame[src] then
        return cancelled(src, 'That game is no longer available.')
    end
    if distance(from, src) > Config.InviteDistance + 1.0 then
        cancelled(from, 'The other player moved too far away.')
        return cancelled(src, 'The other player moved too far away.')
    end

    -- Take both stakes. If either fails, undo and cancel.
    if not Bridge.Remove(from, inv.bet) then
        cancelled(from, ('You no longer have %s to bet.'):format(money(inv.bet)))
        return cancelled(src, 'The other player could not cover the bet.')
    end
    if not Bridge.Remove(src, inv.bet) then
        Bridge.Add(from, inv.bet, 'dice-refund')
        cancelled(src, ('You do not have %s to bet.'):format(money(inv.bet)))
        return cancelled(from, 'The other player could not cover the bet.')
    end

    nextId = nextId + 1
    local s = {
        id = nextId, players = { from, src }, bet = inv.bet,
        rolls = {}, round = 1, resolving = false,
    }
    sessions[s.id] = s
    inGame[from], inGame[src] = s.id, s.id

    for _, p in ipairs(s.players) do
        TriggerClientEvent('dice:client:start', p, {
            opponent = Bridge.GetDisplayName(otherPlayer(s, p)),
            bet = s.bet,
            pot = s.bet * 2,
            balance = Bridge.GetMoney(p),
            revealMs = Config.RevealMs,
            currency = Config.Currency,
        })
    end
    armTimeout(s)
end)

---------------------------------------------------------------------------
-- Rolling
---------------------------------------------------------------------------

RegisterNetEvent('dice:server:roll', function()
    local src = source
    local s = sessions[inGame[src] or -1]
    if not s or s.resolving or s.rolls[src] then return end

    local d1, d2 = math.random(1, 6), math.random(1, 6)
    s.rolls[src] = { d1, d2 }

    for _, p in ipairs(s.players) do
        TriggerClientEvent('dice:client:rolled', p, { mine = (p == src), dice = { d1, d2 } })
    end

    if s.rolls[s.players[1]] and s.rolls[s.players[2]] then
        s.resolving = true
        SetTimeout(Config.RevealMs, function() resolve(s) end)
    end
end)

---------------------------------------------------------------------------
-- Solo rolls: just throw the dice. No bet, no money, no opponent.
---------------------------------------------------------------------------

local lastSolo = {}

RegisterNetEvent('dice:server:solo', function()
    local src = source
    if inGame[src] then return end

    -- One throw at a time: wait for the animation to finish
    local now = GetGameTimer()
    if (lastSolo[src] or 0) + Config.RevealMs > now then return end
    lastSolo[src] = now

    TriggerClientEvent('dice:client:soloRolled', src, {
        dice = { math.random(1, 6), math.random(1, 6) },
    })
end)

---------------------------------------------------------------------------
-- Leaving / disconnects
---------------------------------------------------------------------------

RegisterNetEvent('dice:server:leave', function()
    local src = source

    -- Withdraw an invite we sent
    local target = outgoing[src]
    if target then
        clearInvite(target)
        cancelled(target, 'The invite was withdrawn.')
        return
    end

    local s = sessions[inGame[src] or -1]
    if not s or s.resolving then return end

    if next(s.rolls) == nil then
        -- Nobody has rolled yet: clean cancel, refund both
        local other = otherPlayer(s, src)
        refundAll(s, 'The game was cancelled. Both bets were refunded.')
        notify(other, 'The other player left the table.', 'info')
    else
        forfeit(s, src, 'The other player left. You won %s.')
        notify(src, 'You left the table and forfeited the pot.', 'error')
    end
end)

AddEventHandler('playerDropped', function()
    local src = source

    local inv = clearInvite(src)
    if inv then cancelled(inv.from, 'That player left the server.') end

    local target = outgoing[src]
    if target then
        clearInvite(target)
        cancelled(target, 'The invite was withdrawn.')
    end

    local s = sessions[inGame[src] or -1]
    if s then
        -- Disconnecting mid-game forfeits the pot to the opponent
        forfeit(s, src, 'The other player disconnected. You won %s.')
    end

    cooldowns[src] = nil
    lastSolo[src] = nil
end)

-- Don't swallow bets if the resource restarts mid-game
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, s in pairs(sessions) do
        for _, p in ipairs(s.players) do
            if isOnline(p) then Bridge.Add(p, s.bet, 'dice-refund') end
        end
    end
end)
