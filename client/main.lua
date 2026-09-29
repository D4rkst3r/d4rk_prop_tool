--[[
    d4rk_prop_tool - client/main.lua  v2.1
    Prop Attachment & Animation Testing Tool
    Abhaengigkeiten: ox_lib, config.lua
--]]

lib.locale(Config.Locale or 'en')

local RESOURCE_VERSION = '2.1.0'

-- ─────────────────────────────────────────────
--  State
-- ─────────────────────────────────────────────

local uiOpen   = false
local canRead  = false
local canWrite = false

local boneById = {}
for _, b in ipairs(Config.Bones) do boneById[b.id] = b.name end

local function boneName(id)
    return boneById[id] or ('BONE_' .. tostring(id))
end

local props = {
    [1] = { entity = nil, model = '', boneId = Config.DefaultBoneSlot1, bone = boneName(Config.DefaultBoneSlot1),
            rotOrder = 1, offset = { x = 0.0, y = 0.0, z = 0.0 }, rotation = { x = 0.0, y = 0.0, z = 0.0 } },
    [2] = { entity = nil, model = '', boneId = Config.DefaultBoneSlot2, bone = boneName(Config.DefaultBoneSlot2),
            rotOrder = 1, offset = { x = 0.0, y = 0.0, z = 0.0 }, rotation = { x = 0.0, y = 0.0, z = 0.0 } },
}

local history    = { {}, {} }
local historyIdx = { 0, 0 }
local MAX_HISTORY = 100

local currentAnim = nil
local moveSpeed   = Config.DefaultMoveSpeed   or 0.01
local rotateSpeed = Config.DefaultRotateSpeed or 1.0

local cam = nil
local DEFAULT_CAM = { dist = 2.5, angle = 0.0, height = 0.5, focus = 'ped' }
local camData = { dist = DEFAULT_CAM.dist, angle = DEFAULT_CAM.angle, height = DEFAULT_CAM.height, focus = DEFAULT_CAM.focus }

local attachments = {}

local function notify(msg, kind)
    lib.notify({ title = locale('title'), description = msg, type = kind or 'inform', duration = 3000 })
end

local function toast(msg, style)
    SendNUIMessage({ type = 'toast', msg = msg, style = style or 'info' })
end

-- ─────────────────────────────────────────────
--  Helpers
-- ─────────────────────────────────────────────

local function requestModel(modelName)
    if type(modelName) ~= 'string' or not modelName:match('^[%w_]+$') then return nil end
    local model = joaat(modelName)
    if not IsModelValid(model) then return nil end
    RequestModel(model)
    local t = 0
    while not HasModelLoaded(model) do
        Wait(10); t = t + 10
        if t > 5000 then return nil end
    end
    return model
end

local function requestAnimDict(dict)
    if type(dict) ~= 'string' or not DoesAnimDictExist(dict) then return false end
    RequestAnimDict(dict)
    local t = 0
    while not HasAnimDictLoaded(dict) do
        Wait(10); t = t + 10
        if t > 5000 then return false end
    end
    return true
end

local function attachProp(slot)
    local p = props[slot]
    if not p.entity or not DoesEntityExist(p.entity) then return end
    local ped = cache.ped
    AttachEntityToEntity(
        p.entity, ped,
        GetPedBoneIndex(ped, p.boneId),
        p.offset.x, p.offset.y, p.offset.z,
        p.rotation.x, p.rotation.y, p.rotation.z,
        true, true, false, true, p.rotOrder, true
    )
end

local function spawnPropEntity(slot, model)
    local mdl = requestModel(model)
    if not mdl then return false end
    local ped    = cache.ped
    local coords = GetEntityCoords(ped)
    local ent    = CreateObject(mdl, coords.x, coords.y, coords.z, false, false, false)
    SetEntityCollision(ent, false, false)
    SetEntityNoCollisionEntity(ent, ped, true)
    SetEntityAsMissionEntity(ent, true, true)
    SetModelAsNoLongerNeeded(mdl)
    props[slot].entity = ent
    props[slot].model  = model
    attachProp(slot)
    return true
end

local function deleteProp(slot)
    local p = props[slot]
    if p.entity and DoesEntityExist(p.entity) then
        DeleteEntity(p.entity)
    end
    p.entity = nil
    p.model  = ''
end

