// What the panel renders, checked against both forms of the one payload.
'use strict';
const { panel, walk, details, runner, FORMS } = require('./harness');

const emit = process.argv[2];
if (!emit) { console.error('usage: behavior.js <emit>'); process.exit(2); }

let failed = 0;
for (const form of Object.keys(FORMS)) {
  const { render: P, written } = panel(emit, form);
  const t = runner(form);
  const nodes = opts => walk(P({ details: details(opts) }));
  const last = () => (written.length ? written[written.length - 1].opts : '');

  t.ok(P({ details: details('', { vecPlatforms: ['osx'], strCompatToolName: '' }) }) === null,
       'a mac build with nothing pinned renders no panel');
  t.ok(P({ details: details('', { unAppID: 3420702832, vecPlatforms: ['osx'],
                                  strCompatToolName: '' }) }) !== null,
       'a shortcut renders the panel before a tool name reaches the page');

  // The panel is the renderer and nothing else: the rest is in the app's Game Settings.
  const r = nodes('');
  t.ok(r.filter(x => x.type === 'Toggle').length === 0, 'no toggles: they moved to Game Settings');
  t.ok(r.filter(x => x.type === 'Section').length === 1, 'one section');
  t.ok(r.filter(x => x.type === 'Dropdown').length === 1, 'one dropdown');
  t.ok(!('label' in r.find(x => x.type === 'Dropdown').props), 'the dropdown carries no label column');

  const backends = r.find(x => x.type === 'Dropdown').props.rgOptions;
  t.ok(backends.map(o => o.label).join(',') === 'Automatic (by the game\'s API),DXMT (DX11),DXVK,WineD3D,mtld3d (DX9),WineMetalGL (OpenGL)',
       `the renderers name themselves (${backends.map(o => o.label).join(',')})`);
  t.ok(backends.map(o => o.data).join(',') === ',dxmt,dxvk,wined3d,mtld3d,winemetalgl',
       'the renderer values stay as the run script reads them');

  t.ok(nodes('LULLABY_RENDERER=dxvk').find(x => x.type === 'Dropdown').props.selectedOption === 'dxvk',
       'the dropdown reflects the current value');
  t.ok(nodes('').find(x => x.type === 'Dropdown').props.selectedOption === '',
       'nothing set reads as automatic');

  written.length = 0;
  nodes('').find(x => x.type === 'Dropdown').props.onChange({ data: 'dxvk' });
  t.ok(last() === 'LULLABY_RENDERER=dxvk', `choosing writes the launch option (${last()})`);
  nodes('LULLABY_RENDERER=dxvk').find(x => x.type === 'Dropdown').props.onChange({ data: '' });
  t.ok(last() === '', `automatic removes it (${last()})`);

  // The old name is taken out when the renderer is chosen again.
  nodes('CX_GRAPHICS_BACKEND=dxvk -novid').find(x => x.type === 'Dropdown').props.onChange({ data: 'dxmt' });
  t.ok(last() === 'LULLABY_RENDERER=dxmt -novid', `the old argument goes, others stay (${last()})`);

  const root = P({ details: details('') });
  t.ok(root.props.className === 'MSCXPanel', 'the panel root carries its own class');
  const css = nodes('').filter(x => x.type === 'style');
  t.ok(css.length === 1 && css[0].props.children.includes('.MSCXPanel{'),
       'the panel carries one stylesheet');

  failed += t.failed;
}
console.log(failed ? `\n${failed} failure(s)` : '\nboth shapes pass');
process.exit(failed ? 1 : 0);
