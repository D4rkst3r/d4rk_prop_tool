--[[
    d4rk_prop_tool - client/main.lua  v2.0
    Prop Attachment & Animation Testing Tool
    Abhaengigkeiten: ox_lib, config.lua
--]]

local dataview = require 'client.dataview'

-- ─────────────────────────────────────────────
--  State
-- ─────────────────────────────────────────────

local uiOpen = false

local props = {
    [1] = { entity=nil, model='', bone='SKEL_R_Hand', boneId=28422, rotOrder=1,
            offset={x=0.0,y=0.0,z=0.0}, rotation={x=0.0,y=0.0,z=0.0} },
    [2] = { entity=nil, model='', bone='SKEL_L_Hand', boneId=57005, rotOrder=1,
            offset={x=0.0,y=0.0,z=0.0}, rotation={x=0.0,y=0.0,z=0.0} },
}

local history = { {}, {} }
local historyIdx = { 0, 0 }
local MAX_HISTORY = 100

local currentAnim = nil
local moveSpeed   = Config.DefaultMoveSpeed   or 0.01
local rotateSpeed = Config.DefaultRotateSpeed or 1.0

local cam     = nil
local camData = { dist=2.5, angle=0.0, height=0.5, focus='ped' }

local gizmoActive    = false
local gizmoEnabled   = false
local gizmoMode      = 'Translate'
local gizmoRelative  = false
local gizmoCursor    = false
local gizmoCancelled = false

local WHEEL_STEP = 0.05
local MIN_SCALE  = 0.05
local MAX_SCALE  = 50.0

local cachedAttachments = {}

-- ─────────────────────────────────────────────
--  Helpers
-- ─────────────────────────────────────────────

local function requestModel(modelName)
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
    if not DoesAnimDictExist(dict) then return false end
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
    local ped = PlayerPedId()
    AttachEntityToEntity(
        p.entity, ped,
        GetPedBoneIndex(ped, p.boneId),
        p.offset.x, p.offset.y, p.offset.z,
        p.rotation.x, p.rotation.y, p.rotation.z,
        true, true, false, true, p.rotOrder, true
    )
end

local function deleteProp(slot)
    local p = props[slot]
    if p.entity and DoesEntityExist(p.entity) then
        DeleteEntity(p.entity)
    end
    p.entity = nil
end

local function stopAnim()
    if currentAnim then
        StopAnimTask(PlayerPedId(), currentAnim.dict, currentAnim.clip, 1.0)
        currentAnim = nil
    end
end

-- ─────────────────────────────────────────────
--  Undo / Redo
-- ─────────────────────────────────────────────

pushHistory = function(slot)
    local p = props[slot]
    local h = history[slot]
    while #h > historyIdx[slot] do table.remove(h) end
    historyIdx[slot] = historyIdx[slot] + 1
    h[historyIdx[slot]] = {
        offset   = { x=p.offset.x,   y=p.offset.y,   z=p.offset.z },
        rotation = { x=p.rotation.x, y=p.rotation.y, z=p.rotation.z },
    }
    if #h > MAX_HISTORY then
        table.remove(h, 1)
        historyIdx[slot] = historyIdx[slot] - 1
    end
end

local function applyHistoryState(slot)
    local p     = props[slot]
    local state = history[slot][historyIdx[slot]]
    if not state then return end
    p.offset   = { x=state.offset.x,   y=state.offset.y,   z=state.offset.z }
    p.rotation = { x=state.rotation.x, y=state.rotation.y, z=state.rotation.z }
    attachProp(slot)
end

undoSlot = function(slot)
    if historyIdx[slot] <= 1 then
        lib.notify({ title='Prop Tool', description='Nichts mehr rueckgaengig.', type='inform', duration=1200 })
        return
    end
    historyIdx[slot] = historyIdx[slot] - 1
    applyHistoryState(slot)
end

redoSlot = function(slot)
    if historyIdx[slot] >= #history[slot] then
        lib.notify({ title='Prop Tool', description='Nichts mehr wiederholen.', type='inform', duration=1200 })
        return
    end
    historyIdx[slot] = historyIdx[slot] + 1
    applyHistoryState(slot)
end

clearHistory = function(slot)
    history[slot]    = {}
    historyIdx[slot] = 0
end

-- ─────────────────────────────────────────────
--  Camera
-- ─────────────────────────────────────────────

local function getCamTarget()
    if camData.focus == 'prop1' and props[1].entity and DoesEntityExist(props[1].entity) then
        return props[1].entity
    elseif camData.focus == 'prop2' and props[2].entity and DoesEntityExist(props[2].entity) then
        return props[2].entity
    end
    return PlayerPedId()
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

