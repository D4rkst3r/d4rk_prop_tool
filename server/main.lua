-- d4rk_prop_tool - server/main.lua

local DATA_FILE = 'data/attachments.json'

-- Datei lesen und an Client zurückschicken
RegisterNetEvent('d4rk_prop_tool:loadAttachments', function()
    local src = source
    local raw = LoadResourceFile(GetCurrentResourceName(), DATA_FILE)
    TriggerClientEvent('d4rk_prop_tool:receiveAttachments', src, raw or '{}')
end)

-- Datei speichern
RegisterNetEvent('d4rk_prop_tool:saveAttachments', function(encoded)
    local src = source
    -- Sicherheitscheck: nur valides JSON akzeptieren
    if type(encoded) ~= 'string' then return end
    local ok = pcall(json.decode, encoded)
    if not ok then
        print('[d4rk_prop_tool] Ungueltige JSON-Daten von ' .. src)
        return
    end
    SaveResourceFile(GetCurrentResourceName(), DATA_FILE, encoded, -1)
end)

-- Export-Datei speichern
RegisterNetEvent('d4rk_prop_tool:saveExport', function(content)
    if type(content) ~= 'string' then return end
    SaveResourceFile(GetCurrentResourceName(), 'output/export.lua', content, -1)
end)