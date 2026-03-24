'use strict';

// ─── NUI Bridge ────────────────────────────────────────────────
function send(event, data) {
    fetch('https://' + GetParentResourceName() + '/' + event, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data || {})
    });
}

// ─── Toast ─────────────────────────────────────────────────────
const toastEl = document.getElementById('toast');
let toastTimer = null;

function showToast(msg, type) {
    if (toastTimer) clearTimeout(toastTimer);
    toastEl.textContent = msg;
    toastEl.className = 'toast ' + (type || 'info') + ' show';
    toastTimer = setTimeout(() => {
        toastEl.classList.remove('show');
    }, 2500);
}

// ─── Copy to clipboard ─────────────────────────────────────────
function copyText(text) {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.left = '-9999px';
    document.body.appendChild(ta);
    ta.select();
    try {
        document.execCommand('copy');
        showToast('In Zwischenablage kopiert!', 'success');
    } catch (e) {
        showToast('Kopieren fehlgeschlagen', 'error');
    }
    document.body.removeChild(ta);
}

// ─── Hold-to-repeat ────────────────────────────────────────────
let holdInterval = null;

function holdRepeat(el, fn) {
    el.addEventListener('mousedown', () => {
        fn();
        holdInterval = setInterval(fn, 60);
    });
    const stop = () => { if (holdInterval) { clearInterval(holdInterval); holdInterval = null; } };
    el.addEventListener('mouseup',    stop);
    el.addEventListener('mouseleave', stop);
}

// ─── State ─────────────────────────────────────────────────────
let propList  = [];
let propIdx   = [0, 0];
let animList  = [];
let animIdx   = 0;

// ─── Init UI from Lua ──────────────────────────────────────────
window.addEventListener('message', (e) => {
    const d = e.data;

    if (d.type === 'openUI') {
        document.getElementById('app').style.display = 'block';

        // Animations
        animList = d.animations || [];
        animIdx = 0;
        rebuildAnimSelect();

        // Bones
        buildBoneSelect('boneSelect1', d.bones || []);
        buildBoneSelect('boneSelect2', d.bones || []);

        // Props
        propList = d.props || [];
        propIdx = [0, 0];
        buildPropSelect('propSelect1', 0);
        buildPropSelect('propSelect2', 0);

        // Speeds
        const ms = d.moveSpeed || 0.01;
        const rs = d.rotateSpeed || 1.0;
        document.getElementById('moveSlider').value = ms;
        document.getElementById('moveVal').textContent = ms;
        document.getElementById('rotSlider').value = rs;
        document.getElementById('rotVal').textContent = rs;

        // Speed presets
        buildPresets('movePresets', d.moveSpeeds || [], (v) => {
            document.getElementById('moveSlider').value = v;
            document.getElementById('moveVal').textContent = v;
            send('updateMoveSpeed', { value: parseFloat(v) });
        });
        buildPresets('rotPresets', d.rotateSpeeds || [], (v) => {
            document.getElementById('rotSlider').value = v;
            document.getElementById('rotVal').textContent = v;
            send('updateRotateSpeed', { value: parseFloat(v) });
        });

        // Camera
        document.getElementById('camFocus').value  = d.camFocus    || 'ped';
        document.getElementById('camDist').value   = d.camDist     || 2.5;
        document.getElementById('camAngle').value  = d.camAngle    || 0;
        document.getElementById('camHeight').value = d.camHeight   || 0.5;
        document.getElementById('distVal').textContent   = d.camDist   || 2.5;
        document.getElementById('angleVal').textContent  = d.camAngle  || 0;
        document.getElementById('heightVal').textContent = d.camHeight || 0.5;
    }

    if (d.type === 'hideUI') {
        document.getElementById('app').style.display = 'none';
    }

    if (d.type === 'clipboard') {
        copyText(d.text);
    }

    if (d.type === 'updateValues') {
        if (d.prop1) updateLiveValues(1, d.prop1);
        if (d.prop2) updateLiveValues(2, d.prop2);
    }

    if (d.type === 'toast') {
        showToast(d.msg, d.style || 'info');
    }
});

function updateLiveValues(slot, p) {
    const o = p.offset;
    const r = p.rotation;
    document.getElementById('lv' + slot + 'off').textContent =
        'Off  X:' + fmt(o.x) + '  Y:' + fmt(o.y) + '  Z:' + fmt(o.z);
    document.getElementById('lv' + slot + 'rot').textContent =
        'Rot  X:' + fmtR(r.x) + '  Y:' + fmtR(r.y) + '  Z:' + fmtR(r.z);
}

function fmt(v)  { return (v >= 0 ? '+' : '') + v.toFixed(4); }
function fmtR(v) { return (v >= 0 ? '+' : '') + v.toFixed(2); }

// ─── Helpers ───────────────────────────────────────────────────
function rebuildAnimSelect() {
    const sel = document.getElementById('animSelect');
    sel.innerHTML = '';
    animList.forEach((a, i) => {
        const opt = document.createElement('option');
        opt.value = i;
        opt.textContent = a.label;
        sel.appendChild(opt);
    });
    if (animList.length > 0) sel.value = animIdx;
}

