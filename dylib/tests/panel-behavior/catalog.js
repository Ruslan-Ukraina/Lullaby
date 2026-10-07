// The catalog panel (feats/panel.js) as the gates splice it in, drawn from the catalog
// and states notproton-settings printed (fixtures/, kept current by SettingsCLITests):
// it shows the catalog's words in Steam's language and none of its own, the five quick
// rows, inheritance and Reset, the Advanced dialog, the level for all games, and it moves
// renderer launch options into the catalog.
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { walk, runner } = require('./harness');

const emit = process.argv[2];
const fixtures = process.argv[3];
const source = execFileSync(emit, ['panel'], { encoding: 'utf8' });
const t = runner('catalog panel');

const catalog = JSON.parse(fs.readFileSync(path.join(fixtures, 'catalog.json'), 'utf8'));
const gameState = JSON.parse(fs.readFileSync(path.join(fixtures, 'state-game.json'), 'utf8'));
const globalState = JSON.parse(fs.readFileSync(path.join(fixtures, 'state-global.json'), 'utf8'));
const clone = x => JSON.parse(JSON.stringify(x));

// React and Steam's controls, stubbed: elements are plain objects, hooks keep their first value.
const mk = (type, props, key) => ({ type, props, key });
const J = { jsx: mk, jsxs: mk, Fragment: 'Fragment' };
const B = { y4: 'ToggleField', Vb: 'DropdownField', FO: 'TextField', $n: 'Button', m: 'Dropdown', D0: 'Field' };
const R = {
  useState: init => [init, () => {}],
  useEffect: () => {}, useCallback: f => f, useRef: v => ({ current: v }), useMemo: f => f(),
};

t.ok(!/__NP_SETTINGS_TOKEN__/.test(source) || source.includes('"__NP_SETTINGS_TOKEN__"'), 'the token is a placeholder the dylib replaces');
t.ok(!/[^\x00-\x7f]/.test(source), 'the spliced source is ASCII');
const api = new Function('return ' + source)()(J, B, R);
t.ok(typeof api.Game === 'function' && typeof api.Global === 'function', 'the panel gives the page two components');

// ---- helpers ----------------------------------------------------------------------

function text(node) {
  if (node === null || node === undefined || node === false) return '';
  if (typeof node === 'string' || typeof node === 'number') return String(node);
  if (Array.isArray(node)) return node.map(text).join('');
  if (typeof node.type === 'function') return text(node.type(node.props));
  return text(node.props && node.props.children);
}

function strings(node, out = []) {
  if (node === null || node === undefined || node === false) return out;
  if (typeof node === 'string') { out.push(node); return out; }
  if (typeof node === 'number') return out;
  if (Array.isArray(node)) { node.forEach(n => strings(n, out)); return out; }
  if (typeof node.type === 'function') return strings(node.type(node.props), out);
  const p = node.props || {};
  for (const k of ['label', 'description', 'placeholder', 'aria-label']) if (p[k] !== undefined) strings(p[k], out);
  if (p.rgOptions) p.rgOptions.forEach(o => strings(o.label, out));
  if (node.type !== 'style') strings(p.children, out);
  return out;
}

function catalogWords(lang) {
  const words = new Set();
  const add = l => { if (l && l[lang]) words.add(l[lang]); };
  for (const s of catalog.settings) {
    add(s.title); add(s.caption);
    add(s.help.summary); add(s.help.footnote);
    (s.help.entries || []).forEach(e => { add(e.name); add(e.text); });
    (s.control.choices || []).forEach(c => add(c.label));
  }
  catalog.groups.forEach(g => add(g.title));
  Object.values(catalog.text).forEach(add);
  return words;
}

// A string the panel drew is a catalog text, a catalog template filled in, or a piece of
// the game's own data; nothing else.
function foreign(tree, lang, data) {
  const words = catalogWords(lang);
  const templates = [...words].filter(w => w.includes('%@')).map(w => w.split('%@'));
  const allowed = new Set(['i', ' \u00b7 ', ' \u2014 ', ...data]);
  return strings(tree).filter(s => {
    if (words.has(s) || allowed.has(s) || /^\d+\u2013\d+$/.test(s)) return false;
    return !templates.some(([a, b]) => s.startsWith(a) && s.endsWith(b) && s.length >= a.length + b.length);
  });
}