local function stopAnim()
    if currentAnim then
        StopAnimTask(cache.ped, currentAnim.dict, currentAnim.clip, 1.0)
        currentAnim = nil
    end
end

local function hasProp(slot)
    local p = props[slot]
    return p.entity ~= nil and DoesEntityExist(p.entity)
end

--- Schickt Bone / RotOrder / Modell eines Slots an die NUI, damit die
--- Dropdowns nach Undo, Preset-Load oder Reset nicht auseinanderlaufen.
local function syncSlot(slot)
    local p = props[slot]
    SendNUIMessage({
        type     = 'syncSlot',
        slot     = slot,
        boneId   = p.boneId,
        rotOrder = p.rotOrder,
        model    = p.model,
    })
end

local function syncCamera()
    SendNUIMessage({
        type   = 'syncCamera',
        dist   = camData.dist,
        angle  = camData.angle,
        height = camData.height,
        focus  = camData.focus,
    })
end

local function syncSpeeds()
    SendNUIMessage({ type = 'syncSpeeds', moveSpeed = moveSpeed, rotateSpeed = rotateSpeed })
end

-- ─────────────────────────────────────────────
--  Undo / Redo
-- ─────────────────────────────────────────────

local function snapshot(p)
    return {
        model    = p.model,
        boneId   = p.boneId,
        bone     = p.bone,
        rotOrder = p.rotOrder,
        offset   = { x = p.offset.x,   y = p.offset.y,   z = p.offset.z },
        rotation = { x = p.rotation.x, y = p.rotation.y, z = p.rotation.z },
    }
end

local function pushHistory(slot)
    local h = history[slot]
    while #h > historyIdx[slot] do table.remove(h) end
    historyIdx[slot] = historyIdx[slot] + 1
    h[historyIdx[slot]] = snapshot(props[slot])
    if #h > MAX_HISTORY then
        table.remove(h, 1)
        historyIdx[slot] = historyIdx[slot] - 1
    end
end

local function applyHistoryState(slot)
    local p     = props[slot]
    local state = history[slot][historyIdx[slot]]
    if not state then return end
    p.offset   = { x = state.offset.x,   y = state.offset.y,   z = state.offset.z }
    p.rotation = { x = state.rotation.x, y = state.rotation.y, z = state.rotation.z }
    p.boneId   = state.boneId
    p.bone     = state.bone
    p.rotOrder = state.rotOrder
    attachProp(slot)
    syncSlot(slot)
end

local function undoSlot(slot)
    if historyIdx[slot] <= 1 then
        toast(locale('nothing_to_undo'), 'info')
        return
    end
    historyIdx[slot] = historyIdx[slot] - 1
    applyHistoryState(slot)
end

local function redoSlot(slot)
    if historyIdx[slot] >= #history[slot] then
        toast(locale('nothing_to_redo'), 'info')
        return
    end
    historyIdx[slot] = historyIdx[slot] + 1
    applyHistoryState(slot)
end

local function clearHistory(slot)
    history[slot]    = {}
    historyIdx[slot] = 0
end

-- ─────────────────────────────────────────────
--  Camera
-- ─────────────────────────────────────────────

local function getCamTarget()
    if camData.focus == 'prop1' and hasProp(1) then return props[1].entity end
    if camData.focus == 'prop2' and hasProp(2) then return props[2].entity end
    return cache.ped
end

local function updateCamPosition()
    if not cam then return end
    local target = GetEntityCoords(getCamTarget())
    local rad = math.rad(camData.angle)
    SetCamCoord(cam,
        target.x + camData.dist * math.sin(rad),
        target.y - camData.dist * math.cos(rad),
        target.z + camData.height
    )
    PointCamAtCoord(cam, target.x, target.y, target.z + 0.4)
end

local function startCamera()
    if cam then return end
    cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 300, true, false)
    updateCamPosition()
end

local function stopCamera()
    if not cam then return end
    RenderScriptCams(false, true, 300, true, false)
    SetCamActive(cam, false)
    DestroyCam(cam, false)
    cam = nil
end

-- Kamera nachfuehren + Live-Werte an die NUI, nur solange die UI offen ist.
CreateThread(function()
    local tick = 0
    while true do
        if uiOpen and cam then
            Wait(0)
            updateCamPosition()
            tick = tick + 1
            if tick >= 6 then
                tick = 0
                local p1, p2 = props[1], props[2]
                SendNUIMessage({
                    type  = 'updateValues',
                    prop1 = { offset = p1.offset, rotation = p1.rotation },
                    prop2 = { offset = p2.offset, rotation = p2.rotation },
                })
            end
        else
            Wait(250)
            tick = 0
        end
    end
end)