function buildPropSelect(id, idx) {
    const sel = document.getElementById(id);
    sel.innerHTML = '';
    propList.forEach((p, i) => {
        const opt = document.createElement('option');
        opt.value = i;
        opt.textContent = p;
        sel.appendChild(opt);
    });
    if (propList.length > 0) sel.value = idx;
}

function buildBoneSelect(id, bones) {
    const sel = document.getElementById(id);
    sel.innerHTML = '';
    bones.forEach((b) => {
        const opt = document.createElement('option');
        opt.value = b.id;
        opt.textContent = b.name + ' (' + b.id + ')';
        sel.appendChild(opt);
    });
    if (bones.length > 0) send('setBone', { slot: parseInt(id.slice(-1)), boneId: parseInt(sel.value) });
}

function buildPresets(containerId, values, onClick) {
    const cont = document.getElementById(containerId);
    cont.innerHTML = '';
    values.forEach((v) => {
        const btn = document.createElement('button');
        btn.className = 'btn-preset';
        btn.textContent = v;
        btn.addEventListener('click', () => onClick(v));
        cont.appendChild(btn);
    });
}

// ─── Animation Controls ────────────────────────────────────────
function playCurrentAnim() {
    const customDict = document.getElementById('customDict').value.trim();
    const customAnim = document.getElementById('customAnim').value.trim();
    const flags = parseInt(document.getElementById('animFlags').value) || 49;

    if (customDict && customAnim) {
        send('playAnim', { dict: customDict, anim: customAnim, flags });
        return;
    }
    if (animList.length === 0) return;
    const a = animList[animIdx];
    send('playAnim', { dict: a.dict, anim: a.anim, flags });
}

document.getElementById('animPrev').addEventListener('click', () => {
    if (!animList.length) return;
    animIdx = (animIdx - 1 + animList.length) % animList.length;
    document.getElementById('animSelect').value = animIdx;
    playCurrentAnim();
});

document.getElementById('animNext').addEventListener('click', () => {
    if (!animList.length) return;
    animIdx = (animIdx + 1) % animList.length;
    document.getElementById('animSelect').value = animIdx;
    playCurrentAnim();
});

document.getElementById('animSelect').addEventListener('change', (e) => {
    animIdx = parseInt(e.target.value) || 0;
    document.getElementById('customDict').value = '';
    document.getElementById('customAnim').value = '';
});

document.getElementById('btnPlayAnim').addEventListener('click', playCurrentAnim);
document.getElementById('btnStopAnim').addEventListener('click', () => send('stopAnim', {}));

document.querySelectorAll('.btn-flag').forEach((btn) => {
    btn.addEventListener('click', () => {
        document.getElementById('animFlags').value = btn.dataset.val;
        document.querySelectorAll('.btn-flag').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
    });
});

// ─── Speed Sliders ─────────────────────────────────────────────
document.getElementById('moveSlider').addEventListener('input', (e) => {
    document.getElementById('moveVal').textContent = e.target.value;
    send('updateMoveSpeed', { value: parseFloat(e.target.value) });
});

document.getElementById('rotSlider').addEventListener('input', (e) => {
    document.getElementById('rotVal').textContent = e.target.value;
    send('updateRotateSpeed', { value: parseFloat(e.target.value) });
});

// ─── Camera ────────────────────────────────────────────────────
function sendCam() {
    send('updateCamera', {
        dist:   parseFloat(document.getElementById('camDist').value),
        angle:  parseFloat(document.getElementById('camAngle').value),
        height: parseFloat(document.getElementById('camHeight').value),
    });
}

document.getElementById('camFocus').addEventListener('change', (e) => {
    send('updateCameraFocus', { focus: e.target.value });
});

document.getElementById('camDist').addEventListener('input', (e) => {
    document.getElementById('distVal').textContent = e.target.value;
    sendCam();
});

document.getElementById('camAngle').addEventListener('input', (e) => {
    document.getElementById('angleVal').textContent = e.target.value;
    sendCam();
});

document.getElementById('camHeight').addEventListener('input', (e) => {
    document.getElementById('heightVal').textContent = e.target.value;
    sendCam();
});

document.querySelectorAll('.btn-nudge').forEach((btn) => {
    btn.addEventListener('click', () => {
        const axis = btn.dataset.axis;
        const amt  = parseFloat(btn.dataset.amt);
        const slider = { dist: 'camDist', angle: 'camAngle', height: 'camHeight' }[axis];
        const span   = { dist: 'distVal', angle: 'angleVal', height: 'heightVal' }[axis];
        const el = document.getElementById(slider);
        const newVal = Math.min(parseFloat(el.max), Math.max(parseFloat(el.min), parseFloat(el.value) + amt));
        el.value = newVal;
        document.getElementById(span).textContent = newVal.toFixed(axis === 'angle' ? 0 : 1);
        sendCam();
    });
});

