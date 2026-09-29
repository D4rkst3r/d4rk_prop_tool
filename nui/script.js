'use strict';

// ─── NUI Bridge ────────────────────────────────────────────────
function send(event, data) {
    if (typeof GetParentResourceName !== 'function') return Promise.resolve();
    return fetch('https://' + GetParentResourceName() + '/' + event, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data || {})
    }).catch(err => {
        console.error('NUI fetch failed for event:', event, err);
    });
}

const $ = (id) => document.getElementById(id);

// ─── i18n ──────────────────────────────────────────────────────
let L = {};

function t(key, ...args) {
    let s = L[key];
    if (s === undefined) return key;
    let i = 0;
    return s.replace(/%[sd]/g, () => (args[i++] ?? ''));
}

function applyLocale() {
    document.querySelectorAll('[data-i18n]').forEach((el) => {
        const v = L[el.dataset.i18n];
        if (v !== undefined) el.textContent = v;
    });
    document.querySelectorAll('[data-i18n-ph]').forEach((el) => {
        const v = L[el.dataset.i18nPh];
        if (v !== undefined) el.placeholder = v;
    });
    document.querySelectorAll('[data-i18n-title]').forEach((el) => {
        const v = L[el.dataset.i18nTitle];
        if (v !== undefined) el.title = v;
    });
}

// ─── Toast ─────────────────────────────────────────────────────
const toastEl = $('toast');
let toastTimer = null;

function showToast(msg, type) {
    if (toastTimer) clearTimeout(toastTimer);
    toastEl.textContent = msg;
    toastEl.className = 'toast ' + (type || 'info') + ' show';
    toastTimer = setTimeout(() => toastEl.classList.remove('show'), 2500);
}

// ─── Confirm Modal ─────────────────────────────────────────────
const modalEl = $('modal');
let modalResolve = null;

function confirmDialog(text) {
    $('modalText').textContent = text;
    modalEl.classList.add('open');
    return new Promise((resolve) => { modalResolve = resolve; });
}

function closeModal(result) {
    modalEl.classList.remove('open');
    if (modalResolve) { modalResolve(result); modalResolve = null; }
}

$('modalOk').addEventListener('click', () => closeModal(true));
// d4rk RP: Werte beider Plaetze in den Animationskatalog schreiben
$('btnKatalog').addEventListener('click', () => send('katalogSpeichern', {}));
$('modalCancel').addEventListener('click', () => closeModal(false));
modalEl.addEventListener('click', (e) => { if (e.target === modalEl) closeModal(false); });

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
        showToast(t('ui_copied'), 'success');
    } catch (e) {
        showToast(t('ui_copy_failed'), 'error');
    }
    document.body.removeChild(ta);
}

// ─── Hold-to-repeat ────────────────────────────────────────────
let holdInterval = null;

function stopHold() {
    if (holdInterval) { clearInterval(holdInterval); holdInterval = null; }
}

// Global, damit ein Mouseup ausserhalb des Buttons die Wiederholung stoppt.
document.addEventListener('mouseup', stopHold);
window.addEventListener('blur', stopHold);

function holdRepeat(el, fn, startFn) {
    el.addEventListener('mousedown', () => {
        stopHold();
        if (startFn) startFn();
        fn();
        holdInterval = setInterval(fn, 60);
    });
    el.addEventListener('mouseleave', stopHold);
}

// ─── State ─────────────────────────────────────────────────────
let propList = [];
let propIdx  = [0, 0];
let animList = [];
let animIdx  = 0;
let presets  = {};
let canWrite = false;

// ─── Prop Search / Filter ──────────────────────────────────────
function filterPropSelect(slot, searchTerm) {
    const i    = slot - 1;
    const sel  = $('propSelect' + slot);
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
    sel.value = propIdx[i];
    if (sel.value === '' && sel.options.length > 0) {
        sel.selectedIndex = 0;
        propIdx[i] = parseInt(sel.options[0].value) || 0;
    }
}

$('propSearch1').addEventListener('input', (e) => filterPropSelect(1, e.target.value));
$('propSearch2').addEventListener('input', (e) => filterPropSelect(2, e.target.value));

// ─── Presets ───────────────────────────────────────────────────
let presetsOpen = true;

$('presetsToggle').addEventListener('click', () => {
    presetsOpen = !presetsOpen;
    $('presetsList').style.display = presetsOpen ? 'block' : 'none';
    $('presetsArrow').textContent  = presetsOpen ? '▾' : '▸';
});

function fmtV(v) {
    const n = parseFloat(v) || 0;
    return (n >= 0 ? '+' : '') + n.toFixed(4);
}

