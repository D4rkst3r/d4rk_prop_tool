--[[
    d4rk RP - Anmeldung beim Adminpanel (Dev-Reiter).

    Keine Fachlogik. Dieselbe Schnittstelle wie d4rk_world/server/panel.lua:
    das Panel fuehrt den Befehl auf dem Client aus, als haette man ihn
    getippt. Das Recht prueft der Befehl selbst (canUse im Server).

    KEINE HARTE ABHAENGIGKEIT auf d4rk_admin - steht es nicht bereit, faellt
    diese Datei still aus und das Tool laeuft weiter.
]]

local WERKZEUGE = {
    { key = Config.Command, label = 'Prop-Tool', gruppe = 'Animationen', icon = 'package-open',
      beschreibung = 'Props an Knochen haengen und ausrichten. Katalogeintraege oeffnet "Im Prop-Tool einstellen" im Animationsmenue.',
      permission = Config.AcePermission },
}

---@param aufNachfrage boolean? true, wenn d4rk_admin selbst gefragt hat
local function anmelden(aufNachfrage)
    -- Auf die Nachfrage hin steht d4rk_admin noch auf 'starting' (gemessen
    -- 28.08.2026, siehe d4rk_world/server/panel.lua) - dann nicht pruefen.
    if not aufNachfrage and GetResourceState('d4rk_admin') ~= 'started' then return end

    local ok, fehler = pcall(function()
        for i = 1, #WERKZEUGE do
            exports.d4rk_admin:registerTool(WERKZEUGE[i])
        end
    end)

    if not ok then
        lib.print.warn(('d4rk_prop_tool: Anmeldung beim Adminpanel gescheitert: %s'):format(tostring(fehler)))
        return
    end

    lib.print.info(('d4rk_prop_tool: %d Werkzeug(e) beim Adminpanel angemeldet.'):format(#WERKZEUGE))
end

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    anmelden()
end)

-- Nach einem Neustart von d4rk_admin ist dessen Liste leer; es fragt nach.
-- Nicht die Funktion direkt haengen: das erste Ereignisargument kaeme als
-- aufNachfrage an.
AddEventHandler('d4rk_admin:werkzeugeAnmelden', function()
    anmelden(true)
end)
