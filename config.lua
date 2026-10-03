Config = {}

-- 'qbox' (qbx_core) | 'qb' (qb-core)
-- Every bet, refund and payout goes through this framework.
Config.Framework = 'qbox'

Config.Command  = 'dice'   -- opens the dice table
Config.Key      = nil      -- optional default key, e.g. 'F7' (players can rebind it in Settings)
Config.Currency = '$'

Config.Account = 'cash'    -- money account used for bets: 'cash' or 'bank'

Config.MinBet = 10
Config.MaxBet = 5000

Config.InviteDistance = 5.0   -- metres between the two players
Config.InviteTimeout  = 30    -- seconds the other player has to accept
Config.RollTimeout    = 60    -- seconds both players have to roll before bets are refunded
Config.Cooldown       = 10    -- seconds before a player can start another bet game

Config.HouseCut = 0           -- percent of the pot removed from the winner's payout (0 = none)

-- How long the dice animation plays before the result is decided (ms).
Config.RevealMs = 2600