/** Baut eine Detailzeile ohne innerHTML - Preset-Inhalte sind Fremddaten. */
function detailRow(label, valueNode, valueClass) {
    const row = document.createElement('div');
    row.className = 'pd-row';

    const lbl = document.createElement('span');
    lbl.className = 'pd-label';
    lbl.textContent = label;

    const val = document.createElement('span');
    val.className = 'pd-value' + (valueClass ? ' ' + valueClass : '');
    if (typeof valueNode === 'string') {
        val.textContent = valueNode;
    } else {
        val.appendChild(valueNode);
    }

    row.appendChild(lbl);
    row.appendChild(val);
    return row;
}

function buildPresetList(data) {
    presets = data || {};
    const list = $('presetsList');
    list.innerHTML = '';

    const keys = Object.keys(presets);
    if (keys.length === 0) {
        const empty = document.createElement('div');
        empty.className = 'preset-empty';
        empty.textContent = t('ui_no_presets');
        list.appendChild(empty);
        return;
    }

    keys.sort().forEach((name) => {
        const e = presets[name] || {};
        const wrap = document.createElement('div');
        wrap.className = 'preset-wrap';

        // ── Kopfzeile ──────────────────────────────────────────
        const row = document.createElement('div');
        row.className = 'preset-row';

        const info = document.createElement('div');
        info.className = 'preset-info';

        const nameEl = document.createElement('span');
        nameEl.className = 'preset-name';
        nameEl.textContent = name;

        const modelEl = document.createElement('span');
        modelEl.className = 'preset-model';
        modelEl.textContent = e.prop || '?';

        info.appendChild(nameEl);
        info.appendChild(modelEl);

        const btns = document.createElement('div');
        btns.className = 'preset-btns';

        const bToggle = document.createElement('button');
        bToggle.className = 'btn btn-preset-toggle';
        bToggle.textContent = '▾';
        bToggle.title = t('ui_details');

        const b1 = document.createElement('button');
        b1.className = 'btn btn-preset-load';
        b1.textContent = 'S1';
        b1.title = t('ui_load_slot', '1');
        b1.addEventListener('click', () => send('loadPreset', { name, slot: 1 }));

        const b2 = document.createElement('button');
        b2.className = 'btn btn-preset-load';
        b2.textContent = 'S2';
        b2.title = t('ui_load_slot', '2');
        b2.addEventListener('click', () => send('loadPreset', { name, slot: 2 }));

        const bDel = document.createElement('button');
        bDel.className = 'btn btn-preset-del';
        bDel.textContent = '✕';
        bDel.title = t('ui_delete_preset');
        bDel.disabled = !canWrite;
        bDel.addEventListener('click', async () => {
            if (await confirmDialog(t('ui_confirm_delete', name))) {
                send('deletePreset', { name });
            }
        });

        btns.appendChild(bToggle);
        btns.appendChild(b1);
        btns.appendChild(b2);
        btns.appendChild(bDel);
        row.appendChild(info);
        row.appendChild(btns);

        // ── Detail-Block ───────────────────────────────────────
        const detail = document.createElement('div');
        detail.className = 'preset-detail';

        const o = e.offset   || {};
        const r = e.rotation || {};

        const boneVal = document.createElement('span');
        boneVal.textContent = (e.bone || '?') + ' (' + (e.boneId ?? '?') + ')';
        detail.appendChild(detailRow(t('ui_lbl_bone'), boneVal));

        detail.appendChild(detailRow(t('ui_lbl_offset'),
            'X:' + fmtV(o.x) + '  Y:' + fmtV(o.y) + '  Z:' + fmtV(o.z), 'mono'));
        detail.appendChild(detailRow(t('ui_lbl_rotation'),
            'X:' + fmtV(r.x) + '  Y:' + fmtV(r.y) + '  Z:' + fmtV(r.z), 'mono'));

        if (e.animDict) {
            const anim = document.createElement('span');
            anim.textContent = e.animDict;
            anim.appendChild(document.createElement('br'));
            anim.appendChild(document.createTextNode(e.animClip || ''));
            detail.appendChild(detailRow(t('ui_lbl_anim'), anim, 'mono anim-val'));
        }
        if (e.notes) {
            detail.appendChild(detailRow(t('ui_lbl_note'), e.notes, 'pd-notes'));
        }

        bToggle.addEventListener('click', () => {
            const open = detail.classList.toggle('open');
            bToggle.textContent = open ? '▴' : '▾';
        });

        wrap.appendChild(row);
        wrap.appendChild(detail);
        list.appendChild(wrap);
    });
}