-- ─────────────────────────────────────────────
--  Daten (Server)
-- ─────────────────────────────────────────────

local function refreshPermissions()
    local read, write = lib.callback.await('d4rk_prop_tool:canUse', false)
    canRead  = read  == true
    canWrite = write == true
end

local function loadAttachments()
    local data = lib.callback.await('d4rk_prop_tool:getAttachments', false)
    if type(data) ~= 'table' then
        attachments = {}
        return false
    end
    attachments = data
    return true
end

CreateThread(function()
    refreshPermissions()
    if canRead then loadAttachments() end
    print(('[d4rk_prop_tool] ' .. locale('loaded_hint')):format(RESOURCE_VERSION, Config.Command))
end)

-- ─────────────────────────────────────────────
--  Copy formats
-- ─────────────────────────────────────────────

local function generateCopyText(slot, format)
    local p = props[slot]
    local o, r = p.offset, p.rotation
    local model = p.model ~= '' and p.model or 'no_prop'

    if format == 'ox' then
        return string.format(
            "{\n    model = `%s`,\n    bone  = %d,\n    pos   = vec3(%.4f, %.4f, %.4f),\n    rot   = vec3(%.4f, %.4f, %.4f),\n}",
            model, p.boneId, o.x, o.y, o.z, r.x, r.y, r.z
        )
    elseif format == 'emotes' then
        return string.format(
            "prop = {\n    model='%s', bone=%d,\n    x=%.4f, y=%.4f, z=%.4f,\n    xr=%.4f, yr=%.4f, zr=%.4f,\n}",
            model, p.boneId, o.x, o.y, o.z, r.x, r.y, r.z
        )
    end

    return string.format(
        "-- %s  bone:%d (%s)\nAttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, %d),\n    %.4f, %.4f, %.4f,\n    %.4f, %.4f, %.4f,\n    true, true, false, true, %d, true)",
        model, p.boneId, p.bone, p.boneId, o.x, o.y, o.z, r.x, r.y, r.z, p.rotOrder
    )
end

-- ─────────────────────────────────────────────
--  Export
-- ─────────────────────────────────────────────

local function generateExport(format)
    if not canWrite then
        notify(locale('no_write_access'):format(Config.AcePermission), 'error')
        return
    end
    local output, err = lib.callback.await('d4rk_prop_tool:export', false, format or 'lua')
    if not output then
        notify(err == 'no_entries' and locale('no_entries') or locale('export_failed'), 'error')
        return
    end
    print('\n' .. output .. '\n')
    notify(locale('export_done'), 'success')
end

-- ─────────────────────────────────────────────
--  Open / Close UI
-- ─────────────────────────────────────────────

local UI_KEYS = {
    'ui_katalog', 'ui_katalog_speichern',
    'ui_title', 'ui_close', 'ui_animations', 'ui_custom_dict', 'ui_custom_anim', 'ui_flags',
    'ui_play', 'ui_stop', 'ui_speed', 'ui_move', 'ui_rotate', 'ui_camera', 'ui_focus',
    'ui_focus_ped', 'ui_focus_prop1', 'ui_focus_prop2', 'ui_distance', 'ui_angle', 'ui_height',
    'ui_search_ph', 'ui_custom_model_ph', 'ui_spawn', 'ui_delete', 'ui_bone', 'ui_custom_bone',
    'ui_rot_order', 'ui_rot_order_default', 'ui_position', 'ui_rotation', 'ui_fwd', 'ui_back',
    'ui_left', 'ui_right', 'ui_up', 'ui_down', 'ui_rot_up', 'ui_rot_down', 'ui_reset', 'ui_undo',
    'ui_redo', 'ui_copy', 'ui_quickcopy_title', 'ui_presets', 'ui_no_presets', 'ui_details',
    'ui_load_slot', 'ui_delete_preset', 'ui_lbl_bone', 'ui_lbl_offset', 'ui_lbl_rotation',
    'ui_lbl_anim', 'ui_lbl_note', 'ui_save', 'ui_name_ph', 'ui_notes_ph', 'ui_save_slot',
    'ui_save_entry', 'ui_export', 'ui_export_fmt_lua', 'ui_export_fmt_ox', 'ui_reset_all',
    'ui_copied', 'ui_copy_failed', 'ui_enter_name', 'ui_no_model', 'ui_reset_done',
    'ui_confirm', 'ui_cancel', 'ui_ok', 'ui_confirm_overwrite', 'ui_confirm_delete',
}

