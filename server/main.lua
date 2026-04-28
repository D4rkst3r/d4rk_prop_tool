-- d4rk_prop_tool - server/main.lua

local DATA_FILE       = 'data/attachments.json'
local MAX_JSON_SIZE   = 512 * 1024   -- 512 KB
local MAX_EXPORT_SIZE = 256 * 1024   -- 256 KB
local SAVE_COOLDOWN   = 2000         -- ms zwischen Saves pro Spieler
local EXPORT_COOLDOWN = 5000         -- ms zwischen Exports pro Spieler

local saveCooldowns   = {}
local exportCooldowns = {}

-- Datei lesen und an Client zurückschicken
RegisterNetEvent('d4rk_prop_tool:loadAttachments', function()
    local src = source
    local raw = LoadResourceFile(GetCurrentResourceName(), DATA_FILE)
    TriggerClientEvent('d4rk_prop_tool:receiveAttachments', src, raw or '{}')
end)

-- Datei speichern
RegisterNetEvent('d4rk_prop_tool:saveAttachments', function(encoded)
    local src = source
    local now = GetGameTimer()

    if saveCooldowns[src] and (now - saveCooldowns[src]) < SAVE_COOLDOWN then return end
    saveCooldowns[src] = now

    if type(encoded) ~= 'string' then return end
    if #encoded > MAX_JSON_SIZE then
        print(('[d4rk_prop_tool] JSON zu gross von %s (%d bytes)'):format(src, #encoded))
        return
    end
    local ok = pcall(json.decode, encoded)
    if not ok then
        print(('[d4rk_prop_tool] Ungueltige JSON-Daten von %s'):format(src))
        return
    end
    SaveResourceFile(GetCurrentResourceName(), DATA_FILE, encoded, -1)
end)

-- Export-Datei speichern
RegisterNetEvent('d4rk_prop_tool:saveExport', function(content)
    local src = source
    local now = GetGameTimer()

    if exportCooldowns[src] and (now - exportCooldowns[src]) < EXPORT_COOLDOWN then return end
    exportCooldowns[src] = now

    if type(content) ~= 'string' then return end
    if #content > MAX_EXPORT_SIZE then
        print(('[d4rk_prop_tool] Export zu gross von %s (%d bytes)'):format(src, #content))
        return
    end
    SaveResourceFile(GetCurrentResourceName(), 'output/export.lua', content, -1)
end)

-- Cleanup Cooldowns wenn Spieler disconnectet
AddEventHandler('playerDropped', function()
    local src = source
    saveCooldowns[src]   = nil
    exportCooldowns[src] = nil
end)
