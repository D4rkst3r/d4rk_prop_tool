--[[
    d4rk_prop_tool - server/main.lua

    Alle Datei-Schreibvorgaenge laufen ueber diese Datei. Wer sie ausloesen
    darf, haengt an Config.RequireAce - siehe config.lua.

    Unabhaengig davon wird jeder eingehende Eintrag validiert (sanitizeEntry),
    damit kaputte oder praeparierte Daten weder die JSON noch den Lua-Export
    noch die NUI beschaedigen koennen.
--]]

local DATA_FILE     = 'data/attachments.json'
local EXPORT_FILE   = 'output/export.lua'
local MAX_ENTRIES   = 500
local SAVE_COOLDOWN   = 2000   -- ms zwischen Saves pro Spieler
local EXPORT_COOLDOWN = 5000   -- ms zwischen Exports pro Spieler

local saveCooldowns   = {}
local exportCooldowns = {}

local attachmentCache = nil   -- validierte Attachments, im RAM gehalten

-- ─────────────────────────────────────────────
--  Permissions
-- ─────────────────────────────────────────────

local function allowed(src)
    if not Config.RequireAce then return true end
    return IsPlayerAceAllowed(src, Config.AcePermission)
end

local canRead, canWrite = allowed, allowed

local function onCooldown(store, src, ms)
    local now = GetGameTimer()
    if store[src] and (now - store[src]) < ms then return true end
    store[src] = now
    return false
end

-- ─────────────────────────────────────────────
--  Validierung
-- ─────────────────────────────────────────────

local function num(v, fallback)
    v = tonumber(v)
    if not v or v ~= v then return fallback end   -- NaN abfangen
    return v
end

local function str(v, maxLen)
    if type(v) ~= 'string' then return '' end
    if #v > maxLen then return v:sub(1, maxLen) end
    return v
end

--- Nur Zeichen, die in Modell-/Anim-Bezeichnern vorkommen duerfen. Alles
--- andere wird verworfen - diese Strings landen unescaped im Lua-Export
--- (Backtick-Hash) und im NUI.
local function token(v, pattern, maxLen)
    if type(v) ~= 'string' then return '' end
    if #v > maxLen or not v:match(pattern) then return '' end
    return v
end

local function validName(name)
    return type(name) == 'string'
        and #name > 0 and #name <= 64
        and name:match('^[%w_%-]+$') ~= nil
end

--- Baut aus beliebigem Input einen sauberen Eintrag oder gibt nil zurueck.
local function sanitizeEntry(e)
    if type(e) ~= 'table' then return nil end
    local off = type(e.offset)   == 'table' and e.offset   or {}
    local rot = type(e.rotation) == 'table' and e.rotation or {}
    local boneId = num(e.boneId)
    if not boneId then return nil end
    return {
        prop     = token(e.prop, '^[%w_]+$', 64),
        bone     = token(e.bone, '^[%w_]+$', 64),
        boneId   = math.floor(boneId),
        rotOrder = math.floor(num(e.rotOrder, 1)),
        offset   = { x = num(off.x, 0.0), y = num(off.y, 0.0), z = num(off.z, 0.0) },
        rotation = { x = num(rot.x, 0.0), y = num(rot.y, 0.0), z = num(rot.z, 0.0) },
        animDict = token(e.animDict, '^[%w_@%-%.]+$', 128),
        animClip = token(e.animClip, '^[%w_@%-%.]+$', 128),
        notes    = str(e.notes, 256),
    }
end

local function sanitizeAll(data)
    if type(data) ~= 'table' then return nil end
    local out, count = {}, 0
    for name, entry in pairs(data) do
        if validName(name) then
            local clean = sanitizeEntry(entry)
            if clean then
                count = count + 1
                if count > MAX_ENTRIES then break end
                out[name] = clean
            end
        end
    end
    return out
end

-- ─────────────────────────────────────────────
--  Laden / Speichern
-- ─────────────────────────────────────────────

local function loadFromDisk()
    local raw = LoadResourceFile(GetCurrentResourceName(), DATA_FILE)
    if not raw or raw == '' then return {} end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then
        print('^1[d4rk_prop_tool] attachments.json ist ungueltig - starte mit leerer Liste.^7')
        return {}
    end
    return sanitizeAll(decoded) or {}
end

local function getAttachments()
    if not attachmentCache then attachmentCache = loadFromDisk() end
    return attachmentCache
end