local uiLocale = nil
local function buildUiLocale()
    if uiLocale then return uiLocale end
    uiLocale = {}
    for _, key in ipairs(UI_KEYS) do uiLocale[key] = locale(key) end
    return uiLocale
end

local function openUI()
    local boneList = {}
    for _, b in ipairs(Config.Bones) do boneList[#boneList + 1] = { name = b.name, id = b.id } end

    local animList = {}
    for _, a in ipairs(Config.Animations) do
        animList[#animList + 1] = { label = a.label, dict = a.dict, anim = a.anim, flags = a.flags }
    end

    SendNUIMessage({
        type         = 'openUI',
        locale       = buildUiLocale(),
        props        = Config.Props,
        animations   = animList,
        bones        = boneList,
        moveSpeed    = moveSpeed,
        rotateSpeed  = rotateSpeed,
        moveSpeeds   = Config.MoveSpeeds,
        rotateSpeeds = Config.RotateSpeeds,
        camFocus     = camData.focus,
        camDist      = camData.dist,
        camAngle     = camData.angle,
        camHeight    = camData.height,
        presets      = attachments,
        canWrite     = canWrite,
        slots        = {
            [1] = { boneId = props[1].boneId, rotOrder = props[1].rotOrder, model = props[1].model },
            [2] = { boneId = props[2].boneId, rotOrder = props[2].rotOrder, model = props[2].model },
        },
    })
    SetNuiFocus(true, true)
    startCamera()
    uiOpen = true
end

--- d4rk RP: welcher Katalogeintrag gerade eingestellt wird (nil = keiner)
local katalog = nil

local function closeUI()
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'hideUI' })
    stopCamera()
    uiOpen = false
    katalog = nil
end

-- ─────────────────────────────────────────────
--  NUI Callbacks
-- ─────────────────────────────────────────────

--- Wrapper: validiert den Slot und beantwortet den Callback immer.
local function slotCallback(name, fn)
    RegisterNUICallback(name, function(data, cb)
        local slot = tonumber(data and data.slot)
        if slot ~= 1 and slot ~= 2 then cb({}); return end
        fn(slot, data or {})
        cb({})
    end)
end

RegisterNUICallback('closeUI', function(_, cb) closeUI() cb({}) end)

--[[
    d4rk RP - DER KATALOG (Animationsmenue, Paragraph 10, 29.09.2026).

    d4rk_animation ruft KatalogOeffnen mit einem Eintrag:
      { key, label, dict, clip, flag, plaetze = { [1]={model,boneId,rotOrder,offset,rotation}, [2]=... } }
    Das Tool spielt die Animation, haengt die Gegenstaende mit den Katalogwerten
    an und zeigt oben "Katalog: <Name>" samt Knopf. Der Knopf schickt beide
    Plaetze an d4rk_animation:PropSetzen - der Server prueft dort das Recht.
]]
exports('KatalogOeffnen', function(e)
    if type(e) ~= 'table' or type(e.key) ~= 'string' then return false end

    CreateThread(function()
        -- Wie der Befehl: erst Rechte und Voreinstellungen, dann oeffnen.
        -- refreshPermissions wartet auf den Server, deshalb im Faden.
        refreshPermissions()
        if not canRead then
            notify(locale('no_access'), 'error')
            return
        end
        if not uiOpen then
            loadAttachments()
            openUI()
        end
        katalog = { key = e.key, label = e.label or e.key }

        for slot = 1, 2 do
            local q = e.plaetze and e.plaetze[slot]
            if hasProp(slot) then deleteProp(slot) end
            if type(q) == 'table' and (q.model or '') ~= '' then
                local p = props[slot]
                p.boneId   = tonumber(q.boneId) or p.boneId
                p.bone     = boneName(p.boneId)
                p.rotOrder = tonumber(q.rotOrder) or 1
                p.offset   = { x = q.offset.x + 0.0, y = q.offset.y + 0.0, z = q.offset.z + 0.0 }
                p.rotation = { x = q.rotation.x + 0.0, y = q.rotation.y + 0.0, z = q.rotation.z + 0.0 }
                clearHistory(slot)
                if not spawnPropEntity(slot, q.model) then
                    toast(locale('invalid_model'):format(q.model), 'error')
                end
            end
            syncSlot(slot)
        end

        if requestAnimDict(e.dict) then
            stopAnim()
            TaskPlayAnim(cache.ped, e.dict, e.clip, 8.0, -8.0, -1, tonumber(e.flag) or 49, 0, false, false, false)
            currentAnim = { dict = e.dict, clip = e.clip }
        end

        SendNUIMessage({ type = 'katalog', key = e.key, label = katalog.label, dict = e.dict, clip = e.clip, flags = e.flag })
    end)
    return true
end)

