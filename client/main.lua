--[[
    d4rk_prop_tool - client/main.lua
    Prop Attachment & Animation Testing Tool
    Abhaengigkeiten: ox_lib
--]]

local dataview = require 'client.dataview'

-- ─────────────────────────────────────────────
--  Knochen-Lookup-Table
-- ─────────────────────────────────────────────
local BONES = {
    { name = 'SKEL_R_Hand',     id = 28422 },
    { name = 'SKEL_L_Hand',     id = 57005 },
    { name = 'SKEL_R_Forearm',  id = 61007 },
    { name = 'SKEL_L_Forearm',  id = 63931 },
    { name = 'SKEL_Spine2',     id = 24818 },
    { name = 'SKEL_R_UpperArm', id = 40269 },
    { name = 'SKEL_L_UpperArm', id = 45509 },
    { name = 'IK_R_Hand',       id = 36029 },
    { name = 'IK_L_Hand',       id = 65245 },
    { name = 'PH_R_Hand',       id = 26613 },
    { name = 'PH_L_Hand',       id = 18905 },
}

-- ─────────────────────────────────────────────
--  State
-- ─────────────────────────────────────────────
local currentProp = nil
local currentAnim = nil
local stepSize    = 0.01

local attachment = {
    prop     = '',
    bone     = 'SKEL_R_Hand',
    boneId   = 28422,
    offset   = { x = 0.0, y = 0.0, z = 0.0 },
    rotation = { x = 0.0, y = 0.0, z = 0.0 },
    animDict = '',
    animClip = '',
    notes    = '',
}

-- ─────────────────────────────────────────────
--  Hilfsfunktionen
-- ─────────────────────────────────────────────

local function getBoneId(boneName)
    for _, b in ipairs(BONES) do
        if b.name == boneName then return b.id end
    end
    return nil
end

-- Lokaler Cache der Attachments (wird vom Server geladen)
local cachedAttachments = {}

local function loadAttachments()
    return cachedAttachments
end

local function saveAttachments(data)
    cachedAttachments = data
    TriggerServerEvent('d4rk_prop_tool:saveAttachments', json.encode(data, { indent = true }))
end

-- Beim Laden des Scripts einmalig vom Server holen
AddEventHandler('d4rk_prop_tool:receiveAttachments', function(raw)
    local ok, data = pcall(json.decode, raw)
    cachedAttachments = ok and data or {}
end)

CreateThread(function()
    Wait(500)  -- kurz warten bis Server bereit
    TriggerServerEvent('d4rk_prop_tool:loadAttachments')
end)

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

local function removeProp()
    if currentProp and DoesEntityExist(currentProp) then
        DeleteEntity(currentProp)
    end
    currentProp = nil
end

local function stopAnim()
    if currentAnim then
        local ped = PlayerPedId()
        StopAnimTask(ped, currentAnim.dict, currentAnim.clip, 1.0)
        currentAnim = nil
    end
end

local function attachPropToPed()
    if not currentProp or not DoesEntityExist(currentProp) then return end
    local ped = PlayerPedId()
    AttachEntityToEntity(
        currentProp, ped,
        GetPedBoneIndex(ped, attachment.boneId),
        attachment.offset.x,   attachment.offset.y,   attachment.offset.z,
        attachment.rotation.x, attachment.rotation.y, attachment.rotation.z,
        true, true, false, true, 1, true
    )
end

-- ─────────────────────────────────────────────
--  Gizmo - DrawGizmo Native
--  Credits: Andyyy7666, AvarianKnight (aus M-PropV2)
-- ─────────────────────────────────────────────

local gizmoActive    = false
local gizmoEnabled   = false
local gizmoMode      = 'Translate'
local gizmoRelative  = false
local gizmoCursor    = false
local gizmoCancelled = false

local WHEEL_STEP = 0.05
local MIN_SCALE  = 0.05
local MAX_SCALE  = 50.0

local function _vecLen(x, y, z)
    return math.sqrt(x*x + y*y + z*z)
end