local function persist()
    SaveResourceFile(GetCurrentResourceName(), DATA_FILE, json.encode(attachmentCache, { indent = true }), -1)
end

-- ─────────────────────────────────────────────
--  Export
-- ─────────────────────────────────────────────

local function q(s)
    return (string.format('%q', s or ''):gsub('\\\n', '\\n'))
end

local function buildLuaExport(data)
    local lines = {
        '-- d4rk_prop_tool export',
        '-- ' .. os.date('%Y-%m-%d %H:%M:%S'),
        '',
        'local ATTACHMENTS = {',
    }
    local names = {}
    for name in pairs(data) do names[#names + 1] = name end
    table.sort(names)

    for _, name in ipairs(names) do
        local e = data[name]
        lines[#lines + 1] = string.format('    [%s] = {', q(name))
        lines[#lines + 1] = string.format('        prop     = %s,', q(e.prop))
        lines[#lines + 1] = string.format('        bone     = %d,  -- %s', e.boneId, e.bone)
        lines[#lines + 1] = string.format('        offset   = vec3(%.4f, %.4f, %.4f),', e.offset.x, e.offset.y, e.offset.z)
        lines[#lines + 1] = string.format('        rotation = vec3(%.4f, %.4f, %.4f),', e.rotation.x, e.rotation.y, e.rotation.z)
        lines[#lines + 1] = string.format('        rotOrder = %d,', e.rotOrder)
        if e.animDict ~= '' then
            lines[#lines + 1] = string.format('        animDict = %s,', q(e.animDict))
            lines[#lines + 1] = string.format('        animClip = %s,', q(e.animClip))
        end
        if e.notes ~= '' then
            lines[#lines + 1] = '        -- ' .. e.notes:gsub('[\r\n]', ' ')
        end
        lines[#lines + 1] = '    },'
    end

    lines[#lines + 1] = '}'
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'return ATTACHMENTS'
    return table.concat(lines, '\n')
end

local function buildOxItemsExport(data)
    local lines = {
        '-- d4rk_prop_tool export - ox_inventory items',
        '-- ' .. os.date('%Y-%m-%d %H:%M:%S'),
        '-- Einfuegen in ox_inventory/data/items.lua oder per RegisterItems() registrieren.',
        '',
    }
    local names = {}
    for name in pairs(data) do names[#names + 1] = name end
    table.sort(names)

    for _, name in ipairs(names) do
        local e = data[name]
        -- Ohne Modell gibt es kein sinnvolles Item - der Backtick-Hash waere leer.
        if e.prop == '' then goto continue end

        lines[#lines + 1] = string.format('[%s] = {', q(name))
        lines[#lines + 1] = string.format('    label  = %s,', q((name:gsub('_', ' '))))
        lines[#lines + 1] = '    weight = 100,'
        lines[#lines + 1] = '    stack  = true,'
        lines[#lines + 1] = '    close  = true,'
        lines[#lines + 1] = '    client = {'
        if e.animDict ~= '' then
            lines[#lines + 1] = string.format('        anim = { dict = %s, clip = %s, flag = 49 },', q(e.animDict), q(e.animClip))
        end
        lines[#lines + 1] = '        prop = {'
        lines[#lines + 1] = string.format('            model = `%s`,', e.prop)
        lines[#lines + 1] = string.format('            bone  = %d,  -- %s', e.boneId, e.bone)
        lines[#lines + 1] = string.format('            pos   = vec3(%.4f, %.4f, %.4f),', e.offset.x, e.offset.y, e.offset.z)
        lines[#lines + 1] = string.format('            rot   = vec3(%.4f, %.4f, %.4f),', e.rotation.x, e.rotation.y, e.rotation.z)
        lines[#lines + 1] = '        },'
        lines[#lines + 1] = '        usetime = 2500,'
        lines[#lines + 1] = '    },'
        if e.notes ~= '' then
            lines[#lines + 1] = '    -- ' .. e.notes:gsub('[\r\n]', ' ')
        end
        lines[#lines + 1] = '},'

        ::continue::
    end
    return table.concat(lines, '\n')
end

-- ─────────────────────────────────────────────
--  Callbacks
-- ─────────────────────────────────────────────

-- ─────────────────────────────────────────────
--  d4rk RP: Recht anmelden und in den Animationskatalog schreiben
-- ─────────────────────────────────────────────

-- Neues meldet seine Rechte an (d4rk RP CLAUDE.md) - sonst steht der Knoten
-- nicht in der Rechtematrix und niemand kann ihn vergeben.
CreateThread(function()
    if GetResourceState('d4rk_perms') ~= 'started' then return end
    pcall(function()
        exports.d4rk_perms:RechtAnmelden(Config.AcePermission, 'Prop-Tool benutzen', 'animationen')
    end)
end)

-- Die Werte eines Katalogeintrags zurueckschreiben. Das Tool prueft sein
-- eigenes Recht, d4rk_animation prueft danach das KATALOGRECHT selbst.
lib.callback.register('d4rk_prop_tool:katalogSpeichern', function(src, key, plaetze)
    if not canWrite(src) then return { ok = false, grund = 'no_write_access' } end
    if onCooldown(saveCooldowns, src, SAVE_COOLDOWN) then return { ok = false, grund = 'cooldown' } end
    if GetResourceState('d4rk_animation') ~= 'started' then return { ok = false, grund = 'kein_katalog' } end
    local ok, erg = pcall(function() return exports.d4rk_animation:PropSetzen(src, key, plaetze) end)
    if not ok or type(erg) ~= 'table' then return { ok = false, grund = 'kein_katalog' } end
    return erg
end)

lib.callback.register('d4rk_prop_tool:canUse', function(src)
    return canRead(src), canWrite(src)
end)

lib.callback.register('d4rk_prop_tool:getAttachments', function(src)
    if not canRead(src) then return nil end
    return getAttachments()
end)

lib.callback.register('d4rk_prop_tool:saveAttachment', function(src, name, entry)
    if not canWrite(src) then return false, 'no_write_access' end
    if onCooldown(saveCooldowns, src, SAVE_COOLDOWN) then return false, 'cooldown' end
    if not validName(name) then return false, 'invalid_name' end

    local clean = sanitizeEntry(entry)
    if not clean then return false, 'invalid_entry' end

    local all = getAttachments()
    local isNew = all[name] == nil
    if isNew then
        local count = 0
        for _ in pairs(all) do count = count + 1 end
        if count >= MAX_ENTRIES then return false, 'limit_reached' end
    end

    all[name] = clean
    persist()
    return true, nil, all
end)

lib.callback.register('d4rk_prop_tool:deleteAttachment', function(src, name)
    if not canWrite(src) then return false, 'no_write_access' end
    if onCooldown(saveCooldowns, src, SAVE_COOLDOWN) then return false, 'cooldown' end
    if not validName(name) then return false, 'invalid_name' end

    local all = getAttachments()
    if not all[name] then return false, 'not_found' end

    all[name] = nil
    persist()
    return true, nil, all
end)

--- Der Export wird komplett serverseitig aus der Datei gebaut. Der Client
--- schickt nur das gewuenschte Format - nie den Dateiinhalt.
lib.callback.register('d4rk_prop_tool:export', function(src, format)
    if not canWrite(src) then return nil, 'no_write_access' end
    if onCooldown(exportCooldowns, src, EXPORT_COOLDOWN) then return nil, 'cooldown' end

    local all = getAttachments()
    if not next(all) then return nil, 'no_entries' end

    local output = (format == 'ox') and buildOxItemsExport(all) or buildLuaExport(all)
    SaveResourceFile(GetCurrentResourceName(), EXPORT_FILE, output, -1)
    return output
end)

-- ─────────────────────────────────────────────
--  Exports fuer andere Resourcen
-- ─────────────────────────────────────────────

--- Alle gespeicherten Attachments (Kopie).
exports('getAttachments', function()
    local out = {}
    for name, e in pairs(getAttachments()) do
        out[name] = sanitizeEntry(e)
    end
    return out
end)

--- Ein einzelnes Attachment nach Name.
exports('getAttachment', function(name)
    local e = getAttachments()[name]
    return e and sanitizeEntry(e) or nil
end)

-- ─────────────────────────────────────────────
--  Cleanup
-- ─────────────────────────────────────────────

-- Einzeiliger Hinweis beim Start, falls das Tool offen laeuft. Nur damit es
-- nicht unbemerkt auf einem Live-Server landet - gefahrlos zu entfernen.
AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() or Config.RequireAce then return end
    print('^3[d4rk_prop_tool] Offener Modus: jeder Spieler darf Presets speichern und exportieren. Config.RequireAce = true sichert das ab.^7')
end)

AddEventHandler('playerDropped', function()
    local src = source
    saveCooldowns[src]   = nil
    exportCooldowns[src] = nil
end)