RegisterNUICallback('katalogSpeichern', function(_, cb)
    cb({})
    if not katalog then return end
    local plaetze = {}
    for slot = 1, 2 do
        if hasProp(slot) then
            local p = props[slot]
            plaetze[slot] = {
                model = p.model, boneId = p.boneId, rotOrder = p.rotOrder,
                offset = { x = p.offset.x, y = p.offset.y, z = p.offset.z },
                rotation = { x = p.rotation.x, y = p.rotation.y, z = p.rotation.z },
            }
        end
    end
    local key = katalog.key
    CreateThread(function()
        local erg = lib.callback.await('d4rk_prop_tool:katalogSpeichern', false, key, plaetze)
        if type(erg) == 'table' and erg.ok then
            toast(locale('katalog_gespeichert'):format(key), 'success')
        else
            -- Der Grund als TEXT, nicht als Code ("Nicht uebernommen: zahl").
            -- Ein unbekannter Code bleibt sichtbar statt zu verschwinden.
            local g = tostring(type(erg) == 'table' and erg.grund or 'server')
            local text = locale('katalog_grund_' .. g)
            if not text or text == 'katalog_grund_' .. g then text = g end
            toast(locale('katalog_fehler'):format(text), 'error')
        end
    end)
end)

slotCallback('spawnProp', function(slot, data)
    deleteProp(slot)
    if not spawnPropEntity(slot, data.model) then
        toast(locale('invalid_model'):format(tostring(data.model)), 'error')
        return
    end
    clearHistory(slot)
    pushHistory(slot)
    toast(locale('prop_spawned'):format(data.model), 'success')
end)

slotCallback('deleteProp', function(slot)
    deleteProp(slot)
    clearHistory(slot)
    syncSlot(slot)
end)

slotCallback('setBone', function(slot, data)
    local boneId = tonumber(data.boneId)
    if not boneId then return end
    local p = props[slot]
    pushHistory(slot)
    p.boneId = math.floor(boneId)
    p.bone   = boneName(p.boneId)
    attachProp(slot)
    syncSlot(slot)
end)

slotCallback('setRotOrder', function(slot, data)
    local order = tonumber(data.order)
    if not order or order < 0 or order > 5 then return end
    pushHistory(slot)
    props[slot].rotOrder = math.floor(order)
    attachProp(slot)
end)

local MOVE_AXES = {
    forward = { 'offset', 'y',  1 }, back  = { 'offset', 'y', -1 },
    left    = { 'offset', 'x', -1 }, right = { 'offset', 'x',  1 },
    up      = { 'offset', 'z',  1 }, down  = { 'offset', 'z', -1 },
    rotLeft = { 'rotation', 'z', -1 }, rotRight = { 'rotation', 'z',  1 },
    rotUp   = { 'rotation', 'x', -1 }, rotDown  = { 'rotation', 'x',  1 },
    rotCW   = { 'rotation', 'y',  1 }, rotCCW   = { 'rotation', 'y', -1 },
}

slotCallback('moveProp', function(slot, data)
    local axis = MOVE_AXES[data.dir]
    if not axis then return end
    local p     = props[slot]
    local field, comp, sign = axis[1], axis[2], axis[3]
    local step  = field == 'offset' and moveSpeed or rotateSpeed
    p[field][comp] = p[field][comp] + step * sign
    attachProp(slot)
end)

RegisterNUICallback('playAnim', function(data, cb)
    if not requestAnimDict(data.dict) then
        toast(locale('animdict_missing'):format(tostring(data.dict)), 'error')
        cb({}); return
    end
    stopAnim()
    TaskPlayAnim(cache.ped, data.dict, data.anim, 8.0, -8.0, -1, tonumber(data.flags) or 49, 0, false, false, false)
    currentAnim = { dict = data.dict, clip = data.anim }
    cb({})
end)