// ─── Messages von Lua ──────────────────────────────────────────
window.addEventListener('message', (e) => {
    const d = e.data;

    switch (d.type) {
        case 'openUI': {
            L = d.locale || {};
            applyLocale();

            canWrite = d.canWrite === true;
            $('btnSave').disabled   = !canWrite;
            $('btnExport').disabled = !canWrite;

            animList = d.animations || [];
            animIdx  = 0;
            rebuildAnimSelect();

            buildBoneSelect('boneSelect1', d.bones || []);
            buildBoneSelect('boneSelect2', d.bones || []);

            propList = d.props || [];
            propIdx  = [0, 0];
            $('propSearch1').value = '';
            $('propSearch2').value = '';
            filterPropSelect(1, '');
            filterPropSelect(2, '');

            applySpeeds(d.moveSpeed, d.rotateSpeed);

            buildSpeedPresets('movePresets', d.moveSpeeds || [], (v) => {
                $('moveSlider').value = v;
                $('moveVal').textContent = v;
                send('updateMoveSpeed', { value: parseFloat(v) });
            });
            buildSpeedPresets('rotPresets', d.rotateSpeeds || [], (v) => {
                $('rotSlider').value = v;
                $('rotVal').textContent = v;
                send('updateRotateSpeed', { value: parseFloat(v) });
            });

            applyCamera(d);

            // Slot-Zustand aus Lua uebernehmen (Bone / RotOrder)
            const slots = d.slots || {};
            [1, 2].forEach((s) => { if (slots[s]) applySlot(s, slots[s]); });

            buildPresetList(d.presets || {});
            $('app').style.display = 'block';
            break;
        }

        case 'hideUI':
            $('app').style.display = 'none';
            $('katalogBox').style.display = 'none';
            closeModal(false);
            break;

        // d4rk RP: ein Katalogeintrag wird eingestellt
        case 'katalog':
            $('katalogBox').style.display = '';
            $('katalogName').textContent = d.label || d.key || '';
            if (d.dict) $('customDict').value = d.dict;
            if (d.clip) $('customAnim').value = d.clip;
            if (d.flags !== undefined) $('animFlags').value = d.flags;
            break;

        case 'clipboard':
            copyText(d.text);
            break;

        case 'updateValues':
            if (d.prop1) updateLiveValues(1, d.prop1);
            if (d.prop2) updateLiveValues(2, d.prop2);
            break;

        case 'toast':
            showToast(d.msg, d.style || 'info');
            break;

        case 'updatePresets':
            buildPresetList(d.presets || {});
            break;

        case 'syncSlot':
            applySlot(d.slot, d);
            break;

        case 'syncCamera':
            applyCamera({
                camDist: d.dist, camAngle: d.angle, camHeight: d.height, camFocus: d.focus
            });
            break;

        case 'syncSpeeds':
            applySpeeds(d.moveSpeed, d.rotateSpeed);
            break;
    }
});

function applySlot(slot, state) {
    if (slot !== 1 && slot !== 2) return;
    const bone = $('boneSelect' + slot);
    if (state.boneId !== undefined) {
        bone.value = state.boneId;
        // Bone-ID nicht in der Liste -> Custom-Feld fuehren
        $('customBone' + slot).value = (bone.value === '') ? state.boneId : '';
    }
    if (state.rotOrder !== undefined) $('rotOrder' + slot).value = state.rotOrder;
}

function applyCamera(d) {
    if (d.camFocus  !== undefined) $('camFocus').value  = d.camFocus;
    if (d.camDist   !== undefined) { $('camDist').value   = d.camDist;   $('distVal').textContent   = d.camDist; }
    if (d.camAngle  !== undefined) { $('camAngle').value  = d.camAngle;  $('angleVal').textContent  = d.camAngle; }
    if (d.camHeight !== undefined) { $('camHeight').value = d.camHeight; $('heightVal').textContent = d.camHeight; }
}

function applySpeeds(move, rot) {
    if (move !== undefined) { $('moveSlider').value = move; $('moveVal').textContent = move; }
    if (rot  !== undefined) { $('rotSlider').value  = rot;  $('rotVal').textContent  = rot; }
}

function updateLiveValues(slot, p) {
    const o = p.offset, r = p.rotation;
    $('lv' + slot + 'off').textContent = 'Off  X:' + fmt(o.x) + '  Y:' + fmt(o.y) + '  Z:' + fmt(o.z);
    $('lv' + slot + 'rot').textContent = 'Rot  X:' + fmtR(r.x) + '  Y:' + fmtR(r.y) + '  Z:' + fmtR(r.z);
}