local function _normalize(x, y, z)
    local l = _vecLen(x, y, z)
    if l == 0 then return 0, 0, 0 end
    return x/l, y/l, z/l
end

local function _clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end

local function _uniformScale(entity)
    local f, r, u = GetEntityMatrix(entity)
    local s = (_vecLen(r[1],r[2],r[3]) + _vecLen(f[1],f[2],f[3]) + _vecLen(u[1],u[2],u[3])) / 3.0
    return s > 0.0 and s or 1.0
end

local function _makeMatrix(entity)
    local f, r, u, a = GetEntityMatrix(entity)
    local v = dataview.ArrayBuffer(64)
    v:SetFloat32(0,  r[1]):SetFloat32(4,  r[2]):SetFloat32(8,  r[3]):SetFloat32(12, 0)
     :SetFloat32(16, f[1]):SetFloat32(20, f[2]):SetFloat32(24, f[3]):SetFloat32(28, 0)
     :SetFloat32(32, u[1]):SetFloat32(36, u[2]):SetFloat32(40, u[3]):SetFloat32(44, 0)
     :SetFloat32(48, a[1]):SetFloat32(52, a[2]):SetFloat32(56, a[3]):SetFloat32(60, 1)
    return v
end

local function _applyMatrix(entity, v)
    local x1,y1,z1 = _normalize(v:GetFloat32(16), v:GetFloat32(20), v:GetFloat32(24))
    local x2,y2,z2 = _normalize(v:GetFloat32(0),  v:GetFloat32(4),  v:GetFloat32(8))
    local x3,y3,z3 = _normalize(v:GetFloat32(32), v:GetFloat32(36), v:GetFloat32(40))
    local tx,ty,tz = v:GetFloat32(48), v:GetFloat32(52), v:GetFloat32(56)
    SetEntityMatrix(entity, x1,y1,z1, x2,y2,z2, x3,y3,z3, tx,ty,tz)
end

local function _applyScale(v, s)
    local fnx,fny,fnz = _normalize(v:GetFloat32(16), v:GetFloat32(20), v:GetFloat32(24))
    local rnx,rny,rnz = _normalize(v:GetFloat32(0),  v:GetFloat32(4),  v:GetFloat32(8))
    local unx,uny,unz = _normalize(v:GetFloat32(32), v:GetFloat32(36), v:GetFloat32(40))
    v:SetFloat32(16, fnx*s):SetFloat32(20, fny*s):SetFloat32(24, fnz*s)
     :SetFloat32(0,  rnx*s):SetFloat32(4,  rny*s):SetFloat32(8,  rnz*s)
     :SetFloat32(32, unx*s):SetFloat32(36, uny*s):SetFloat32(40, unz*s)
end

local function computeAttachmentFromWorld()
    local ped     = PlayerPedId()
    local boneIdx = GetPedBoneIndex(ped, attachment.boneId)
    local bonePos = GetWorldPositionOfEntityBone(ped, boneIdx)
    local propPos = GetEntityCoords(currentProp)
    local propRot = GetEntityRotation(currentProp, 2)
    local dx = propPos.x - bonePos.x
    local dy = propPos.y - bonePos.y
    local dz = propPos.z - bonePos.z
    local pf, pr, pu = GetEntityMatrix(ped)
    attachment.offset.x = dx*pr[1] + dy*pr[2] + dz*pr[3]
    attachment.offset.y = dx*pf[1] + dy*pf[2] + dz*pf[3]
    attachment.offset.z = dx*pu[1] + dy*pu[2] + dz*pu[3]
    local pedRot = GetEntityRotation(ped, 2)
    attachment.rotation.x = propRot.x
    attachment.rotation.y = propRot.y
    attachment.rotation.z = propRot.z - pedRot.z
end

-- ─────────────────────────────────────────────
--  TextUI
-- ─────────────────────────────────────────────

local STEP_LEVELS = { 0.001, 0.01, 0.1, 1.0 }
local stepIndex   = 2

