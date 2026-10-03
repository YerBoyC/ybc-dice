local uiOpen = false

local function ui(action, data)
    data = data or {}
    data.action = action
    SendNUIMessage(data)
end

local function setFocus(on)
    uiOpen = on
    SetNuiFocus(on, on)
end

local function feedNotify(msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, true)
end

---------------------------------------------------------------------------
-- Opening the table
---------------------------------------------------------------------------

RegisterCommand(Config.Command, function()
    if uiOpen then return end

    local me = PlayerId()
    local myPos = GetEntityCoords(PlayerPedId())
    local nearby = {}

    for _, player in ipairs(GetActivePlayers()) do
        if player ~= me then
            local ped = GetPlayerPed(player)
            if #(GetEntityCoords(ped) - myPos) <= Config.InviteDistance then
                nearby[#nearby + 1] = GetPlayerServerId(player)
            end
        end
    end

    TriggerServerEvent('dice:server:open', nearby)
end, false)

if Config.Key then
    RegisterKeyMapping(Config.Command, 'Open the dice table', 'keyboard', Config.Key)
end

---------------------------------------------------------------------------
-- Server -> UI
---------------------------------------------------------------------------

local function forward(event, action)
    RegisterNetEvent(event, function(data)
        setFocus(true)
        ui(action, data)
    end)
end

forward('dice:client:open',      'open')
forward('dice:client:waiting',   'waiting')
forward('dice:client:invite',    'invite')
forward('dice:client:start',     'start')
forward('dice:client:cancelled', 'cancelled')

-- These only update a table that is already on screen
RegisterNetEvent('dice:client:rolled',     function(data) ui('rolled', data) end)
RegisterNetEvent('dice:client:soloRolled', function(data) ui('soloRolled', data) end)
RegisterNetEvent('dice:client:tie',    function(data) ui('tie', data) end)
RegisterNetEvent('dice:client:result', function(data) ui('result', data) end)

RegisterNetEvent('dice:client:notify', function(msg, kind)
    if uiOpen then
        ui('toast', { message = msg, kind = kind })
    else
        feedNotify(msg)
    end
end)

---------------------------------------------------------------------------
-- UI -> Server
---------------------------------------------------------------------------

RegisterNUICallback('close', function(_, cb)
    setFocus(false)
    cb({})
end)

RegisterNUICallback('invite', function(data, cb)
    TriggerServerEvent('dice:server:invite', data.target, data.bet)
    cb({})
end)

RegisterNUICallback('respond', function(data, cb)
    TriggerServerEvent('dice:server:respond', data.accept == true)
    cb({})
end)

RegisterNUICallback('solo', function(_, cb)
    TriggerServerEvent('dice:server:solo')
    cb({})
end)

RegisterNUICallback('roll', function(_, cb)
    TriggerServerEvent('dice:server:roll')
    cb({})
end)

RegisterNUICallback('leave', function(_, cb)
    TriggerServerEvent('dice:server:leave')
    cb({})
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and uiOpen then
        SetNuiFocus(false, false)
    end
end)