CreateThread(function()
    local tick = 0
    while true do
        if uiOpen and cam then
            Wait(0)
            updateCamPosition()
            tick = tick + 1
            if tick >= 6 then
                tick = 0
                local p1 = props[1]
                local p2 = props[2]
                SendNUIMessage({
                    type  = 'updateValues',
                    prop1 = { offset={x=p1.offset.x, y=p1.offset.y, z=p1.offset.z}, rotation={x=p1.rotation.x, y=p1.rotation.y, z=p1.rotation.z} },
                    prop2 = { offset={x=p2.offset.x, y=p2.offset.y, z=p2.offset.z}, rotation={x=p2.rotation.x, y=p2.rotation.y, z=p2.rotation.z} },
                })
            end
        else
            Wait(100)
            tick = 0
        end
    end
end)

-- ─────────────────────────────────────────────
--  Gizmo
-- ─────────────────────────────────────────────

local function _vecLen(x, y, z)  return math.sqrt(x*x + y*y + z*z) end
local function _normalize(x, y, z)
    local l = _vecLen(x, y, z)
    if l == 0 then return 0, 0, 0 end
    return x/l, y/l, z/l
end
local function _clamp(v, a, b) if v < a then return a end if v > b then return b end return v end

local function _uniformScale(e)
    local f, r, u = GetEntityMatrix(e)
    local s = (_vecLen(r[1],r[2],r[3]) + _vecLen(f[1],f[2],f[3]) + _vecLen(u[1],u[2],u[3])) / 3.0
    return s > 0.0 and s or 1.0
end

local function _makeMatrix(e)
    local f, r, u, a = GetEntityMatrix(e)
    local v = dataview.ArrayBuffer(64)
    v:SetFloat32(0,  r[1]):SetFloat32(4,  r[2]):SetFloat32(8,  r[3]):SetFloat32(12, 0)
     :SetFloat32(16, f[1]):SetFloat32(20, f[2]):SetFloat32(24, f[3]):SetFloat32(28, 0)
     :SetFloat32(32, u[1]):SetFloat32(36, u[2]):SetFloat32(40, u[3]):SetFloat32(44, 0)
     :SetFloat32(48, a[1]):SetFloat32(52, a[2]):SetFloat32(56, a[3]):SetFloat32(60, 1)
    return v
end

local function _applyMatrix(e, v)
    local x1,y1,z1 = _normalize(v:GetFloat32(16), v:GetFloat32(20), v:GetFloat32(24))
    local x2,y2,z2 = _normalize(v:GetFloat32(0),  v:GetFloat32(4),  v:GetFloat32(8))
    local x3,y3,z3 = _normalize(v:GetFloat32(32), v:GetFloat32(36), v:GetFloat32(40))
    SetEntityMatrix(e, x1,y1,z1, x2,y2,z2, x3,y3,z3, v:GetFloat32(48), v:GetFloat32(52), v:GetFloat32(56))
end

local function _applyScale(v, s)
    local fnx,fny,fnz = _normalize(v:GetFloat32(16), v:GetFloat32(20), v:GetFloat32(24))
    local rnx,rny,rnz = _normalize(v:GetFloat32(0),  v:GetFloat32(4),  v:GetFloat32(8))
    local unx,uny,unz = _normalize(v:GetFloat32(32), v:GetFloat32(36), v:GetFloat32(40))
    v:SetFloat32(16, fnx*s):SetFloat32(20, fny*s):SetFloat32(24, fnz*s)
     :SetFloat32(0,  rnx*s):SetFloat32(4,  rny*s):SetFloat32(8,  rnz*s)
     :SetFloat32(32, unx*s):SetFloat32(36, uny*s):SetFloat32(40, unz*s)
end

local function computeFromWorld(slot)
    local p = props[slot]
    local ped = PlayerPedId()
    local bonePos = GetWorldPositionOfEntityBone(ped, GetPedBoneIndex(ped, p.boneId))
    local propPos = GetEntityCoords(p.entity)
    local propRot = GetEntityRotation(p.entity, 2)
    local dx = propPos.x - bonePos.x
    local dy = propPos.y - bonePos.y
    local dz = propPos.z - bonePos.z
    local pf, pr, pu = GetEntityMatrix(ped)
    p.offset.x = dx*pr[1] + dy*pr[2] + dz*pr[3]
    p.offset.y = dx*pf[1] + dy*pf[2] + dz*pf[3]
    p.offset.z = dx*pu[1] + dy*pu[2] + dz*pu[3]
    local pedRot = GetEntityRotation(ped, 2)
    p.rotation.x = propRot.x
    p.rotation.y = propRot.y
    p.rotation.z = propRot.z - pedRot.z