function ctxFor(state, lang, extra) {
  const calls = [];
  return Object.assign({
    lang, catalog, state, error: null, advanced: false, global: state.level === 'global',
    setAdvanced: v => calls.push(['advanced', v]),
    change: (id, value) => { calls.push(['set', id, value]); return Promise.resolve(); },
    reset: () => { calls.push(['reset']); return Promise.resolve(); },
    calls,
  }, extra || {});
}

const rowsOf = tree => walk(tree).filter(n => ['ToggleField', 'DropdownField', 'Field'].includes(n.type));
const titleOf = (id, lang) => catalog.settings.find(s => s.id === id).title[lang];
const rowFor = (tree, id, lang) => rowsOf(tree).find(n => text(n.props.label).startsWith(titleOf(id, lang)));

// ---- the game's panel, in each language ----------------------------------------------

for (const lang of ['en', 'uk', 'ru']) {
  const ctx = ctxFor(clone(gameState), lang);
  const tree = api.view(ctx);
  const quick = catalog.settings.filter(s => s.quick !== undefined).sort((a, b) => a.quick - b.quick);
  const titles = rowsOf(tree).map(n => text(n.props.label));
  t.ok(quick.length === 5 && quick.every((s, i) => titles[i] && titles[i].startsWith(s.title[lang])),
    `${lang}: the five quick rows in the catalog's order (${titles.join(' | ')})`);
  t.ok(text(tree).includes(catalog.text.section[lang]), `${lang}: the header is the catalog's`);
  t.ok(text(tree).includes(catalog.text.advanced[lang]), `${lang}: Advanced settings button`);
  const extra = foreign(tree, lang, ['Dormison', 'peak.exe', 'PEAK', 'NotProton']);
  t.ok(extra.length === 0, `${lang}: every word comes from the catalog (${JSON.stringify(extra)})`);
}

// ---- inheritance, Reset and changes -----------------------------------------------------

{
  const ctx = ctxFor(clone(gameState), 'ru');
  const tree = api.view(ctx);
  const renderer = rowFor(tree, 'renderer', 'ru');
  t.ok(text(renderer.props.description).includes(catalog.text.defaultValue.ru.replace('%@', 'DXMT')),
    'a game-only row names NotProton\'s default');
  const up = rowFor(tree, 'upscaler', 'ru');
  t.ok(text(up.props.description).includes(catalog.text.inherited.ru.replace('%@', catalog.settings.find(x => x.id === 'upscaler').control.choices[0].label.ru)),
    'a row with a level for all games says what it inherits');
  const retina = rowFor(tree, 'retina', 'ru');
  t.ok(retina.props.checked === true && text(retina.props.description).includes(catalog.text.inherited.ru.replace('%@', '\u0412\u043a\u043b.')),
    'a toggle shows the value for all games it inherits');
  const fps = rowFor(tree, 'fps', 'ru');
  t.ok(text(fps.props.description).includes(catalog.text.own.ru), 'an own value says so');
  const reset = walk(fps.props.description).find(n => n.props && n.props.className === 'NPLink');
  reset.props.onClick({ stopPropagation() {}, preventDefault() {} });
  fps.props.onChange(false);
  const upscaler = rowFor(tree, 'upscaler', 'ru');
  upscaler.props.onChange({ data: JSON.stringify('metalfx') });
  t.ok(JSON.stringify(ctx.calls) === JSON.stringify([['set', 'fps', null], ['set', 'fps', false], ['set', 'upscaler', 'metalfx']]),
    `Reset inherits, a toggle and a list set values (${JSON.stringify(ctx.calls)})`);

  const info = walk(renderer.props.label).find(n => n.props && /NPInfo/.test(n.props.className || ''));
  t.ok(info && info.props.role === 'button', 'every row has an (i)');
}

// ---- the frame-rate limit's own value --------------------------------------------------