local function updateTextUI()
    if not currentProp then
        lib.hideTextUI()
        return
    end
    local stepLabels = { '0.001', '0.01', '0.1', '1.0' }
    local stepBar = ''
    for i, lbl in ipairs(stepLabels) do
        stepBar = stepBar .. (i == stepIndex and ('[' .. lbl .. ']') or lbl)
        if i < #stepLabels then stepBar = stepBar .. '  ' end
    end
    local gizmoLine
    if gizmoActive then
        gizmoLine = '────────────────────────────\n'
            .. 'GIZMO AKTIV - ' .. gizmoMode .. '\n'
            .. 'W=Move  R=Rotate  S=Scale  Q=Local/World\n'
            .. 'ENTER=Fertig  ESC=Abbruch'
    else
        gizmoLine = '────────────────────────────\n'
            .. '8/2=Y  4/6=X  7/9=Z\n'
            .. '1/3=rX  0/Num.=rY  5/Enter=rZ\n'
            .. 'Num+/-  Schritt  [/]  Schnellwahl  G=Gizmo'
    end
    lib.showTextUI(
        string.format(
            'd4rk Prop Tool  -  %s\n'
            .. '────────────────────────────\n'
            .. 'Offset  X:%+.4f  Y:%+.4f  Z:%+.4f\n'
            .. 'Rot     X:%+.4f  Y:%+.4f  Z:%+.4f\n'
            .. '%s',
            stepBar,
            attachment.offset.x,   attachment.offset.y,   attachment.offset.z,
            attachment.rotation.x, attachment.rotation.y, attachment.rotation.z,
            gizmoLine
        ),
        { position = 'top-left', icon = gizmoActive and 'arrow-pointer' or 'screwdriver-wrench' }
    )
end

-- ─────────────────────────────────────────────
--  Prop spawnen / Animation
-- ─────────────────────────────────────────────

local function spawnAndAttach()
    removeProp()
    local model = requestModel(attachment.prop)
    if not model then
        lib.notify({ title = 'Prop Tool', description = 'Ungueltiges Modell: ' .. attachment.prop, type = 'error' })
        return false
    end
    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)
    currentProp  = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)
    SetEntityNoCollisionEntity(currentProp, ped, true)
    SetEntityAsMissionEntity(currentProp, true, true)
    SetModelAsNoLongerNeeded(model)
    attachPropToPed()
    updateTextUI()
    lib.notify({ title = 'Prop Tool', description = 'Prop gespawnt: ' .. attachment.prop, type = 'success' })
    return true
end

local function playAnimation(dict, clip)
    local ped = PlayerPedId()
    if not requestAnimDict(dict) then
        lib.notify({ title = 'Prop Tool', description = 'AnimDict nicht gefunden: ' .. dict, type = 'error' })
        return false
    end
    stopAnim()
    TaskPlayAnim(ped, dict, clip, 8.0, -8.0, -1, 49, 0, false, false, false)
    currentAnim = { dict = dict, clip = clip }
    lib.notify({ title = 'Prop Tool', description = 'Anim: ' .. dict .. ' / ' .. clip, type = 'info' })
    return true
end

-- ─────────────────────────────────────────────
--  Echtzeit-Keybinds - Hold + Beschleunigung
-- ─────────────────────────────────────────────

