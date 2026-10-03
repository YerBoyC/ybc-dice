# YBC DICE

Roll two dice in a UI. Play alone for fun, or invite a nearby player and bet.

- **Solo:** no opponent, no bet, no money involved.
- **Two players:** each rolls two dice, the higher total takes the pot, ties roll again.

All money (bets, refunds, payouts) goes through **QBox** (`qbx_core`) or **QBCore** (`qb-core`).

## Install

1. Drop the `ybc-dice` folder into your `resources` folder.
2. Add `ensure ybc-dice` to `server.cfg`, after your core resource.
3. In `config.lua` set `Config.Framework` to `'qbox'` or `'qb'`, and `Config.Account` to `'cash'` or `'bank'`.
4. OneSync must be on (the server checks how far apart the players are).

## How to play

Type `/dice`.

**Alone, or nobody nearby:** the table opens straight to a solo roll. Press **Roll again** as often as you like. Nothing is charged.

**With someone:** stand within `Config.InviteDistance` of them, type `/dice`, then either:
- press **Roll solo** to throw on your own, or
- pick the player, set a bet and press **Send invite**.

They have `Config.InviteTimeout` seconds to accept. On accept both stakes are taken up front, each player presses **Roll dice**, and the winner is paid the pot (minus `Config.HouseCut` percent, 0 by default).

## What the server enforces

- Every roll is made on the server, solo and bet games alike.
- Bet limits, distance, cooldown, funds and "already busy" checks all run server-side.
- Closing the table before anyone has rolled refunds both players.
- Leaving or disconnecting after a roll forfeits the pot to the opponent.
- If nobody finishes rolling within `Config.RollTimeout`, both bets are refunded.
- Restarting the resource mid-game refunds active bets.

## Money integration

`server/bridge.lua` is the only file that touches money. It fetches the player with `exports.qbx_core:GetPlayer` (QBox) or `QBCore.Functions.GetPlayer` (QBCore) and then uses `PlayerData.money`, `Functions.RemoveMoney` and `Functions.AddMoney`. Character names come from `PlayerData.charinfo`.