end

local function gizmoTextUILoop(entity)
    CreateThread(function()
        while gizmoEnabled do
            Wait(100)
            local pos = GetEntityCoords(entity)
            local rot = GetEntityRotation(entity, 2)
            lib.showTextUI(
                string.format(
                    'Gizmo - %s | %s\n'
                    .. 'Pos  %.2f  %.2f  %.2f\n'
                    .. 'Rot  %.1f  %.1f  %.1f  Scale: %.2f\n'
                    .. 'W=Move  R=Rotate  S=Scale  Q=Lokal\n'
                    .. 'LALT=Snap  ENTER=OK  ESC=Abbruch',
                    gizmoMode, gizmoRelative and 'Lokal' or 'Welt',
                    pos.x, pos.y, pos.z,
                    rot.x, rot.y, rot.z, _uniformScale(entity)
                ),
                { position = 'top-left', icon = 'arrow-pointer' }
            )
        end
        lib.hideTextUI()
    end)
end

local function runGizmoLoop(entity)
    gizmoCursor = true
    EnterCursorMode()
    SetEntityDrawOutline(entity, true)

    while gizmoEnabled and DoesEntityExist(entity) do
        Wait(0)

        if IsControlJustPressed(0, 47) then
            if gizmoCursor then LeaveCursorMode() gizmoCursor = false
            else EnterCursorMode() gizmoCursor = true end
        end

        DisableControlAction(0, 24,  true)
        DisableControlAction(0, 25,  true)
        DisableControlAction(0, 140, true)
        DisablePlayerFiring(cache.playerId, true)
        DisableControlAction(0, 200, true)
        DisableControlAction(0, 199, true)
        DisableControlAction(0, 202, true)

        if IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 202) then
            gizmoCancelled = true
            gizmoEnabled   = false
            PlaySoundFrontend(-1, 'CANCEL', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
            break
        end

        local mat = _makeMatrix(entity)

        if gizmoMode == 'Scale' then
            DisableControlAction(0, 14, true)
            DisableControlAction(0, 15, true)
            local up   = IsDisabledControlJustPressed(0, 15)
            local down = IsDisabledControlJustPressed(0, 14)
            if up or down then
                local t = _clamp(_uniformScale(entity) * (1.0 + (up and WHEEL_STEP or -WHEEL_STEP)), MIN_SCALE, MAX_SCALE)
                _applyScale(mat, t)
                _applyMatrix(entity, mat)
            end
        end

        if gizmoMode == 'Rotate' and IsControlPressed(0, 21) then
            local rot = GetEntityRotation(entity, 2)
            rot.z = math.floor((rot.z + 22.5) / 45) * 45
            SetEntityRotation(entity, rot.x, rot.y, rot.z, 2, true)
        end

        local changed = Citizen.InvokeNative(0xEB2EDCA2, mat:Buffer(), 'PropTool_Gizmo', Citizen.ReturnResultAnyway())
        if changed then
            if gizmoMode == 'Scale' then
                local ns = _clamp(math.max(
                    _vecLen(mat:GetFloat32(0),  mat:GetFloat32(4),  mat:GetFloat32(8)),
                    _vecLen(mat:GetFloat32(16), mat:GetFloat32(20), mat:GetFloat32(24)),
                    _vecLen(mat:GetFloat32(32), mat:GetFloat32(36), mat:GetFloat32(40))
                ), MIN_SCALE, MAX_SCALE)
                _applyScale(mat, ns)
            end
            _applyMatrix(entity, mat)
        end
    end

    if gizmoCursor then LeaveCursorMode() end
    gizmoCursor = false
    SetEntityDrawOutline(entity, false)
    gizmoEnabled = false
end

local function startGizmo(slot)
    local p = props[slot]
    if not p.entity or not DoesEntityExist(p.entity) then
        lib.notify({ title='Prop Tool', description='Kein Prop in Slot '..slot, type='error' })
        return
    end
    if gizmoActive then return end

    CreateThread(function()
        SetNuiFocus(false, false)
        SendNUIMessage({ type='hideUI' })
        stopCamera()
        uiOpen = false

        gizmoActive    = true
        gizmoEnabled   = true
        gizmoCancelled = false
        gizmoMode      = 'Translate'

        local savedOff = { x=p.offset.x,   y=p.offset.y,   z=p.offset.z }
        local savedRot = { x=p.rotation.x, y=p.rotation.y, z=p.rotation.z }

        DetachEntity(p.entity, true, true)
        FreezeEntityPosition(p.entity, true)

        gizmoTextUILoop(p.entity)
        runGizmoLoop(p.entity)

        FreezeEntityPosition(p.entity, false)
        gizmoActive = false

        if gizmoCancelled then
            p.offset   = savedOff
            p.rotation = savedRot
            lib.notify({ title='Prop Tool', description='Gizmo abgebrochen.', type='error' })
        else
            pushHistory(slot)
            computeFromWorld(slot)
            pushHistory(slot)
            lib.notify({ title='Prop Tool', description='Gizmo fertig.', type='success' })
        end

        attachProp(slot)
        openUI()
    end)
end

lib.addKeybind({ name='_ptool_gizmoSelect',    description='Prop Tool Gizmo - Auswahl',    defaultMapper='MOUSE_BUTTON', defaultKey='MOUSE_LEFT',
    onPressed=function() if gizmoEnabled then ExecuteCommand('+gizmoSelect') end end,
    onReleased=function() ExecuteCommand('-gizmoSelect') end })
lib.addKeybind({ name='_ptool_gizmoTranslate', description='Prop Tool Gizmo - Move',        defaultKey='W',
    onPressed=function() if gizmoEnabled then gizmoMode='Translate' ExecuteCommand('+gizmoTranslation') end end,
    onReleased=function() ExecuteCommand('-gizmoTranslation') end })
lib.addKeybind({ name='_ptool_gizmoRotate',    description='Prop Tool Gizmo - Rotate',      defaultKey='R',
    onPressed=function() if gizmoEnabled then gizmoMode='Rotate' ExecuteCommand('+gizmoRotation') end end,
    onReleased=function() ExecuteCommand('-gizmoRotation') end })
lib.addKeybind({ name='_ptool_gizmoScale',     description='Prop Tool Gizmo - Scale',       defaultKey='S',
    onPressed=function() if gizmoEnabled then gizmoMode='Scale' ExecuteCommand('+gizmoScale') end end,
    onReleased=function() ExecuteCommand('-gizmoScale') end })
lib.addKeybind({ name='_ptool_gizmoLocal',     description='Prop Tool Gizmo - Lokal/Welt',  defaultKey='Q',
    onPressed=function() if gizmoEnabled then gizmoRelative=not gizmoRelative ExecuteCommand('+gizmoLocal') end end,
    onReleased=function() ExecuteCommand('-gizmoLocal') end })
lib.addKeybind({ name='ptool_gizmoSnap',       description='Prop Tool Gizmo - Snap Ground', defaultKey='LMENU',
    onPressed=function() if gizmoEnabled then PlaceObjectOnGroundProperly_2(props[1].entity) end end })
lib.addKeybind({ name='ptool_gizmoConfirm',    description='Prop Tool Gizmo - Bestaetigen', defaultKey='RETURN',
    onReleased=function() if gizmoEnabled then gizmoEnabled=false end end })

-- ─────────────────────────────────────────────
--  Data / Persistence
-- ─────────────────────────────────────────────

local function loadAttachments() return cachedAttachments end

local function saveAttachments(data)
    cachedAttachments = data
    TriggerServerEvent('d4rk_prop_tool:saveAttachments', json.encode(data, { indent=true }))
end

RegisterNetEvent('d4rk_prop_tool:receiveAttachments')
AddEventHandler('d4rk_prop_tool:receiveAttachments', function(raw)
    local ok, data = pcall(json.decode, raw)
    if not ok then
        print('[d4rk_prop_tool] Ungueltige attachments.json erhalten, Presets werden nicht geladen.')
        lib.notify({ title='Prop Tool', description='Fehler beim Laden von attachments.json', type='error', duration=4000 })
        cachedAttachments = {}
    else
        cachedAttachments = data
        if uiOpen then
            SendNUIMessage({ type='updatePresets', presets=cachedAttachments })
        end
    end
end)

CreateThread(function()
    Wait(500)
    TriggerServerEvent('d4rk_prop_tool:loadAttachments')
end)

-- ─────────────────────────────────────────────
--  Copy formats
-- ─────────────────────────────────────────────

local function generateCopyText(slot, format)
    local p = props[slot]
    local o = p.offset
    local r = p.rotation
    if format == 'ox' then
        return string.format(
            "{\n    model = '%s',\n    bone  = %d,\n    pos   = vec3(%.4f, %.4f, %.4f),\n    rot   = vec3(%.4f, %.4f, %.4f),\n}",
            p.model, p.boneId, o.x, o.y, o.z, r.x, r.y, r.z
        )
    elseif format == 'emotes' then
        return string.format(
            "prop = {\n    model='%s', bone=%d,\n    x=%.4f, y=%.4f, z=%.4f,\n    xr=%.4f, yr=%.4f, zr=%.4f,\n}",
            p.model, p.boneId, o.x, o.y, o.z, r.x, r.y, r.z
        )
    else
        return string.format(
            "-- %s  bone:%d\nAttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, %d),\n    %.4f, %.4f, %.4f,\n    %.4f, %.4f, %.4f,\n    true, true, false, true, %d, true)",
            p.model, p.boneId, p.boneId, o.x, o.y, o.z, r.x, r.y, r.z, p.rotOrder
        )
    end
end

-- ─────────────────────────────────────────────
--  Export
-- ─────────────────────────────────────────────

local function generateExport()
    local data = loadAttachments()
    if not next(data) then
        lib.notify({ title='Prop Tool', description='Keine Eintraege.', type='error' })
        return
    end
    local d, mo, y  = GetClockDate()
    local h, mi, s  = GetClockTime()
    local timestamp = string.format('%04d-%02d-%02d %02d:%02d:%02d', y, mo, d, h, mi, s)
    local lines = { '-- d4rk_prop_tool export', '-- '..timestamp, '', 'local ATTACHMENTS = {' }
    for name, e in pairs(data) do
        lines[#lines+1] = '    '..name..' = {'
        lines[#lines+1] = "        prop     = '"..e.prop.."',"
        lines[#lines+1] = '        bone     = '..e.boneId..',  -- '..e.bone
        lines[#lines+1] = string.format('        offset   = vector3(%.4f, %.4f, %.4f),', e.offset.x, e.offset.y, e.offset.z)
        lines[#lines+1] = string.format('        rotation = vector3(%.4f, %.4f, %.4f),', e.rotation.x, e.rotation.y, e.rotation.z)
        if e.animDict and e.animDict ~= '' then
            lines[#lines+1] = "        animDict = '"..e.animDict.."',"
            lines[#lines+1] = "        animClip = '"..e.animClip.."',"
        end
        if e.notes and e.notes ~= '' then lines[#lines+1] = '        -- '..e.notes end
        lines[#lines+1] = '    },'
    end
    lines[#lines+1] = '}'
    local output = table.concat(lines, '\n')
    print('\n'..output..'\n')
    TriggerServerEvent('d4rk_prop_tool:saveExport', output)
    lib.notify({ title='Prop Tool', description='Export in F8 + output/export.lua', type='success', duration=5000 })
end

-- ─────────────────────────────────────────────
--  Open / Close UI
-- ─────────────────────────────────────────────

function openUI()
    local boneList = {}
    for _, b in ipairs(Config.Bones) do boneList[#boneList+1] = { name=b.name, id=b.id } end

    local animList = {}
    for _, a in ipairs(Config.Animations) do animList[#animList+1] = { label=a.label, dict=a.dict, anim=a.anim, flags=a.flags } end

    SendNUIMessage({
        type         = 'openUI',
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
        presets      = cachedAttachments,
    })
    SetNuiFocus(true, true)
    startCamera()
    uiOpen = true
end

local function closeUI()
    SetNuiFocus(false, false)
    SendNUIMessage({ type='hideUI' })
    stopCamera()
    uiOpen = false
end

-- ─────────────────────────────────────────────
--  NUI Callbacks
-- ─────────────────────────────────────────────

RegisterNUICallback('closeUI', function(_, cb) closeUI() cb({}) end)

RegisterNUICallback('spawnProp', function(data, cb)
    local slot  = data.slot
    local model = data.model
    deleteProp(slot)
    local mdl = requestModel(model)
    if not mdl then
        SendNUIMessage({ type='toast', msg='Ungueltiges Modell: '..model, style='error' })
        cb({}); return
    end
    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local ent    = CreateObject(mdl, coords.x, coords.y, coords.z, false, false, false)
    SetEntityNoCollisionEntity(ent, ped, true)
    SetEntityAsMissionEntity(ent, true, true)
    SetModelAsNoLongerNeeded(mdl)
    props[slot].entity = ent
    props[slot].model  = model
    clearHistory(slot)
    pushHistory(slot)
    attachProp(slot)
    SendNUIMessage({ type='toast', msg='Prop '..model..' gespawnt', style='success' })
    cb({})
end)

RegisterNUICallback('deleteProp', function(data, cb)
    deleteProp(data.slot)
    cb({})
end)

RegisterNUICallback('setBone', function(data, cb)
    local p = props[data.slot]
    p.boneId = data.boneId
    for _, b in ipairs(Config.Bones) do
        if b.id == data.boneId then p.bone = b.name break end
    end
    attachProp(data.slot)
    cb({})
end)

RegisterNUICallback('setRotOrder', function(data, cb)
    props[data.slot].rotOrder = data.order
    attachProp(data.slot)
    cb({})
end)

RegisterNUICallback('moveProp', function(data, cb)
    local p  = props[data.slot]
    local d  = data.dir
    local ms = moveSpeed
    local rs = rotateSpeed
    if     d == 'forward'  then p.offset.y   = p.offset.y   + ms
    elseif d == 'back'     then p.offset.y   = p.offset.y   - ms
    elseif d == 'left'     then p.offset.x   = p.offset.x   - ms
    elseif d == 'right'    then p.offset.x   = p.offset.x   + ms
    elseif d == 'up'       then p.offset.z   = p.offset.z   + ms
    elseif d == 'down'     then p.offset.z   = p.offset.z   - ms
    elseif d == 'rotLeft'  then p.rotation.z = p.rotation.z - rs
    elseif d == 'rotRight' then p.rotation.z = p.rotation.z + rs
    elseif d == 'rotUp'    then p.rotation.x = p.rotation.x - rs
    elseif d == 'rotDown'  then p.rotation.x = p.rotation.x + rs
    elseif d == 'rotCW'    then p.rotation.y = p.rotation.y + rs
    elseif d == 'rotCCW'   then p.rotation.y = p.rotation.y - rs
    end
    attachProp(data.slot)
    cb({})
end)

RegisterNUICallback('playAnim', function(data, cb)
    if not requestAnimDict(data.dict) then
        SendNUIMessage({ type='toast', msg='AnimDict nicht gefunden', style='error' })
        cb({}); return
    end
    stopAnim()
    TaskPlayAnim(PlayerPedId(), data.dict, data.anim, 8.0, -8.0, -1, data.flags or 49, 0, false, false, false)
    currentAnim = { dict=data.dict, clip=data.anim }
    cb({})
end)

RegisterNUICallback('stopAnim',          function(_, cb) stopAnim() cb({}) end)
RegisterNUICallback('updateMoveSpeed',   function(d, cb) moveSpeed   = tonumber(d.value) or 0.01 cb({}) end)
RegisterNUICallback('updateRotateSpeed', function(d, cb) rotateSpeed = tonumber(d.value) or 1.0  cb({}) end)

RegisterNUICallback('updateCamera', function(data, cb)
    camData.dist   = data.dist   or camData.dist
    camData.angle  = data.angle  or camData.angle
    camData.height = data.height or camData.height
    updateCamPosition()
    cb({})
end)

RegisterNUICallback('updateCameraFocus', function(data, cb)
    camData.focus = data.focus or 'ped'
    updateCamPosition()
    cb({})
end)

RegisterNUICallback('startGizmo', function(data, cb) startGizmo(data.slot) cb({}) end)

RegisterNUICallback('resetProp', function(data, cb)
    local slot = data.slot
    pushHistory(slot)
    local p = props[slot]
    p.offset   = { x=0.0, y=0.0, z=0.0 }
    p.rotation = { x=0.0, y=0.0, z=0.0 }
    attachProp(slot)
    cb({})
end)

RegisterNUICallback('resetAll', function(_, cb)
    for slot = 1, 2 do
        pushHistory(slot)
        props[slot].offset   = { x=0.0, y=0.0, z=0.0 }
        props[slot].rotation = { x=0.0, y=0.0, z=0.0 }
        attachProp(slot)
    end
    stopAnim()
    camData = { dist=2.5, angle=0.0, height=0.5, focus='ped' }
    cb({})
end)

RegisterNUICallback('copyData', function(data, cb)
    SendNUIMessage({ type='clipboard', text=generateCopyText(data.slot, data.format) })
    cb({})
end)

RegisterNUICallback('quickCopy', function(data, cb)
    local p = props[data.slot]
    local o = p.offset
    local r = p.rotation
    local text = string.format(
        '-- %s  bone:%d\noffset   = vec3(%.4f, %.4f, %.4f)\nrotation = vec3(%.4f, %.4f, %.4f)',
        p.model ~= '' and p.model or 'no_prop', p.boneId,
        o.x, o.y, o.z, r.x, r.y, r.z
    )
    SendNUIMessage({ type='clipboard', text=text })
    cb({})
end)

RegisterNUICallback('startMove', function(data, cb)
    pushHistory(data.slot)
    cb({})
end)

RegisterNUICallback('undo', function(data, cb)
    undoSlot(data.slot)
    cb({})
end)

RegisterNUICallback('redo', function(data, cb)
    redoSlot(data.slot)
    cb({})
end)

RegisterNUICallback('loadPreset', function(data, cb)
    local name = data.name
    local slot = data.slot
    local all  = loadAttachments()
    local preset = all[name]
    if not preset then
        SendNUIMessage({ type='toast', msg='Preset nicht gefunden: '..name, style='error' })
        cb({}); return
    end
    pushHistory(slot)
    local p = props[slot]
    p.offset   = { x=preset.offset.x,   y=preset.offset.y,   z=preset.offset.z }
    p.rotation = { x=preset.rotation.x, y=preset.rotation.y, z=preset.rotation.z }
    for _, b in ipairs(Config.Bones) do
        if b.id == preset.boneId then p.boneId = preset.boneId; p.bone = b.name; break end
    end
    if (not p.entity or not DoesEntityExist(p.entity)) and preset.prop and preset.prop ~= '' then
        CreateThread(function()
            local mdl = requestModel(preset.prop)
            if mdl then
                local ped    = PlayerPedId()
                local coords = GetEntityCoords(ped)
                local ent    = CreateObject(mdl, coords.x, coords.y, coords.z, false, false, false)
                SetEntityNoCollisionEntity(ent, ped, true)
                SetEntityAsMissionEntity(ent, true, true)
                SetModelAsNoLongerNeeded(mdl)
                p.entity = ent
                p.model  = preset.prop
                attachProp(slot)
                SendNUIMessage({ type='toast', msg='Preset "'..name..'" in Slot '..slot..' geladen', style='success' })
            end
        end)
    else
        attachProp(slot)
        SendNUIMessage({ type='toast', msg='Preset "'..name..'" in Slot '..slot..' geladen', style='success' })
    end
    cb({})
end)

RegisterNUICallback('saveEntry', function(data, cb)
    local name = (data.name or ''):gsub('%s+', '_'):lower()
    if name == '' then cb({}); return end
    local slot = (props[1].entity and DoesEntityExist(props[1].entity)) and 1 or 2
    local p    = props[slot]
    local all  = loadAttachments()
    all[name]  = {
        prop     = p.model,
        bone     = p.bone,
        boneId   = p.boneId,
        offset   = { x=p.offset.x,   y=p.offset.y,   z=p.offset.z },
        rotation = { x=p.rotation.x, y=p.rotation.y, z=p.rotation.z },
        animDict = currentAnim and currentAnim.dict or '',
        animClip = currentAnim and currentAnim.clip or '',
        notes    = data.notes or '',
    }
    saveAttachments(all)
    SendNUIMessage({ type='updatePresets', presets=all })
    cb({})
end)

RegisterNUICallback('exportLua', function(_, cb)
    generateExport()
    cb({})
end)

-- ─────────────────────────────────────────────
--  Numpad (Slot 1, works when UI is closed)
-- ─────────────────────────────────────────────

local STEP_LEVELS = { 0.001, 0.01, 0.1, 1.0 }
local stepIndex   = 2

local AXES = {
    off_yp  = { key='NUMPAD8',     fn=function(d) props[1].offset.y   = props[1].offset.y   + d end },
    off_yn  = { key='NUMPAD2',     fn=function(d) props[1].offset.y   = props[1].offset.y   - d end },
    off_xn  = { key='NUMPAD4',     fn=function(d) props[1].offset.x   = props[1].offset.x   - d end },
    off_xp  = { key='NUMPAD6',     fn=function(d) props[1].offset.x   = props[1].offset.x   + d end },
    off_zp  = { key='NUMPAD7',     fn=function(d) props[1].offset.z   = props[1].offset.z   + d end },
    off_zn  = { key='NUMPAD9',     fn=function(d) props[1].offset.z   = props[1].offset.z   - d end },
    rot_xp  = { key='NUMPAD1',     fn=function(d) props[1].rotation.x = props[1].rotation.x + d end },
    rot_xn  = { key='NUMPAD3',     fn=function(d) props[1].rotation.x = props[1].rotation.x - d end },
    rot_yp  = { key='NUMPAD0',     fn=function(d) props[1].rotation.y = props[1].rotation.y + d end },
    rot_yn  = { key='DECIMAL',     fn=function(d) props[1].rotation.y = props[1].rotation.y - d end },
    rot_zp  = { key='NUMPAD5',     fn=function(d) props[1].rotation.z = props[1].rotation.z + d end },
    rot_zn  = { key='NUMPADENTER', fn=function(d) props[1].rotation.z = props[1].rotation.z - d end },
}

local holdState = {}
for name in pairs(AXES) do holdState[name] = { pressed=false, holdTime=0 } end

local function accel(ms)
    if ms < 400  then return 1.0 end
    if ms < 1200 then return 1.0 + (ms-400)/800*4.0 end
    return 10.0
end

for name, axis in pairs(AXES) do
    lib.addKeybind({
        name='ptool_num_'..name, description='Prop Tool Num - '..name, defaultKey=axis.key,
        onPressed=function()
            if uiOpen or gizmoActive then return end
            if not (props[1].entity and DoesEntityExist(props[1].entity)) then return end
            holdState[name].pressed=true; holdState[name].holdTime=0
        end,
        onReleased=function() holdState[name].pressed=false; holdState[name].holdTime=0 end,
    })
end

lib.addKeybind({ name='ptool_step_up', description='Prop Tool - Schritt +', defaultKey='ADD',
    onPressed=function()
        if uiOpen or gizmoActive then return end
        stepIndex = math.min(#STEP_LEVELS, stepIndex+1)
        moveSpeed = STEP_LEVELS[stepIndex]
        lib.notify({ title='Prop Tool', description=string.format('Schritt: %.3f', moveSpeed), type='inform', duration=1200, position='top-right' })
    end })
lib.addKeybind({ name='ptool_step_down', description='Prop Tool - Schritt -', defaultKey='SUBTRACT',
    onPressed=function()
        if uiOpen or gizmoActive then return end
        stepIndex = math.max(1, stepIndex-1)
        moveSpeed = STEP_LEVELS[stepIndex]
        lib.notify({ title='Prop Tool', description=string.format('Schritt: %.3f', moveSpeed), type='inform', duration=1200, position='top-right' })
    end })

local lastFrame = GetGameTimer()
CreateThread(function()
    while true do
        if uiOpen or gizmoActive then
            Wait(100); lastFrame = GetGameTimer()
        else
            Wait(0)
            local now = GetGameTimer()
            local dt  = math.min(now - lastFrame, 100)
            lastFrame = now
            local changed = false
            for name, state in pairs(holdState) do
                if state.pressed then
                    state.holdTime = state.holdTime + dt
                    AXES[name].fn(moveSpeed * accel(state.holdTime) * (dt / 1000.0))
                    changed = true
                end
            end
            if changed then attachProp(1) end
        end
    end
end)

-- ─────────────────────────────────────────────
--  Commands
-- ─────────────────────────────────────────────

RegisterCommand(Config.Command, function(source, args)
    if Config.OnlyAdmins and not IsPlayerAceAllowed('player', 'd4rk_prop_tool.use') then
        lib.notify({ title='Prop Tool', description='Kein Zugriff.', type='error' })
        return
    end
    local sub = args[1]
    if not sub or sub == '' then
        if uiOpen then closeUI() else openUI() end
    elseif sub == 'stop' then
        stopAnim(); deleteProp(1); deleteProp(2); closeUI()
        lib.notify({ title='Prop Tool', description='Alles gestoppt.', type='inform' })
    elseif sub == 'export' then
        generateExport()
    elseif sub == 'list' then
        local data = loadAttachments()
        if not next(data) then print('[d4rk_prop_tool] Keine Eintraege.'); return end
        print('\n[d4rk_prop_tool] Eintraege:')
        for n, e in pairs(data) do print('  - '..n..' -> '..e.prop..' @ '..e.bone) end
        lib.notify({ title='Prop Tool', description='Eintraege in F8', type='inform' })
    end
end, false)

-- ─────────────────────────────────────────────
--  Cleanup
-- ─────────────────────────────────────────────

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    gizmoEnabled = false
    stopAnim()
    deleteProp(1); deleteProp(2)
    stopCamera()
    if uiOpen then SetNuiFocus(false, false); uiOpen = false end
    lib.hideTextUI()
end)

CreateThread(function()
    Wait(1000)
    print('[d4rk_prop_tool] v2.0 geladen. /'..Config.Command..' zum Oeffnen.')
end)