RegisterNUICallback('stopAnim', function(_, cb) stopAnim() cb({}) end)

RegisterNUICallback('updateMoveSpeed', function(d, cb)
    moveSpeed = tonumber(d.value) or Config.DefaultMoveSpeed
    cb({})
end)

RegisterNUICallback('updateRotateSpeed', function(d, cb)
    rotateSpeed = tonumber(d.value) or Config.DefaultRotateSpeed
    cb({})
end)

RegisterNUICallback('updateCamera', function(data, cb)
    camData.dist   = tonumber(data.dist)   or camData.dist
    camData.angle  = tonumber(data.angle)  or camData.angle
    camData.height = tonumber(data.height) or camData.height
    updateCamPosition()
    cb({})
end)

RegisterNUICallback('updateCameraFocus', function(data, cb)
    camData.focus = data.focus or 'ped'
    updateCamPosition()
    cb({})
end)

slotCallback('resetProp', function(slot)
    pushHistory(slot)
    local p = props[slot]
    p.offset   = { x = 0.0, y = 0.0, z = 0.0 }
    p.rotation = { x = 0.0, y = 0.0, z = 0.0 }
    attachProp(slot)
end)

RegisterNUICallback('resetAll', function(_, cb)
    for slot = 1, 2 do
        pushHistory(slot)
        props[slot].offset   = { x = 0.0, y = 0.0, z = 0.0 }
        props[slot].rotation = { x = 0.0, y = 0.0, z = 0.0 }
        attachProp(slot)
    end
    stopAnim()
    camData = { dist = DEFAULT_CAM.dist, angle = DEFAULT_CAM.angle, height = DEFAULT_CAM.height, focus = DEFAULT_CAM.focus }
    updateCamPosition()
    syncCamera()
    cb({})
end)

slotCallback('copyData', function(slot, data)
    SendNUIMessage({ type = 'clipboard', text = generateCopyText(slot, data.format) })
end)

slotCallback('quickCopy', function(slot)
    local p = props[slot]
    local o, r = p.offset, p.rotation
    SendNUIMessage({ type = 'clipboard', text = string.format(
        '-- %s  bone:%d (%s)\noffset   = vec3(%.4f, %.4f, %.4f)\nrotation = vec3(%.4f, %.4f, %.4f)',
        p.model ~= '' and p.model or 'no_prop', p.boneId, p.bone,
        o.x, o.y, o.z, r.x, r.y, r.z
    ) })
end)

slotCallback('startMove', function(slot) pushHistory(slot) end)
slotCallback('undo',      function(slot) undoSlot(slot) end)
slotCallback('redo',      function(slot) redoSlot(slot) end)

slotCallback('loadPreset', function(slot, data)
    local preset = attachments[data.name]
    if not preset then
        toast(locale('preset_not_found'):format(tostring(data.name)), 'error')
        return
    end

    pushHistory(slot)
    local p = props[slot]
    p.offset   = { x = preset.offset.x,   y = preset.offset.y,   z = preset.offset.z }
    p.rotation = { x = preset.rotation.x, y = preset.rotation.y, z = preset.rotation.z }
    p.boneId   = preset.boneId
    p.bone     = boneName(preset.boneId)
    p.rotOrder = preset.rotOrder or 1

    local needsSpawn = not hasProp(slot) and preset.prop ~= ''
    if needsSpawn then
        CreateThread(function()
            if not spawnPropEntity(slot, preset.prop) then
                toast(locale('invalid_model'):format(preset.prop), 'error')
                return
            end
            syncSlot(slot)
            toast(locale('preset_loaded'):format(data.name, slot), 'success')
        end)
        return
    end

    attachProp(slot)
    syncSlot(slot)
    toast(locale('preset_loaded'):format(data.name, slot), 'success')
end)

