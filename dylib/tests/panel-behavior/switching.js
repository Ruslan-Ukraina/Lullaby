// Changing the renderer must not take the player's other launch options with it,
// and %command% has to stay last or Steam runs the game before the arguments.
'use strict';
const { panel, walk, details, runner, FORMS } = require('./harness');

const emit = process.argv[2];
if (!emit) { console.error('usage: switching.js <emit>'); process.exit(2); }

const KEEP = ['-novid', 'MTL_HUD_ENABLED=1', 'WINEMSYNC=0', 'LULLABY_RETINA=1', 'DXMT_CONFIG=x', '%command%'];
const FROM = '-novid LULLABY_RENDERER=dxmt CX_GRAPHICS_BACKEND=dxvk MTL_HUD_ENABLED=1 WINEMSYNC=0 '
           + 'LULLABY_RETINA=1 DXMT_CONFIG=x %command%';

let failed = 0;
for (const form of Object.keys(FORMS)) {
  const { render: P, written } = panel(emit, form);
  const t = runner(form);
  for (const to of ['', 'dxmt', 'dxvk', 'wined3d']) {
    written.length = 0;
    walk(P({ details: details(FROM) })).find(x => x.type === 'Dropdown').props.onChange({ data: to });
    const opts = written[written.length - 1].opts;
    const lost = KEEP.filter(k => opts.indexOf(k) < 0);
    t.ok(lost.length === 0 && !opts.includes('CX_GRAPHICS_BACKEND') && opts.trim().endsWith('%command%')
         && (to ? opts.includes('LULLABY_RENDERER=' + to) : !opts.includes('LULLABY_RENDERER')),
         `switching to ${to || 'automatic'} keeps the other arguments (${opts})`
         + (lost.length ? ` [lost: ${lost}]` : ''));
  }
  failed += t.failed;
}
console.log(failed ? `\n${failed} failure(s)` : '\nnothing lost');
process.exit(failed ? 1 : 0);