local AXES = {
    off_yp  = { key = 'NUMPAD8',     desc = 'Offset Y +',   apply = function(d) attachment.offset.y   = attachment.offset.y   + d end },
    off_yn  = { key = 'NUMPAD2',     desc = 'Offset Y -',   apply = function(d) attachment.offset.y   = attachment.offset.y   - d end },
    off_xn  = { key = 'NUMPAD4',     desc = 'Offset X -',   apply = function(d) attachment.offset.x   = attachment.offset.x   - d end },
    off_xp  = { key = 'NUMPAD6',     desc = 'Offset X +',   apply = function(d) attachment.offset.x   = attachment.offset.x   + d end },
    off_zp  = { key = 'NUMPAD7',     desc = 'Offset Z +',   apply = function(d) attachment.offset.z   = attachment.offset.z   + d end },
    off_zn  = { key = 'NUMPAD9',     desc = 'Offset Z -',   apply = function(d) attachment.offset.z   = attachment.offset.z   - d end },
    rot_xp  = { key = 'NUMPAD1',     desc = 'Rotation X +', apply = function(d) attachment.rotation.x = attachment.rotation.x + d end },
    rot_xn  = { key = 'NUMPAD3',     desc = 'Rotation X -', apply = function(d) attachment.rotation.x = attachment.rotation.x - d end },
    rot_yp  = { key = 'NUMPAD0',     desc = 'Rotation Y +', apply = function(d) attachment.rotation.y = attachment.rotation.y + d end },
    rot_yn  = { key = 'DECIMAL',     desc = 'Rotation Y -', apply = function(d) attachment.rotation.y = attachment.rotation.y - d end },
    rot_zp  = { key = 'NUMPAD5',     desc = 'Rotation Z +', apply = function(d) attachment.rotation.z = attachment.rotation.z + d end },
    rot_zn  = { key = 'NUMPADENTER', desc = 'Rotation Z -', apply = function(d) attachment.rotation.z = attachment.rotation.z - d end },
}

local holdState = {}
for name in pairs(AXES) do
    holdState[name] = { pressed = false, holdTime = 0 }
end

local function accel(ms)
    if ms < 400  then return 1.0 end
    if ms < 1200 then return 1.0 + (ms - 400) / 800 * 4.0 end
    return 10.0
end

