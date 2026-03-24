fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'd4rk_prop_tool'
description 'Prop Attachment & Animation Testing Tool fuer FiveM-Entwickler'
author      'd4rk'
version     '1.0.0'

client_scripts {
    '@ox_lib/init.lua',
    'client/dataview.lua',
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}

files {
    'data/attachments.json',
}

dependencies {
    'ox_lib',
}