{
  const ctx = ctxFor(clone(gameState), 'en');
  const tree = api.view(ctx);
  const limit = rowFor(tree, 'fpsLimit', 'en');
  t.ok(limit.props.selectedOption === JSON.stringify('__custom'), 'a limit outside the presets shows as Custom');
  const field = walk(tree).find(n => n.type === 'TextField');
  t.ok(field && field.props.value === '45', 'and its number is editable');
  let typed = '45';
  const make = value => {
    const st = R.useState;
    R.useState = init => (typeof init === 'string' ? [value, v => { typed = v; }] : [init, () => {}]);
    const editor = walk(api.view(ctx)).find(n => n.type === 'TextField');
    R.useState = st;
    return editor;
  };
  make('60').props.onBlur();
  make('5').props.onBlur();
  make('x').props.onBlur();
  t.ok(JSON.stringify(ctx.calls) === JSON.stringify([['set', 'fpsLimit', 60]]),
    `a typed limit in range is set, others are not (${JSON.stringify(ctx.calls)})`);
  limit.props.onChange({ data: JSON.stringify(30) });
  t.ok(JSON.stringify(ctx.calls.pop()) === JSON.stringify(['set', 'fpsLimit', 30]), 'a preset is set as a number');
  t.ok(typed === '45', 'typing goes through the field');
}

// ---- the Advanced dialog -------------------------------------------------------------------

{
  const ctx = ctxFor(clone(gameState), 'uk', { advanced: true });
  const tree = api.view(ctx);
  const overlay = walk(tree).find(n => n.props && n.props.className === 'NPOverlay');
  t.ok(!!overlay, 'Advanced settings opens over the window');
  const inDialog = rowsOf(overlay).map(n => text(n.props.label));
  const others = catalog.settings.filter(s => s.quick === undefined && s.levels.includes('game'));
  t.ok(others.every(s => inDialog.some(l => l.startsWith(s.title.uk))) && inDialog.length >= others.length,
    `every other row is in the dialog (${inDialog.length} of ${others.length})`);
  const groups = walk(overlay).filter(n => n.props && n.props.className === 'NPGroup').map(n => text(n));
  t.ok(JSON.stringify(groups) === JSON.stringify(catalog.groups.map(g => g.title.uk)), `by group, in order (${groups})`);
  const buttons = walk(overlay).filter(n => n.type === 'Button');
  buttons.find(b => text(b) === catalog.text.resetGame.uk).props.onClick();
  buttons.find(b => text(b) === catalog.text.done.uk).props.onClick();
  overlay.props.onKeyDown({ key: 'Escape', stopPropagation() {}, preventDefault() {} });
  t.ok(JSON.stringify(ctx.calls) === JSON.stringify([['reset'], ['advanced', false], ['advanced', false]]),
    `Reset game settings, Done and Escape (${JSON.stringify(ctx.calls)})`);
  const dll = walk(overlay).filter(n => n.type === 'Button' && text(n) === catalog.text.remove.uk);
  dll[0].props.onClick();
  t.ok(JSON.stringify(ctx.calls.pop()) === JSON.stringify(['set', 'dllOverrides', null]), 'removing the last DLL override inherits');
  t.ok(foreign(tree, 'uk', ['Dormison', 'peak.exe', 'PEAK', 'NotProton', 'd3dcompiler_47']).length === 0,
    'the dialog speaks only the catalog\'s words');
}

// ---- for all games -------------------------------------------------------------------------

{
  const ctx = ctxFor(clone(globalState), 'ru');
  const tree = api.view(ctx);
  const titles = rowsOf(tree).map(n => text(n.props.label));
  t.ok(!titles.some(l => l.startsWith(titleOf('renderer', 'ru'))), 'no renderer for all games');
  t.ok(titles.length === 4, `four quick rows for all games (${titles.join(' | ')})`);
  t.ok(text(tree).includes(catalog.text.globalSection.ru), 'its own header');
  const retina = rowFor(tree, 'retina', 'ru');
  t.ok(text(retina.props.description).includes(catalog.text.ownGlobal.ru), 'a changed value for all games says so');
  const fps = rowFor(tree, 'fps', 'ru');
  t.ok(text(fps.props.description).includes(catalog.text.defaultValue.ru.replace('%@', '\u0412\u044b\u043a\u043b.')), 'and an unchanged one names the default');
  const dialog = walk(api.view(ctxFor(clone(globalState), 'ru', { advanced: true })))
    .find(n => n.props && n.props.className === 'NPOverlay');
  t.ok(!rowsOf(dialog).some(n => text(n.props.label).startsWith(titleOf('msync', 'ru'))), 'msync+ is a game\'s alone');
  t.ok(text(dialog).includes(catalog.text.resetGlobal.ru), 'reset to NotProton\'s defaults');
}