RegisterNUICallback('saveEntry', function(data, cb)
    local slot = tonumber(data.slot)
    if slot ~= 1 and slot ~= 2 then cb({}); return end

    local name = (data.name or ''):gsub('%s+', '_'):gsub('[^%w_%-]', ''):lower()
    if name == '' then cb({}); return end

    if not hasProp(slot) then
        toast(locale('no_prop_in_slot'):format(slot), 'error')
        cb({}); return
    end

    local p = props[slot]
    local entry = {
        prop     = p.model,
        bone     = p.bone,
        boneId   = p.boneId,
        rotOrder = p.rotOrder,
        offset   = { x = p.offset.x,   y = p.offset.y,   z = p.offset.z },
        rotation = { x = p.rotation.x, y = p.rotation.y, z = p.rotation.z },
        animDict = currentAnim and currentAnim.dict or '',
        animClip = currentAnim and currentAnim.clip or '',
        notes    = data.notes or '',
    }

    local ok, err, all = lib.callback.await('d4rk_prop_tool:saveAttachment', false, name, entry)
    if not ok then
        toast(err == 'no_write_access'
            and locale('no_write_access'):format(Config.AcePermission)
            or locale('preset_save_failed'), 'error')
        cb({}); return
    end

    attachments = all or attachments
    SendNUIMessage({ type = 'updatePresets', presets = attachments })
    toast(locale('preset_saved'):format(name), 'success')
    cb({})
end)

RegisterNUICallback('deletePreset', function(data, cb)
    local name = data.name
    local ok, err, all = lib.callback.await('d4rk_prop_tool:deleteAttachment', false, name)
    if not ok then
        toast(err == 'no_write_access'
            and locale('no_write_access'):format(Config.AcePermission)
            or locale('preset_save_failed'), 'error')
        cb({}); return
    end
    attachments = all or attachments
    SendNUIMessage({ type = 'updatePresets', presets = attachments })
    toast(locale('preset_deleted'):format(name), 'success')
    cb({})
end)

RegisterNUICallback('exportLua', function(data, cb)
    generateExport(data and data.format)
    cb({})
end)

-- ─────────────────────────────────────────────
--  Numpad (Slot 1, funktioniert bei geschlossener UI)
-- ─────────────────────────────────────────────

local stepIndex = 2

local AXES = {
    off_yp = { key = 'NUMPAD8',     kind = 'offset',   comp = 'y', sign =  1 },
    off_yn = { key = 'NUMPAD2',     kind = 'offset',   comp = 'y', sign = -1 },
    off_xn = { key = 'NUMPAD4',     kind = 'offset',   comp = 'x', sign = -1 },
    off_xp = { key = 'NUMPAD6',     kind = 'offset',   comp = 'x', sign =  1 },
    off_zp = { key = 'NUMPAD7',     kind = 'offset',   comp = 'z', sign =  1 },
    off_zn = { key = 'NUMPAD9',     kind = 'offset',   comp = 'z', sign = -1 },
    rot_xp = { key = 'NUMPAD1',     kind = 'rotation', comp = 'x', sign =  1 },
    rot_xn = { key = 'NUMPAD3',     kind = 'rotation', comp = 'x', sign = -1 },
    rot_yp = { key = 'NUMPAD0',     kind = 'rotation', comp = 'y', sign =  1 },
    rot_yn = { key = 'DECIMAL',     kind = 'rotation', comp = 'y', sign = -1 },
    rot_zp = { key = 'NUMPAD5',     kind = 'rotation', comp = 'z', sign =  1 },
    rot_zn = { key = 'NUMPADENTER', kind = 'rotation', comp = 'z', sign = -1 },
}

local holdState = {}
for name in pairs(AXES) do holdState[name] = { pressed = false, holdTime = 0 } end
local heldCount = 0

local function accel(ms)
    if ms < 400  then return 1.0 end
    if ms < 1200 then return 1.0 + (ms - 400) / 800 * 4.0 end
    return 10.0
end

for name, axis in pairs(AXES) do
    lib.addKeybind({
        name = 'ptool_num_' .. name,
        description = 'Prop Tool Num - ' .. name,
        defaultKey = axis.key,
        onPressed = function()
            if uiOpen or not canRead or not hasProp(1) then return end
            if holdState[name].pressed then return end
            holdState[name].pressed  = true
            holdState[name].holdTime = 0
            heldCount = heldCount + 1
        end,
        onReleased = function()
            if not holdState[name].pressed then return end
            holdState[name].pressed  = false
            holdState[name].holdTime = 0
            heldCount = math.max(0, heldCount - 1)
        end,
    })
end