local function setStepIndex(idx)
    stepIndex = math.max(1, math.min(#STEP_LEVELS, idx))
    stepSize  = STEP_LEVELS[stepIndex]
    lib.notify({
        title       = 'Prop Tool',
        description = string.format('Schrittgroesse: %.3f', stepSize),
        type        = 'inform',
        duration    = 1200,
        position    = 'top-right',
    })
    updateTextUI()
end

for name, axis in pairs(AXES) do
    lib.addKeybind({
        name        = 'ptool_' .. name,
        description = 'Prop Tool - ' .. axis.desc,
        defaultKey  = axis.key,
        onPressed   = function()
            if not currentProp then return end
            holdState[name].pressed  = true
            holdState[name].holdTime = 0
        end,
        onReleased  = function()
            holdState[name].pressed  = false
            holdState[name].holdTime = 0
        end,
    })
end

lib.addKeybind({ name = 'ptool_step_up',     description = 'Prop Tool - Schrittgroesse +', defaultKey = 'ADD',      onPressed = function() setStepIndex(stepIndex + 1) end })
lib.addKeybind({ name = 'ptool_step_down',   description = 'Prop Tool - Schrittgroesse -', defaultKey = 'SUBTRACT', onPressed = function() setStepIndex(stepIndex - 1) end })
lib.addKeybind({ name = 'ptool_step_sm_alt', description = 'Prop Tool - Schritt 0.01',     defaultKey = 'LBRACKET', onPressed = function() stepIndex = 2; setStepIndex(stepIndex) end })
lib.addKeybind({ name = 'ptool_step_lg_alt', description = 'Prop Tool - Schritt 0.1',      defaultKey = 'RBRACKET', onPressed = function() stepIndex = 3; setStepIndex(stepIndex) end })

local lastFrameTime = GetGameTimer()
CreateThread(function()
    while true do
        if not currentProp then
            Wait(100)
            lastFrameTime = GetGameTimer()
        else
            Wait(0)
            local now = GetGameTimer()
            local dt  = math.min(now - lastFrameTime, 100)
            lastFrameTime = now
            local changed = false
            for name, state in pairs(holdState) do
                if state.pressed then
                    state.holdTime = state.holdTime + dt
                    AXES[name].apply(stepSize * accel(state.holdTime) * (dt / 1000.0))
                    changed = true
                end
            end
            if changed then
                attachPropToPed()
                updateTextUI()
            end
        end
    end
end)

-- ─────────────────────────────────────────────
--  Gizmo-Loop
-- ─────────────────────────────────────────────

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
                    .. 'Rot  %.1f  %.1f  %.1f\n'
                    .. 'Scale: %.2f\n'
                    .. 'W=Move  R=Rotate  S=Scale  Q=Local/World\n'
                    .. 'LALT=Snap  ENTER=Fertig  ESC=Abbruch',
                    gizmoMode,
                    gizmoRelative and 'Lokal' or 'Welt',
                    pos.x, pos.y, pos.z,
                    rot.x, rot.y, rot.z,
                    _uniformScale(entity)
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
                local target = _clamp(_uniformScale(entity) * (1.0 + (up and WHEEL_STEP or -WHEEL_STEP)), MIN_SCALE, MAX_SCALE)
                _applyScale(mat, target)
                _applyMatrix(entity, mat)
            end
        end

        if gizmoMode == 'Rotate' and IsControlPressed(0, 21) then
            local rot = GetEntityRotation(entity, 2)
            rot.z = math.floor((rot.z + 22.5) / 45) * 45
            SetEntityRotation(entity, rot.x, rot.y, rot.z, 2, true)
        end

        local changed = Citizen.InvokeNative(
            0xEB2EDCA2,
            mat:Buffer(),
            'PropTool_Gizmo',
            Citizen.ReturnResultAnyway()
        )

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

local function startGizmo()
    if not currentProp then
        lib.notify({ title = 'Prop Tool', description = 'Kein aktiver Prop.', type = 'error' })
        return
    end
    if gizmoActive then return end
    CreateThread(function()
        gizmoActive    = true
        gizmoEnabled   = true
        gizmoCancelled = false
        gizmoMode      = 'Translate'
        local savedOffset   = { x = attachment.offset.x,   y = attachment.offset.y,   z = attachment.offset.z }
        local savedRotation = { x = attachment.rotation.x, y = attachment.rotation.y, z = attachment.rotation.z }
        DetachEntity(currentProp, true, true)
        FreezeEntityPosition(currentProp, true)  -- verhindert Fallen nach Detach
        gizmoTextUILoop(currentProp)
        runGizmoLoop(currentProp)
        FreezeEntityPosition(currentProp, false)
        gizmoActive = false
        if gizmoCancelled then
            attachment.offset   = savedOffset
            attachment.rotation = savedRotation
            lib.notify({ title = 'Prop Tool', description = 'Gizmo abgebrochen.', type = 'error' })
        else
            computeAttachmentFromWorld()
            lib.notify({ title = 'Prop Tool', description = 'Gizmo fertig - Offset uebernommen.', type = 'success' })
        end
        attachPropToPed()
        updateTextUI()
    end)
end

lib.addKeybind({ name = 'ptool_gizmo_toggle',   description = 'Prop Tool - Gizmo ein/aus',        defaultKey = 'G',     onPressed  = function() startGizmo() end })
lib.addKeybind({ name = 'ptool_gizmoConfirm',   description = 'Prop Tool - Gizmo bestaetigen',    defaultKey = 'RETURN', onReleased = function() if gizmoEnabled then gizmoEnabled = false end end })
lib.addKeybind({ name = 'ptool_gizmoSnap',      description = 'Prop Tool - Gizmo Snap to Ground', defaultKey = 'LMENU', onPressed  = function() if gizmoEnabled then PlaceObjectOnGroundProperly_2(currentProp) end end })

lib.addKeybind({
    name = '_ptool_gizmoSelect', description = 'Prop Tool - Gizmo Auswahl',
    defaultMapper = 'MOUSE_BUTTON', defaultKey = 'MOUSE_LEFT',
    onPressed  = function() if gizmoEnabled then ExecuteCommand('+gizmoSelect') end end,
    onReleased = function() ExecuteCommand('-gizmoSelect') end,
})
lib.addKeybind({
    name = '_ptool_gizmoTranslate', description = 'Prop Tool - Gizmo Move', defaultKey = 'W',
    onPressed  = function() if gizmoEnabled then gizmoMode = 'Translate' ExecuteCommand('+gizmoTranslation') end end,
    onReleased = function() ExecuteCommand('-gizmoTranslation') end,
})
lib.addKeybind({
    name = '_ptool_gizmoRotate', description = 'Prop Tool - Gizmo Rotate', defaultKey = 'R',
    onPressed  = function() if gizmoEnabled then gizmoMode = 'Rotate' ExecuteCommand('+gizmoRotation') end end,
    onReleased = function() ExecuteCommand('-gizmoRotation') end,
})
lib.addKeybind({
    name = '_ptool_gizmoScale', description = 'Prop Tool - Gizmo Scale', defaultKey = 'S',
    onPressed  = function() if gizmoEnabled then gizmoMode = 'Scale' ExecuteCommand('+gizmoScale') end end,
    onReleased = function() ExecuteCommand('-gizmoScale') end,
})
lib.addKeybind({
    name = '_ptool_gizmoLocal', description = 'Prop Tool - Gizmo Local/World', defaultKey = 'Q',
    onPressed  = function() if gizmoEnabled then gizmoRelative = not gizmoRelative ExecuteCommand('+gizmoLocal') end end,
    onReleased = function() ExecuteCommand('-gizmoLocal') end,
})

-- ─────────────────────────────────────────────
--  Hauptmenu
-- ─────────────────────────────────────────────

local function openSavedMenu()
    local data        = loadAttachments()
    local menuOptions = {}

    for entryName, entry in pairs(data) do
        menuOptions[#menuOptions + 1] = {
            title       = entryName,
            description = entry.prop .. ' @ ' .. entry.bone,
            onSelect    = function()
                attachment.prop     = entry.prop
                attachment.bone     = entry.bone
                attachment.boneId   = entry.boneId
                attachment.offset   = { x = entry.offset.x,   y = entry.offset.y,   z = entry.offset.z }
                attachment.rotation = { x = entry.rotation.x, y = entry.rotation.y, z = entry.rotation.z }
                attachment.animDict = entry.animDict or ''
                attachment.animClip = entry.animClip or ''
                local spawned = spawnAndAttach()
                if spawned and attachment.animDict ~= '' then
                    playAnimation(attachment.animDict, attachment.animClip)
                end
            end,
            metadata = {
                { label = 'Prop',     value = entry.prop },
                { label = 'Knochen',  value = entry.bone },
                { label = 'AnimDict', value = entry.animDict or '-' },
                { label = 'AnimClip', value = entry.animClip or '-' },
                { label = 'Notes',    value = entry.notes    or '-' },
            },
            contextMenu = entryName .. '_ctx',
        }

        lib.registerContext({
            id      = entryName .. '_ctx',
            title   = entryName,
            options = {
                {
                    title    = 'Bearbeiten',
                    onSelect = function()
                        if not currentProp then
                            lib.notify({ title = 'Prop Tool', description = 'Kein Prop aktiv.', type = 'error' })
                            return
                        end
                        local inputData = lib.inputDialog('Eintrag bearbeiten: ' .. entryName, {
                            { type = 'input', label = 'Notiz', default = entry.notes or '' },
                        })
                        if not inputData then return end
                        data[entryName].notes    = inputData[1] or ''
                        data[entryName].offset   = { x = attachment.offset.x,   y = attachment.offset.y,   z = attachment.offset.z }
                        data[entryName].rotation = { x = attachment.rotation.x, y = attachment.rotation.y, z = attachment.rotation.z }
                        if currentAnim then
                            data[entryName].animDict = currentAnim.dict
                            data[entryName].animClip = currentAnim.clip
                        end
                        saveAttachments(data)
                        lib.notify({ title = 'Prop Tool', description = entryName .. ' gespeichert.', type = 'success' })
                    end,
                },
                {
                    title    = 'Loeschen',
                    onSelect = function()
                        data[entryName] = nil
                        saveAttachments(data)
                        lib.notify({ title = 'Prop Tool', description = entryName .. ' geloescht.', type = 'inform' })
                    end,
                },
            },
        })
    end

    if #menuOptions == 0 then
        menuOptions[#menuOptions + 1] = { title = 'Keine Eintraege vorhanden', disabled = true }
    end

    lib.registerContext({
        id      = 'ptool_saved_menu',
        title   = 'Gespeicherte Eintraege',
        menu    = 'ptool_main_menu',
        options = menuOptions,
    })
    lib.showContext('ptool_saved_menu')
end

local function openMainMenu()
    lib.registerContext({
        id      = 'ptool_main_menu',
        title   = 'd4rk Prop Tool',
        options = {
            {
                title       = 'Prop spawnen',
                description = 'Modell, Knochen und Offsets festlegen',
                onSelect    = function()
                    local input = lib.inputDialog('Prop spawnen', {
                        { type = 'input',  label = 'Prop Modell',  placeholder = 'prop_ld_jerrycan_01', required = true },
                        { type = 'select', label = 'Knochen', options = (function()
                            local opts = {}
                            for _, b in ipairs(BONES) do opts[#opts+1] = { label = b.name, value = b.name } end
                            return opts
                        end)() },
                        { type = 'number', label = 'Offset X',   default = 0.0 },
                        { type = 'number', label = 'Offset Y',   default = 0.0 },
                        { type = 'number', label = 'Offset Z',   default = 0.0 },
                        { type = 'number', label = 'Rotation X', default = 0.0 },
                        { type = 'number', label = 'Rotation Y', default = 0.0 },
                        { type = 'number', label = 'Rotation Z', default = 0.0 },
                    })
                    if not input then return end
                    local boneName = input[2] or 'SKEL_R_Hand'
                    attachment.prop        = input[1]
                    attachment.bone        = boneName
                    attachment.boneId      = getBoneId(boneName) or 28422
                    attachment.offset.x    = tonumber(input[3]) or 0.0
                    attachment.offset.y    = tonumber(input[4]) or 0.0
                    attachment.offset.z    = tonumber(input[5]) or 0.0
                    attachment.rotation.x  = tonumber(input[6]) or 0.0
                    attachment.rotation.y  = tonumber(input[7]) or 0.0
                    attachment.rotation.z  = tonumber(input[8]) or 0.0
                    spawnAndAttach()
                end,
            },
            {
                title       = 'Animation abspielen',
                description = 'AnimDict + AnimClip (geloopt)',
                onSelect    = function()
                    local input = lib.inputDialog('Animation abspielen', {
                        { type = 'input', label = 'AnimDict', required = true },
                        { type = 'input', label = 'AnimClip', required = true },
                    })
                    if not input then return end
                    attachment.animDict = input[1]
                    attachment.animClip = input[2]
                    playAnimation(attachment.animDict, attachment.animClip)
                end,
            },
            {
                title    = 'Animation stoppen',
                onSelect = function()
                    stopAnim()
                    lib.notify({ title = 'Prop Tool', description = 'Animation gestoppt.', type = 'inform' })
                end,
            },
            {
                title       = 'Aktuellen Stand speichern',
                description = 'Attachment einen Namen geben',
                onSelect    = function()
                    if not currentProp then
                        lib.notify({ title = 'Prop Tool', description = 'Kein aktiver Prop.', type = 'error' })
                        return
                    end
                    local input = lib.inputDialog('Eintrag speichern', {
                        { type = 'input', label = 'Name (z.B. jerrycan_pour)', required = true },
                        { type = 'input', label = 'Notiz (optional)' },
                    })
                    if not input or not input[1] or input[1] == '' then return end
                    local entryName = input[1]:gsub('%s+', '_'):lower()
                    local data = loadAttachments()
                    data[entryName] = {
                        prop     = attachment.prop,
                        bone     = attachment.bone,
                        boneId   = attachment.boneId,
                        offset   = { x = attachment.offset.x,   y = attachment.offset.y,   z = attachment.offset.z },
                        rotation = { x = attachment.rotation.x, y = attachment.rotation.y, z = attachment.rotation.z },
                        animDict = currentAnim and currentAnim.dict or attachment.animDict,
                        animClip = currentAnim and currentAnim.clip or attachment.animClip,
                        notes    = input[2] or '',
                    }
                    saveAttachments(data)
                    lib.notify({ title = 'Prop Tool', description = 'Gespeichert als ' .. entryName, type = 'success' })
                end,
            },
            {
                title    = 'Gespeicherte Eintraege',
                arrow    = true,
                onSelect = function() openSavedMenu() end,
            },
            {
                title    = 'Prop entfernen & stoppen',
                onSelect = function()
                    stopAnim(); removeProp(); lib.hideTextUI()
                    lib.notify({ title = 'Prop Tool', description = 'Prop entfernt.', type = 'inform' })
                end,
            },
        },
    })
    lib.showContext('ptool_main_menu')
end

-- ─────────────────────────────────────────────
--  Export-Generator
-- ─────────────────────────────────────────────

local function generateExport()
    local data = loadAttachments()
    if not next(data) then
        lib.notify({ title = 'Prop Tool', description = 'Keine Eintraege zum Exportieren.', type = 'error' })
        return
    end
    local lines = { '-- Generiert von d4rk_prop_tool', '-- ' .. os.date('%Y-%m-%d %H:%M:%S'), '', 'local ATTACHMENTS = {' }
    for name, e in pairs(data) do
        lines[#lines+1] = '    ' .. name .. ' = {'
        lines[#lines+1] = "        prop     = '" .. e.prop .. "',"
        lines[#lines+1] = '        bone     = ' .. e.boneId .. ',  -- ' .. e.bone
        lines[#lines+1] = string.format('        offset   = vector3(%.4f, %.4f, %.4f),', e.offset.x, e.offset.y, e.offset.z)
        lines[#lines+1] = string.format('        rotation = vector3(%.4f, %.4f, %.4f),', e.rotation.x, e.rotation.y, e.rotation.z)
        if e.animDict and e.animDict ~= '' then
            lines[#lines+1] = "        animDict = '" .. e.animDict .. "',"
            lines[#lines+1] = "        animClip = '" .. e.animClip .. "',"
        end
        if e.notes and e.notes ~= '' then lines[#lines+1] = '        -- ' .. e.notes end
        lines[#lines+1] = '    },'
    end
    lines[#lines+1] = '}'
    local output = table.concat(lines, '\n')
    print('\n' .. output .. '\n')
    TriggerServerEvent('d4rk_prop_tool:saveExport', output)
    lib.notify({ title = 'Prop Tool', description = 'Export gespeichert.', type = 'success', duration = 6000 })
end

-- ─────────────────────────────────────────────
--  Befehle
-- ─────────────────────────────────────────────

RegisterCommand('ptool', function(source, args)
    local sub = args[1]
    if not sub or sub == '' then
        openMainMenu()
    elseif sub == 'stop' then
        stopAnim(); removeProp(); lib.hideTextUI()
        lib.notify({ title = 'Prop Tool', description = 'Gestoppt.', type = 'inform' })
    elseif sub == 'stopanim' then
        stopAnim()
        lib.notify({ title = 'Prop Tool', description = 'Animation gestoppt.', type = 'inform' })
    elseif sub == 'export' then
        generateExport()
    elseif sub == 'list' then
        local data = loadAttachments()
        if not next(data) then print('[d4rk_prop_tool] Keine Eintraege.') return end
        print('\n[d4rk_prop_tool] Eintraege:')
        for name, entry in pairs(data) do
            print('  - ' .. name .. ' -> ' .. entry.prop .. ' @ ' .. entry.bone)
        end
        lib.notify({ title = 'Prop Tool', description = 'Eintraege in F8 ausgegeben.', type = 'inform' })
    else
        lib.notify({ title = 'Prop Tool', description = 'Unbekannter Befehl: ' .. sub, type = 'error' })
    end
end, false)

-- ─────────────────────────────────────────────
--  Cleanup
-- ─────────────────────────────────────────────

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    gizmoEnabled = false
    stopAnim()
    removeProp()
    lib.hideTextUI()
end)

CreateThread(function()
    Wait(1000)
    print('[d4rk_prop_tool] Geladen. /ptool zum Starten.')
end)