function fmt(v)  { return (v >= 0 ? '+' : '') + v.toFixed(4); }
function fmtR(v) { return (v >= 0 ? '+' : '') + v.toFixed(2); }

// ─── Helpers ───────────────────────────────────────────────────
function rebuildAnimSelect() {
    const sel = $('animSelect');
    sel.innerHTML = '';
    animList.forEach((a, i) => {
        const opt = document.createElement('option');
        opt.value = i;
        opt.textContent = a.label;
        sel.appendChild(opt);
    });
    if (animList.length > 0) sel.value = animIdx;
}

function buildBoneSelect(id, bones) {
    const sel = $(id);
    sel.innerHTML = '';
    bones.forEach((b) => {
        const opt = document.createElement('option');
        opt.value = b.id;
        opt.textContent = b.name + ' (' + b.id + ')';
        sel.appendChild(opt);
    });
}

function buildSpeedPresets(containerId, values, onClick) {
    const cont = $(containerId);
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
    const customDict = $('customDict').value.trim();
    const customAnim = $('customAnim').value.trim();
    const flags = parseInt($('animFlags').value) || 49;

    if (customDict && customAnim) {
        send('playAnim', { dict: customDict, anim: customAnim, flags });
        return;
    }
    if (animList.length === 0) return;
    const a = animList[animIdx];
    send('playAnim', { dict: a.dict, anim: a.anim, flags });
}

$('animPrev').addEventListener('click', () => {
    if (!animList.length) return;
    animIdx = (animIdx - 1 + animList.length) % animList.length;
    $('animSelect').value = animIdx;
    playCurrentAnim();
});

$('animNext').addEventListener('click', () => {
    if (!animList.length) return;
    animIdx = (animIdx + 1) % animList.length;
    $('animSelect').value = animIdx;
    playCurrentAnim();
});

$('animSelect').addEventListener('change', (e) => {
    animIdx = parseInt(e.target.value) || 0;
    $('customDict').value = '';
    $('customAnim').value = '';
});

$('btnPlayAnim').addEventListener('click', playCurrentAnim);
$('btnStopAnim').addEventListener('click', () => send('stopAnim', {}));

document.querySelectorAll('.btn-flag').forEach((btn) => {
    btn.addEventListener('click', () => {
        $('animFlags').value = btn.dataset.val;
        document.querySelectorAll('.btn-flag').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
    });
});

// ─── Speed Sliders ─────────────────────────────────────────────
$('moveSlider').addEventListener('input', (e) => {
    $('moveVal').textContent = e.target.value;
    send('updateMoveSpeed', { value: parseFloat(e.target.value) });
});

$('rotSlider').addEventListener('input', (e) => {
    $('rotVal').textContent = e.target.value;
    send('updateRotateSpeed', { value: parseFloat(e.target.value) });
});

// ─── Camera ────────────────────────────────────────────────────
function sendCam() {
    send('updateCamera', {
        dist:   parseFloat($('camDist').value),
        angle:  parseFloat($('camAngle').value),
        height: parseFloat($('camHeight').value),
    });
}

$('camFocus').addEventListener('change', (e) => send('updateCameraFocus', { focus: e.target.value }));

$('camDist').addEventListener('input', (e) => { $('distVal').textContent = e.target.value; sendCam(); });
$('camAngle').addEventListener('input', (e) => { $('angleVal').textContent = e.target.value; sendCam(); });
$('camHeight').addEventListener('input', (e) => { $('heightVal').textContent = e.target.value; sendCam(); });

document.querySelectorAll('.btn-nudge').forEach((btn) => {
    btn.addEventListener('click', () => {
        const axis = btn.dataset.axis;
        const amt  = parseFloat(btn.dataset.amt);
        const el   = $({ dist: 'camDist', angle: 'camAngle', height: 'camHeight' }[axis]);
        const span = $({ dist: 'distVal', angle: 'angleVal', height: 'heightVal' }[axis]);
        const newVal = Math.min(parseFloat(el.max), Math.max(parseFloat(el.min), parseFloat(el.value) + amt));
        el.value = newVal;
        span.textContent = newVal.toFixed(axis === 'angle' ? 0 : 1);
        sendCam();
    });
});

