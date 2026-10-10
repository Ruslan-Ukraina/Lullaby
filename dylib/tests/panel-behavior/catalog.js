// The catalog panel (feats/panel.js) as the gates splice it in, drawn from the catalog
// and states lullaby-settings printed (fixtures/, kept current by SettingsCLITests):
// it shows the catalog's words in Steam's language and none of its own, the four quick
// rows, a line only under a value that differs from what it inherits, Reset, the Advanced
// dialog by group, the level for all games; it leaves Steam's launch options alone.
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
const B = { y4: 'ToggleField', Vb: 'DropdownField', FO: 'TextField', $n: 'Button', D0: 'Field' };
const R = {
  useState: init => [init, () => {}],
  useEffect: () => {}, useCallback: f => f, useRef: v => ({ current: v }), useMemo: f => f(),
};

t.ok(!/__NP_SETTINGS_TOKEN__/.test(source) || source.includes('"__NP_SETTINGS_TOKEN__"'), 'the token is a placeholder the dylib replaces');
t.ok(!/[^\x00-\x7f]/.test(source), 'the spliced source is ASCII');
const D = { createPortal: (child, host) => ({ type: 'Portal', props: { children: child }, host }) };
const api = new Function('return ' + source)()(J, B, R, D);
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
    lang, catalog, state, error: null, advanced: false, global: state.level === 'global', host: { body: true },
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
  t.ok(quick.length === 4 && quick.every((s, i) => titles[i] && titles[i].startsWith(s.title[lang])),
    `${lang}: the four quick rows in the catalog's order (${titles.join(' | ')})`);
  t.ok(text(tree).includes(catalog.text.section[lang]), `${lang}: the header is the catalog's`);
  t.ok(text(tree).includes(catalog.text.advanced[lang]), `${lang}: Advanced settings button`);
  const extra = foreign(tree, lang, ['peak.exe', 'PEAK', 'Lullaby']);
  t.ok(extra.length === 0, `${lang}: every word comes from the catalog (${JSON.stringify(extra)})`);
  t.ok(!text(tree).includes('Dormison'), `${lang}: no engine name by the header`);
}

// ---- inheritance, Reset and changes -----------------------------------------------------