// ---- status, errors -------------------------------------------------------------------------

{
  const running = Object.assign(clone(gameState), { status: 'restartGame', running: true });
  const tree = api.view(ctxFor(running, 'en'));
  const status = walk(tree).find(n => n.props && /NPStatus/.test(n.props.className || ''));
  t.ok(/NPWarn/.test(status.props.className) && text(status).includes(catalog.text.restartGame.en), 'a running game: after a restart');
  const first = api.view(ctxFor(Object.assign(clone(gameState), { status: 'firstLaunch', exes: [] }), 'uk'));
  t.ok(text(first).includes(catalog.text.firstLaunch.uk), 'a game not started yet: at its first launch');
  for (const lang of ['en', 'uk', 'ru']) {
    const down = api.view({ lang, catalog: null, state: null, error: 'boom' });
    t.ok(text(down).includes(api.FALLBACK[lang].replace('%@', 'boom')), `${lang}: unavailable, in Steam's language`);
  }
}

// ---- Steam renamed a control ------------------------------------------------------------

{
  const partial = Object.assign({}, B);
  delete partial.y4;
  const broken = new Function('return ' + source)()(J, partial, R);
  const tree = broken.view(ctxFor(clone(gameState), 'ru'));
  t.ok(text(tree).includes(broken.FALLBACK.ru.replace('%@', 'Steam UI (y4)')), 'a control Steam renamed is reported, not drawn');
  const noReact = new Function('return ' + source)()(J, B, {});
  const out = noReact.Game({ details: { unAppID: 1, strCompatToolName: 'notproton', vecPlatforms: ['windows'] } });
  t.ok(text(out).includes('React'), 'without React the panel says so instead of calling hooks');
}

// ---- launch options and requests -----------------------------------------------------------

{
  const cases = [
    ['', null],
    ['-dx11 NOTPROTON_RENDERER=dxmt', { renderer: 'dxmt', options: '-dx11' }],
    ['WINEMSYNC=1 CX_GRAPHICS_BACKEND=dxvk %command%', { renderer: 'dxvk', options: '%command%' }],
    ['CX_GRAPHICS_BACKEND=d3dmetal %command% -x', { renderer: null, options: '%command% -x' }],
    ['WINEMSYNC=0 %command%', null],
    ['NOTPROTON_WATCHDOG=60 %command%', null],
  ];
  for (const [options, want] of cases) {
    const got = api.legacyOptions(options);
    t.ok(JSON.stringify(got) === JSON.stringify(want), `launch options ${JSON.stringify(options)} -> ${JSON.stringify(got)}`);
  }
  const p = api.requestPath({ op: 'set', app: 3527290, id: 'fps', value: true });
  const m = /^\/notproton-settings\/__NP_SETTINGS_TOKEN__\/[0-9a-z]{1,32}\/([A-Za-z0-9_-]+)\.json$/.exec(p);
  const body = m && Buffer.from(m[1].replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8');
  t.ok(body === '{"op":"set","app":3527290,"id":"fps","value":true}', `a request is a virtual file the dylib answers (${p})`);
  t.ok(api.langOf('ukrainian') === 'uk' && api.langOf('russian') === 'ru' && api.langOf('german') === 'en', "Steam's language");
  const run = d => api.runsThroughNotProton(d);
  t.ok(run({ strCompatToolName: 'notproton', vecPlatforms: ['windows', 'osx'] }), 'a forced NotProton');
  t.ok(run({ strCompatToolName: '', vecPlatforms: ['windows'] }), 'a Windows-only game');
  t.ok(!run({ strCompatToolName: '', vecPlatforms: ['windows', 'osx'] }), 'not a game with a macOS build');
  t.ok(!run({ strCompatToolName: 'proton_9', vecPlatforms: ['windows'] }), 'not another tool');
}

if (t.failed) { console.log(`catalog panel: ${t.failed} failed`); process.exit(1); }
console.log('==> catalog panel: the catalog drawn in Steam, three languages, no words of its own');