// ─── Prop Selects ──────────────────────────────────────────────
function setupPropNav(slot) {
    const i   = slot - 1;
    const sel = $('propSelect' + slot);

    const step = (delta) => {
        if (!propList.length) return;
        propIdx[i] = (propIdx[i] + delta + propList.length) % propList.length;
        sel.value = propIdx[i];
        // Wert nicht in der gefilterten Liste -> Filter leeren
        if (sel.value === '') {
            $('propSearch' + slot).value = '';
            filterPropSelect(slot, '');
            sel.value = propIdx[i];
        }
    };

    $('p' + slot + 'Prev').addEventListener('click', () => step(-1));
    $('p' + slot + 'Next').addEventListener('click', () => step(1));
    sel.addEventListener('change', (e) => { propIdx[i] = parseInt(e.target.value) || 0; });
}

setupPropNav(1);
setupPropNav(2);

// ─── Spawn / Delete ────────────────────────────────────────────
document.querySelectorAll('.spawnBtn').forEach((btn) => {
    btn.addEventListener('click', () => {
        const slot   = parseInt(btn.dataset.slot);
        const custom = $('customProp' + slot).value.trim();
        const model  = custom || propList[propIdx[slot - 1]] || '';
        if (!model) return showToast(t('ui_no_model'), 'error');
        send('spawnProp', { slot, model });
    });
});

document.querySelectorAll('.deleteBtn').forEach((btn) => {
    btn.addEventListener('click', () => send('deleteProp', { slot: parseInt(btn.dataset.slot) }));
});

// ─── Bone / Rotation Order ─────────────────────────────────────
[1, 2].forEach((slot) => {
    $('boneSelect' + slot).addEventListener('change', (e) => {
        $('customBone' + slot).value = '';
        send('setBone', { slot, boneId: parseInt(e.target.value) });
    });
    $('customBone' + slot).addEventListener('change', (e) => {
        const id = parseInt(e.target.value);
        if (Number.isFinite(id)) send('setBone', { slot, boneId: id });
    });
    $('rotOrder' + slot).addEventListener('change', (e) => {
        send('setRotOrder', { slot, order: parseInt(e.target.value) });
    });
});

// ─── Move / Rotate Buttons (hold-repeat + startMove fuer Undo) ─
document.querySelectorAll('.moveBtn, .rotBtn').forEach((btn) => {
    const slot = parseInt(btn.dataset.slot);
    const dir  = btn.dataset.dir;
    holdRepeat(btn, () => send('moveProp', { slot, dir }), () => send('startMove', { slot }));
});

// ─── Reset / Copy / Undo / Redo ────────────────────────────────
document.querySelectorAll('.resetBtn').forEach((btn) => {
    btn.addEventListener('click', () => send('resetProp', { slot: parseInt(btn.dataset.slot) }));
});

document.querySelectorAll('.copyBtn').forEach((btn) => {
    btn.addEventListener('click', () => {
        const slot = parseInt(btn.dataset.slot);
        send('copyData', { slot, format: $('fmt' + slot).value });
    });
});

document.querySelectorAll('.undoBtn').forEach((btn) => {
    btn.addEventListener('click', () => send('undo', { slot: parseInt(btn.dataset.slot) }));
});
document.querySelectorAll('.redoBtn').forEach((btn) => {
    btn.addEventListener('click', () => send('redo', { slot: parseInt(btn.dataset.slot) }));
});

document.querySelectorAll('.quickCopyBtn').forEach((btn) => {
    btn.addEventListener('click', () => send('quickCopy', { slot: parseInt(btn.dataset.slot) }));
});

// ─── Save / Export / Reset All ─────────────────────────────────
$('btnSave').addEventListener('click', async () => {
    const raw   = $('saveName').value.trim();
    const notes = $('saveNotes').value.trim();
    const slot  = parseInt($('saveSlot').value) || 1;

    if (!raw) { showToast(t('ui_enter_name'), 'error'); return; }

    // Muss der Normalisierung in Lua entsprechen
    const name = raw.replace(/\s+/g, '_').replace(/[^\w-]/g, '').toLowerCase();
    if (!name) { showToast(t('ui_enter_name'), 'error'); return; }

    if (presets[name] && !(await confirmDialog(t('ui_confirm_overwrite', name)))) return;

    send('saveEntry', { name: raw, notes, slot });
    $('saveName').value  = '';
    $('saveNotes').value = '';
});

$('btnExport').addEventListener('click', () => {
    send('exportLua', { format: $('exportFmt').value });
});

$('btnResetAll').addEventListener('click', () => {
    send('resetAll', {});
    showToast(t('ui_reset_done'), 'info');
});

// ─── Close ─────────────────────────────────────────────────────
function closeUI() {
    $('app').style.display = 'none';
    closeModal(false);
    send('closeUI', {});
}

$('btnClose').addEventListener('click', closeUI);

document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    if (modalEl.classList.contains('open')) { closeModal(false); return; }
    closeUI();
});