local function applyStep()
    moveSpeed   = Config.MoveStepLevels[stepIndex]   or moveSpeed
    rotateSpeed = Config.RotateStepLevels[stepIndex] or rotateSpeed
    if uiOpen then syncSpeeds() end
    lib.notify({
        title = locale('title'),
        description = locale('move_step'):format(moveSpeed) .. ' / ' .. locale('rotate_step'):format(rotateSpeed),
        type = 'inform', duration = 1400, position = 'top-right',
    })
end

lib.addKeybind({ name = 'ptool_step_up', description = 'Prop Tool - Schritt +', defaultKey = 'ADD',
    onPressed = function()
        if uiOpen or not canRead then return end
        stepIndex = math.min(#Config.MoveStepLevels, stepIndex + 1)
        applyStep()
    end })

lib.addKeybind({ name = 'ptool_step_down', description = 'Prop Tool - Schritt -', defaultKey = 'SUBTRACT',
    onPressed = function()
        if uiOpen or not canRead then return end
        stepIndex = math.max(1, stepIndex - 1)
        applyStep()
    end })

-- Laeuft nur auf Wait(0), solange wirklich eine Taste gehalten wird.
CreateThread(function()
    local lastFrame = GetGameTimer()
    while true do
        if uiOpen or heldCount == 0 then
            Wait(150)
            lastFrame = GetGameTimer()
        else
            Wait(0)
            local now = GetGameTimer()
            local dt  = math.min(now - lastFrame, 100)
            lastFrame = now
            local p, changed = props[1], false
            for name, state in pairs(holdState) do
                if state.pressed then
                    state.holdTime = state.holdTime + dt
                    local axis = AXES[name]
                    local base = axis.kind == 'offset' and moveSpeed or rotateSpeed
                    p[axis.kind][axis.comp] = p[axis.kind][axis.comp]
                        + base * accel(state.holdTime) * (dt / 1000.0) * axis.sign
                    changed = true
                end
            end
            if changed then attachProp(1) end
        end
    end
end)

-- ─────────────────────────────────────────────
--  Exports fuer andere Resourcen
-- ─────────────────────────────────────────────

exports('getAttachments', function() return attachments end)
exports('getAttachment',  function(name) return attachments[name] end)

--- Haengt ein gespeichertes Attachment an einen beliebigen Ped.
--- Gibt die Entity zurueck - der Aufrufer ist fuer das Loeschen zustaendig.
exports('applyAttachment', function(name, ped)
    local e = attachments[name]
    if not e or e.prop == '' then return nil end
    ped = ped or cache.ped
    local mdl = requestModel(e.prop)
    if not mdl then return nil end
    local coords = GetEntityCoords(ped)
    local ent = CreateObject(mdl, coords.x, coords.y, coords.z, false, false, false)
    SetModelAsNoLongerNeeded(mdl)
    AttachEntityToEntity(ent, ped, GetPedBoneIndex(ped, e.boneId),
        e.offset.x, e.offset.y, e.offset.z,
        e.rotation.x, e.rotation.y, e.rotation.z,
        true, true, false, true, e.rotOrder or 1, true)
    return ent
end)

-- ─────────────────────────────────────────────
--  Commands
-- ─────────────────────────────────────────────

RegisterCommand(Config.Command, function(_, args)
    refreshPermissions()
    if not canRead then
        notify(locale('no_access'), 'error')
        return
    end

    local sub = args[1]
    if not sub or sub == '' then
        if uiOpen then
            closeUI()
        else
            loadAttachments()
            openUI()
        end
    elseif sub == 'stop' then
        stopAnim(); deleteProp(1); deleteProp(2); closeUI()
        notify(locale('all_stopped'), 'inform')
    elseif sub == 'export' then
        generateExport(args[2])
    elseif sub == 'list' then
        loadAttachments()
        if not next(attachments) then
            print('[d4rk_prop_tool] ' .. locale('no_entries'))
            return
        end
        print('\n[d4rk_prop_tool]')
        for n, e in pairs(attachments) do
            print(('  - %s -> %s @ %s (%d)'):format(n, e.prop, e.bone, e.boneId))
        end
        notify(locale('entries_in_console'), 'inform')
    end
end, false)

-- ─────────────────────────────────────────────
--  Cleanup
-- ─────────────────────────────────────────────

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    stopAnim()
    deleteProp(1); deleteProp(2)
    stopCamera()
    if uiOpen then SetNuiFocus(false, false); uiOpen = false end
end)
