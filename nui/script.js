'use strict';

// ─── NUI Bridge ────────────────────────────────────────────────
function send(event, data) {
    const resourceName = GetParentResourceName ? GetParentResourceName() : 'd4rk_prop_tool';
    fetch('https://' + resourceName + '/' + event, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data || {})
    }).catch(err => {
        console.error('NUI Fetch failed for event:', event, 'Resource:', resourceName, err);
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

function holdRepeat(el, fn, startFn) {
    el.addEventListener('mousedown', () => {
        if (startFn) startFn();
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

// ─── Prop Search / Filter ──────────────────────────────────────
function filterPropSelect(slot, searchTerm) {
    const i   = slot - 1;
    const sel = document.getElementById('propSelect' + slot);
    const term = searchTerm.toLowerCase().trim();
    sel.innerHTML = '';
    propList.forEach((p, fullIdx) => {
        if (!term || p.toLowerCase().includes(term)) {
            const opt = document.createElement('option');
            opt.value = fullIdx;
            opt.textContent = p;
            sel.appendChild(opt);
        }
    });
    // Versuche bisherige Auswahl zu behalten
    sel.value = propIdx[i];
    if (sel.value === '' && sel.options.length > 0) {
        sel.selectedIndex = 0;
        propIdx[i] = parseInt(sel.options[0].value) || 0;
    }
}

document.getElementById('propSearch1').addEventListener('input', (e) => {
    filterPropSelect(1, e.target.value);
});
document.getElementById('propSearch2').addEventListener('input', (e) => {
    filterPropSelect(2, e.target.value);
});

// ─── Presets ───────────────────────────────────────────────────
let presetsOpen = true;

document.getElementById('presetsToggle').addEventListener('click', () => {
    presetsOpen = !presetsOpen;
    document.getElementById('presetsList').style.display = presetsOpen ? 'block' : 'none';
    document.getElementById('presetsArrow').textContent  = presetsOpen ? '▾' : '▸';
});

function fmtV(v) { return (v >= 0 ? '+' : '') + parseFloat(v).toFixed(4); }

function buildPresetList(presets) {
    const list = document.getElementById('presetsList');
    list.innerHTML = '';
    const keys = Object.keys(presets || {});
    if (keys.length === 0) {
        list.innerHTML = '<div class="preset-empty">Keine Eintraege gespeichert.</div>';
        return;
    }
    keys.sort().forEach((name) => {
        const e = presets[name];
        const wrap = document.createElement('div');
        wrap.className = 'preset-wrap';

        // ── Kopfzeile ──────────────────────────────────────────
        const row = document.createElement('div');
        row.className = 'preset-row';

        const info = document.createElement('div');
        info.className = 'preset-info';
        info.innerHTML = '<span class="preset-name">' + name + '</span>'
            + '<span class="preset-model">' + (e.prop || '?') + '</span>';

        const btns = document.createElement('div');
        btns.className = 'preset-btns';

        const bToggle = document.createElement('button');
        bToggle.className = 'btn btn-preset-toggle';
        bToggle.textContent = '▾';
        bToggle.title = 'Details anzeigen';

        const b1 = document.createElement('button');
        b1.className = 'btn btn-preset-load';
        b1.textContent = 'S1';
        b1.title = 'In Slot 1 laden';
        b1.addEventListener('click', () => send('loadPreset', { name, slot: 1 }));

        const b2 = document.createElement('button');
        b2.className = 'btn btn-preset-load';
        b2.textContent = 'S2';
        b2.title = 'In Slot 2 laden';
        b2.addEventListener('click', () => send('loadPreset', { name, slot: 2 }));

        btns.appendChild(bToggle);
        btns.appendChild(b1);
        btns.appendChild(b2);
        row.appendChild(info);
        row.appendChild(btns);

        // ── Detail-Block ───────────────────────────────────────
        const detail = document.createElement('div');
        detail.className = 'preset-detail';

        const o = e.offset   || {};
        const r = e.rotation || {};
        const hasAnim = e.animDict && e.animDict !== '';

        detail.innerHTML =
            '<div class="pd-row"><span class="pd-label">Bone</span><span class="pd-value">'
                + (e.bone || '?') + ' <span class="pd-id">(' + (e.boneId || '?') + ')</span></span></div>'
            + '<div class="pd-row"><span class="pd-label">Offset</span><span class="pd-value mono">'
                + 'X:' + fmtV(o.x||0) + '  Y:' + fmtV(o.y||0) + '  Z:' + fmtV(o.z||0) + '</span></div>'
            + '<div class="pd-row"><span class="pd-label">Rotation</span><span class="pd-value mono">'
                + 'X:' + fmtV(r.x||0) + '  Y:' + fmtV(r.y||0) + '  Z:' + fmtV(r.z||0) + '</span></div>'
            + (hasAnim
                ? '<div class="pd-row"><span class="pd-label">Anim</span><span class="pd-value mono anim-val">'
                    + e.animDict + '<br>' + e.animClip + '</span></div>'
                : '')
            + (e.notes
                ? '<div class="pd-row"><span class="pd-label">Notiz</span><span class="pd-value pd-notes">'
                    + e.notes + '</span></div>'
                : '');

        // Toggle
        bToggle.addEventListener('click', () => {
            const open = detail.classList.toggle('open');
            bToggle.textContent = open ? '▴' : '▾';
        });

        wrap.appendChild(row);
        wrap.appendChild(detail);
        list.appendChild(wrap);
    });
}

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
        propIdx  = [0, 0];
        document.getElementById('propSearch1').value = '';
        document.getElementById('propSearch2').value = '';
        filterPropSelect(1, '');
        filterPropSelect(2, '');

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

        // Presets
        buildPresetList(d.presets || {});
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

    if (d.type === 'updatePresets') {
        buildPresetList(d.presets || {});
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
        // Falls aktueller Wert nicht in gefilterter Liste: Filter leeren
        if (document.getElementById(selId).value === '') {
            document.getElementById('propSearch' + slot).value = '';
            filterPropSelect(slot, '');
            document.getElementById(selId).value = propIdx[i];
        }
    });

    document.getElementById(nextId).addEventListener('click', () => {
        if (!propList.length) return;
        propIdx[i] = (propIdx[i] + 1) % propList.length;
        document.getElementById(selId).value = propIdx[i];
        if (document.getElementById(selId).value === '') {
            document.getElementById('propSearch' + slot).value = '';
            filterPropSelect(slot, '');
            document.getElementById(selId).value = propIdx[i];
        }
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
        const slot   = parseInt(btn.dataset.slot);
        const i      = slot - 1;
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

// ─── Move / Rotate Buttons (hold-repeat + startMove fuer Undo) ─
document.querySelectorAll('.moveBtn, .rotBtn').forEach((btn) => {
    const slot = parseInt(btn.dataset.slot);
    const dir  = btn.dataset.dir;
    holdRepeat(
        btn,
        () => send('moveProp', { slot, dir }),
        () => send('startMove', { slot })
    );
});

// ─── Reset / Copy ──────────────────────────────────────────────
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

// ─── Undo / Redo ───────────────────────────────────────────────
document.querySelectorAll('.undoBtn').forEach((btn) => {
    btn.addEventListener('click', () => send('undo', { slot: parseInt(btn.dataset.slot) }));
});
document.querySelectorAll('.redoBtn').forEach((btn) => {
    btn.addEventListener('click', () => send('redo', { slot: parseInt(btn.dataset.slot) }));
});

// ─── Quick Copy (aktuelle Live-Werte) ──────────────────────────
document.querySelectorAll('.quickCopyBtn').forEach((btn) => {
    btn.addEventListener('click', () => send('quickCopy', { slot: parseInt(btn.dataset.slot) }));
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