// ─── Prop Selects ──────────────────────────────────────────────
function setupPropNav(slot) {
    const i = slot - 1;
    const selId = 'propSelect' + slot;
    const prevId = 'p' + slot + 'Prev';
    const nextId = 'p' + slot + 'Next';

    document.getElementById(prevId).addEventListener('click', () => {
        if (!propList.length) return;
        propIdx[i] = (propIdx[i] - 1 + propList.length) % propList.length;
        document.getElementById(selId).value = propIdx[i];
    });

    document.getElementById(nextId).addEventListener('click', () => {
        if (!propList.length) return;
        propIdx[i] = (propIdx[i] + 1) % propList.length;
        document.getElementById(selId).value = propIdx[i];
    });

    document.getElementById(selId).addEventListener('change', (e) => {
        propIdx[i] = parseInt(e.target.value) || 0;
    });
}

setupPropNav(1);
setupPropNav(2);

// ─── Spawn / Delete ────────────────────────────────────────────
document.querySelectorAll('.spawnBtn').forEach((btn) => {
    btn.addEventListener('click', () => {
        const slot = parseInt(btn.dataset.slot);
        const i    = slot - 1;
        const custom = document.getElementById('customProp' + slot).value.trim();
        const model  = custom || propList[propIdx[i]] || '';
        if (!model) return showToast('Kein Modell ausgewaehlt', 'error');
        send('spawnProp', { slot, model });
    });
});

document.querySelectorAll('.deleteBtn').forEach((btn) => {
    btn.addEventListener('click', () => {
        send('deleteProp', { slot: parseInt(btn.dataset.slot) });
    });
});

// ─── Bone / Rotation Order ─────────────────────────────────────
document.getElementById('boneSelect1').addEventListener('change', (e) => {
    document.getElementById('customBone1').value = '';
    send('setBone', { slot: 1, boneId: parseInt(e.target.value) });
});
document.getElementById('boneSelect2').addEventListener('change', (e) => {
    document.getElementById('customBone2').value = '';
    send('setBone', { slot: 2, boneId: parseInt(e.target.value) });
});
document.getElementById('customBone1').addEventListener('change', (e) => {
    const id = parseInt(e.target.value);
    if (id) send('setBone', { slot: 1, boneId: id });
});
document.getElementById('customBone2').addEventListener('change', (e) => {
    const id = parseInt(e.target.value);
    if (id) send('setBone', { slot: 2, boneId: id });
});
document.getElementById('rotOrder1').addEventListener('change', (e) => {
    send('setRotOrder', { slot: 1, order: parseInt(e.target.value) });
});
document.getElementById('rotOrder2').addEventListener('change', (e) => {
    send('setRotOrder', { slot: 2, order: parseInt(e.target.value) });
});

// ─── Move / Rotate Buttons (hold-repeat) ──────────────────────
document.querySelectorAll('.moveBtn, .rotBtn').forEach((btn) => {
    holdRepeat(btn, () => {
        send('moveProp', {
            slot: parseInt(btn.dataset.slot),
            dir:  btn.dataset.dir,
        });
    });
});

// ─── Gizmo / Reset / Copy ──────────────────────────────────────
document.querySelectorAll('.gizmoBtn').forEach((btn) => {
    btn.addEventListener('click', () => {
        send('startGizmo', { slot: parseInt(btn.dataset.slot) });
    });
});

document.querySelectorAll('.resetBtn').forEach((btn) => {
    btn.addEventListener('click', () => {
        send('resetProp', { slot: parseInt(btn.dataset.slot) });
    });
});

document.querySelectorAll('.copyBtn').forEach((btn) => {
    btn.addEventListener('click', () => {
        const slot = parseInt(btn.dataset.slot);
        const fmt  = document.getElementById('fmt' + slot).value;
        send('copyData', { slot, format: fmt });
    });
});

// ─── Save / Export / Reset All ─────────────────────────────────
document.getElementById('btnSave').addEventListener('click', () => {
    const name  = document.getElementById('saveName').value.trim();
    const notes = document.getElementById('saveNotes').value.trim();
    if (!name) { showToast('Name eingeben!', 'error'); return; }
    send('saveEntry', { name, notes });
    document.getElementById('saveName').value  = '';
    document.getElementById('saveNotes').value = '';
    showToast('Gespeichert: ' + name, 'success');
});

document.getElementById('btnExport').addEventListener('click', () => {
    send('exportLua', {});
    showToast('Export in F8 + output/export.lua', 'info');
});

document.getElementById('btnResetAll').addEventListener('click', () => {
    send('resetAll', {});
    showToast('Alles zurueckgesetzt', 'info');
});

// ─── Close ─────────────────────────────────────────────────────
document.getElementById('btnClose').addEventListener('click', () => {
    document.getElementById('app').style.display = 'none';
    send('closeUI', {});
});

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        document.getElementById('app').style.display = 'none';
        send('closeUI', {});
    }
});