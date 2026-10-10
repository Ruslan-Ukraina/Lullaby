// Launch options from CrossOver days are rewritten once the panel shows for a game:
// CX_GRAPHICS_BACKEND moves to LULLABY_RENDERER (or goes), WINEMSYNC=1 goes, and
// nothing else changes. A game without them is never written.
'use strict';
const { panel, walk, details, runner, FORMS } = require('./harness');

const emit = process.argv[2];
if (!emit) { console.error('usage: cleanup.js <emit>'); process.exit(2); }

const CASES = [
  ['CX_GRAPHICS_BACKEND=dxvk %command%', 'LULLABY_RENDERER=dxvk %command%', 'dxvk',
   'the old renderer moves to the new name'],
  ['LULLABY_RENDERER=dxmt CX_GRAPHICS_BACKEND=dxvk %command%', 'LULLABY_RENDERER=dxmt %command%', 'dxmt',
   'a renderer already chosen wins over the old name'],
  ['CX_GRAPHICS_BACKEND=d3dmetal -novid %command%', '-novid %command%', '',
   'an old value the engine has no renderer for goes (automatic)'],
  ['WINEMSYNC=1 %command%', '%command%', '',
   'WINEMSYNC=1 goes: msync+ is on anyway'],
  ['-novid  CX_GRAPHICS_BACKEND=wined3d MTL_HUD_ENABLED=1 WINEMSYNC=1 DXMT_CONFIG=x %command%',
   'LULLABY_RENDERER=wined3d -novid MTL_HUD_ENABLED=1 DXMT_CONFIG=x %command%', 'wined3d',
   'other arguments stay, %command% stays last'],
];

let failed = 0;
for (const form of Object.keys(FORMS)) {
  const { render: P, written } = panel(emit, form);
  const t = runner(form);

  for (const [from, to, shown, what] of CASES) {
    written.length = 0;
    const dropdown = walk(P({ details: details(from) })).find(x => x.type === 'Dropdown');
    const opts = written.length ? written[written.length - 1].opts : null;
    t.ok(written.length === 1 && opts === to && written[0].appid === 287700,
         `${what} (${from} -> ${opts})`);
    t.ok(dropdown.props.selectedOption === shown, `the list shows ${shown || 'automatic'} right away`);
  }

  for (const kept of ['WINEMSYNC=0 %command%', 'LULLABY_RENDERER=dxvk -novid %command%', '', '-novid  %command%']) {
    written.length = 0;
    P({ details: details(kept) });
    t.ok(written.length === 0, `"${kept}" is not written`);
  }

  written.length = 0;
  t.ok(P({ details: details('CX_GRAPHICS_BACKEND=dxvk WINEMSYNC=1 %command%',
                             { vecPlatforms: ['osx'], strCompatToolName: '' }) }) === null
       && written.length === 0, 'a Mac game Steam runs natively keeps its options');

  // The renderer chosen afterwards starts from the rewritten options.
  written.length = 0;
  walk(P({ details: details('CX_GRAPHICS_BACKEND=dxvk WINEMSYNC=1 -novid %command%') }))
    .find(x => x.type === 'Dropdown').props.onChange({ data: 'dxmt' });
  const last = written[written.length - 1].opts;
  t.ok(last === 'LULLABY_RENDERER=dxmt -novid %command%', `a choice after the rewrite (${last})`);

  failed += t.failed;
}
console.log(failed ? `\n${failed} failure(s)` : '\nold options rewritten, others untouched');
process.exit(failed ? 1 : 0);
