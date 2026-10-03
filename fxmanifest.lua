fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'dice_game'
description 'Two-dice betting game: invite a nearby player, place a bet, roll in a UI'
version '1.0.0'

shared_script 'config.lua'

client_script 'client/main.lua'

server_scripts {
    'server/bridge.lua',
    'server/main.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
}
