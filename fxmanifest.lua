fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'd4rk_prop_tool'
description 'Prop Attachment & Animation Testing Tool fuer FiveM-Entwickler'
author      'd4rk'
version     '2.0.0'

shared_scripts {
    'config.lua',
}

client_scripts {
    '@ox_lib/init.lua',
    'client/dataview.lua',
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/script.js',
    'data/attachments.json',
}

dependencies {
    'ox_lib',
}