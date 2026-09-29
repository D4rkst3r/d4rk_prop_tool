fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'd4rk_prop_tool'
description 'Prop Attachment & Animation Testing Tool fuer FiveM-Entwickler'
author      'd4rk'
version     '2.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    -- d4rk RP: DarfAkteur, die EINE Rechtefrage des Projekts
    '@d4rk_lib/server/akteur_shared.lua',
    'server/main.lua',
    -- d4rk RP: im Dev-Reiter des Adminpanels anmelden
    'server/panel.lua',
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/script.js',
    'locales/*.json',
}

dependencies {
    'ox_lib',
}