{
  const ctx = ctxFor(clone(gameState), 'ru');
  const tree = api.view(ctx);
  const renderer = rowFor(tree, 'renderer', 'ru');
  t.ok(text(renderer.props.description).includes(catalog.text.defaultValue.ru.replace('%@', 'DXMT')),
    'a game-only row of its own names Lullaby\'s default');
  const up = rowFor(tree, 'upscaler', 'ru');
  t.ok(!walk(up.props.description).some(n => n.props && n.props.className === 'LBInherit'),
    'an inherited row has no line under it');
  const retina = rowFor(tree, 'retina', 'ru');
  t.ok(retina.props.checked === true && !text(retina.props.description).includes(catalog.text.inherited.ru.split('%@')[0]),
    'a toggle shows the value for all games it inherits, without a line');
  const fps = rowFor(tree, 'fps', 'ru');
  t.ok(text(fps.props.description).includes(catalog.text.inherited.ru.replace('%@', '\u0412\u044b\u043a\u043b.')),
    'a game\'s own value names the one for all games');
  t.ok(!('own' in catalog.text) && !('ownGlobal' in catalog.text), 'no "Custom" label left in the catalog');
  t.ok(rowsOf(tree).filter(n => n.type === 'DropdownField').every(n => n.props.childrenContainerWidth === 'min'),
    'lists are as wide as their choices');
  t.ok(!walk(tree).some(n => n.props && n.props.className === 'LBLink'), 'no Reset in the rows');
  fps.props.onChange(false);
  const upscaler = rowFor(tree, 'upscaler', 'ru');
  upscaler.props.onChange({ data: JSON.stringify('metalfx') });
  const resetGame = walk(tree).filter(n => n.type === 'Button' && text(n) === catalog.text.resetGame.ru);
  t.ok(resetGame.length === 1, 'one "Reset game settings" under the block');
  resetGame[0].props.onClick();
  t.ok(JSON.stringify(ctx.calls) === JSON.stringify([['set', 'fps', false], ['set', 'upscaler', 'metalfx'], ['reset']]),
    `a toggle and a list set values, the button resets the game (${JSON.stringify(ctx.calls)})`);
  const css = text(walk(tree).find(n => n.type === 'style'));
  const z = Number((/\.LBOverlay\{[^}]*z-index:(\d+)/.exec(css) || [])[1]);
  t.ok(z >= 1500 && z < 1600, `the dialog sits under Steam's menus (.DialogMenuPosition 1600), as Steam's own modals (1500): ${z}`);
  t.ok(/\.LBDialog \.DialogDropDown\{font-size:13px;padding:8px 14px/.test(css), "the dialog's lists are the page's size");

  const info = walk(renderer.props.label).find(n => n.props && /LBInfo/.test(n.props.className || ''));
  t.ok(info && info.props.role === 'button', 'every row has an (i)');
}

// ---- the Advanced dialog -------------------------------------------------------------------

{
  const ctx = ctxFor(clone(gameState), 'uk', { advanced: true });
  const tree = api.view(ctx);
  const overlay = walk(tree).find(n => n.props && n.props.className === 'LBOverlay');
  t.ok(!!overlay, 'Advanced settings opens over the window');
  const portal = walk(tree).find(n => n.type === 'Portal');
  t.ok(portal && portal.host === ctx.host && walk(portal).includes(overlay),
    "the dialog goes into the window's body through a portal, not into the page");
  const inline = new Function('return ' + source)()(J, B, R, null).view(ctxFor(clone(gameState), 'uk', { advanced: true }));
  t.ok(!walk(inline).some(n => n.type === 'Portal') && walk(inline).some(n => n.props && n.props.className === 'LBOverlay'),
    'without React DOM the dialog stays inline');
  const inDialog = rowsOf(overlay).map(n => text(n.props.label));
  const others = catalog.settings.filter(s => s.quick === undefined && s.levels.includes('game'));
  t.ok(others.every(s => inDialog.some(l => l.startsWith(s.title.uk))) && inDialog.length >= others.length,
    `every other row is in the dialog (${inDialog.length} of ${others.length})`);
  const groups = walk(overlay).filter(n => n.props && n.props.className === 'LBGroup').map(n => text(n));
  t.ok(JSON.stringify(groups) === JSON.stringify(catalog.groups.map(g => g.title.uk)),
    `by group, in order, no Game Porting Toolkit block (it is added in Lullaby) (${groups})`);
  const buttons = walk(overlay).filter(n => n.type === 'Button');
  buttons.find(b => text(b) === catalog.text.resetGame.uk).props.onClick();
  buttons.find(b => text(b) === catalog.text.done.uk).props.onClick();
  overlay.props.onKeyDown({ key: 'Escape', stopPropagation() {}, preventDefault() {} });
  t.ok(JSON.stringify(ctx.calls) === JSON.stringify([['reset'], ['advanced', false], ['advanced', false]]),
    `Reset game settings, Done and Escape (${JSON.stringify(ctx.calls)})`);
  t.ok(groups.includes(catalog.groups.find(g => g.id === 'oldGames').title.uk), 'old games have a group of their own');
  t.ok(!walk(overlay).some(n => n.type === 'textarea' || n.type === 'input'), 'no variable or DLL editors');
  t.ok(foreign(tree, 'uk', ['peak.exe', 'PEAK', 'Lullaby']).length === 0,
    'the dialog speaks only the catalog\'s words');
}

// ---- for all games -------------------------------------------------------------------------

{
  const ctx = ctxFor(clone(globalState), 'ru');
  const tree = api.view(ctx);
  const titles = rowsOf(tree).map(n => text(n.props.label));
  t.ok(!titles.some(l => l.startsWith(titleOf('renderer', 'ru'))), 'no renderer for all games');
  t.ok(titles.length === 3, `three quick rows for all games (${titles.join(' | ')})`);
  t.ok(text(tree).includes(catalog.text.globalSection.ru), 'its own header');
  const retina = rowFor(tree, 'retina', 'ru');
  t.ok(text(retina.props.description).includes(catalog.text.defaultValue.ru.replace('%@', '\u0412\u044b\u043a\u043b.')),
    'a changed value for all games names Lullaby\'s default');
  const fps = rowFor(tree, 'fps', 'ru');
  t.ok(!walk(fps.props.description).some(n => n.props && n.props.className === 'LBInherit'), 'an unchanged one has no line');
  const dialog = walk(api.view(ctxFor(clone(globalState), 'ru', { advanced: true })))
    .find(n => n.props && n.props.className === 'LBOverlay');
  t.ok(!rowsOf(dialog).some(n => text(n.props.label).startsWith(titleOf('msync', 'ru'))), 'msync+ is a game\'s alone');
  t.ok(text(dialog).includes(catalog.text.resetGlobal.ru), 'reset to Lullaby\'s defaults');
}

// ---- status, errors -------------------------------------------------------------------------

{
  const running = Object.assign(clone(gameState), { status: 'restartGame', running: true });
  const tree = api.view(ctxFor(running, 'en'));
  const status = walk(tree).find(n => n.props && /LBStatus/.test(n.props.className || ''));
  t.ok(/LBWarn/.test(status.props.className) && text(status).includes(catalog.text.restartGame.en), 'a running game: after a restart');
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
  const out = noReact.Game({ details: { unAppID: 1, strCompatToolName: 'lullaby', vecPlatforms: ['windows'] } });
  t.ok(text(out).includes('React'), 'without React the panel says so instead of calling hooks');
}

// ---- launch options and requests -----------------------------------------------------------

{
  t.ok(!/SetAppLaunchOptions|strLaunchOptions/.test(source), "Steam's launch options stay the player's: the panel neither reads nor writes them");
  const p = api.requestPath({ op: 'set', app: 3527290, id: 'fps', value: true });
  const m = /^\/lullaby-settings\/__NP_SETTINGS_TOKEN__\/[0-9a-z]{1,32}\/([A-Za-z0-9_-]+)\.json$/.exec(p);
  const body = m && Buffer.from(m[1].replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8');
  t.ok(body === '{"op":"set","app":3527290,"id":"fps","value":true}', `a request is a virtual file the dylib answers (${p})`);
  t.ok(api.langOf('ukrainian') === 'uk' && api.langOf('russian') === 'ru' && api.langOf('german') === 'en', "Steam's language");
  const run = d => api.runsThroughLullaby(d);
  t.ok(run({ strCompatToolName: 'lullaby', vecPlatforms: ['windows', 'osx'] }), 'a forced Lullaby');
  t.ok(run({ strCompatToolName: '', vecPlatforms: ['windows'] }), 'a Windows-only game');
  t.ok(!run({ strCompatToolName: '', vecPlatforms: ['windows', 'osx'] }), 'not a game with a macOS build');
  t.ok(!run({ strCompatToolName: 'proton_9', vecPlatforms: ['windows'] }), 'not another tool');
}

if (t.failed) { console.log(`catalog panel: ${t.failed} failed`); process.exit(1); }
console.log('==> catalog panel: the catalog drawn in Steam, three languages, no words of its own');
