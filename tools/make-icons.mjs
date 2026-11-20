// Génère les icônes SVG (trait 24×24, rendu « template ») dans App/Assets.xcassets.
// Usage : node tools/make-icons.mjs
// Plusieurs tracés sont adaptés de Lucide (licence ISC).
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const ICONS = {
  'mode.avion': ['path:M17.8 19.2 16 11l3.5-3.5C21 6 21.5 4 21 3c-1-.5-3 0-4.5 1.5L13 8 4.8 6.2c-.5-.1-.9.1-1.1.5l-.3.5c-.2.5-.1 1 .3 1.3L9 12l-2 3H4l-1 1 3 2 2 3 1-1v-3l3-2 3.5 5.3c.3.4.8.5 1.3.3l.5-.2c.4-.3.6-.7.5-1.2z'],
  'mode.train': ['path:M8 3.1V7a4 4 0 0 0 8 0V3.1', 'path:m9 15-1-1', 'path:m15 15 1-1', 'path:M9 19c-2.8 0-5-2.2-5-5v-4a8 8 0 0 1 16 0v4c0 2.8-2.2 5-5 5Z', 'path:m8 19-2 3', 'path:m16 19 2 3'],
  'mode.bus': ['path:M8 6v6', 'path:M15 6v6', 'path:M2 12h19.6', 'path:M18 18h3s.5-1.7.8-2.8c.1-.4.2-.8.2-1.2 0-.4-.1-.8-.2-1.2l-1.4-5C20.1 6.8 19.1 6 18 6H4a2 2 0 0 0-2 2v10h3', 'circle:7,18,2', 'path:M9 18h5', 'circle:16,18,2'],
  'mode.covoiturage': ['path:M19 17h2c.6 0 1-.4 1-1v-3c0-.9-.7-1.7-1.5-1.9C18.7 10.6 16 10 16 10s-1.3-1.4-2.2-2.3c-.5-.4-1.1-.7-1.8-.7H5c-.6 0-1.1.4-1.4.9l-1.4 2.9A3.7 3.7 0 0 0 2 12v4c0 .6.4 1 1 1h2', 'circle:7,17,2', 'path:M9 17h6', 'circle:17,17,2'],
  'mode.bateau': ['path:M12 10.2V14', 'path:M12 2v3', 'path:M19 13V7a2 2 0 0 0-2-2H7a2 2 0 0 0-2 2v6', 'path:M19.4 20A11.6 11.6 0 0 0 21 14l-8.2-3.6a2 2 0 0 0-1.6 0L3 14a11.6 11.6 0 0 0 2.8 7.8', 'path:M2 21c.6.5 1.2 1 2.5 1 2.5 0 2.5-2 5-2 1.3 0 1.9.5 2.5 1s1.2 1 2.5 1c2.5 0 2.5-2 5-2 1.3 0 1.9.5 2.5 1'],
  'mode.taxi-brousse': ['path:M18.5 17H21a1 1 0 0 0 1-1v-3.6a1 1 0 0 0-.6-.9L20 11l-3.8-4.2a2 2 0 0 0-1.5-.8H4a2 2 0 0 0-2 2v8a1 1 0 0 0 1 1h2', 'path:M9 17h5.5', 'path:M2 11h18', 'path:M8 6v5', 'path:M13.5 6v5', 'path:M5 3.5h8', 'circle:7,17,2', 'circle:16.5,17,2'],
  'mode.voiture': ['path:M10 2h4', 'path:m21 8-2 2-1.5-3.7A2 2 0 0 0 15.6 5H8.4a2 2 0 0 0-1.9 1.3L5 10 3 8', 'path:M7 14h.01', 'path:M17 14h.01', 'rect:3,10,18,8,2', 'path:M5 18v2', 'path:M19 18v2'],
  'mode.local': ['rect:4,3,16,16,2', 'path:M4 11h16', 'path:M12 3v8', 'path:m8 19-2 3', 'path:m18 22-2-3', 'path:M8 15h.01', 'path:M16 15h.01'],
  'ui.arrow': ['path:M5 12h14', 'path:m12 5 7 7-7 7'],
  'ui.chevron': ['path:m9 18 6-6-6-6'],
  'ui.external': ['path:M15 3h6v6', 'path:M10 14 21 3', 'path:M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6'],
  'ui.alert': ['path:M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z', 'path:M12 9v4', 'path:M12 17h.01'],
  'ui.clock': ['circle:12,12,9', 'path:M12 7v5l3 2'],
  'ui.bolt': ['path:M13 2 4 14h7l-1 8 9-12h-7z'],
  'ui.route': ['circle:6,19,3', 'path:M9 19h8.5a3.5 3.5 0 0 0 0-7h-11a3.5 3.5 0 0 1 0-7H15', 'circle:18,5,3'],
  'ui.log': ['path:M8 6h13', 'path:M8 12h13', 'path:M8 18h13', 'path:M3 6h.01', 'path:M3 12h.01', 'path:M3 18h.01'],
  'ui.settings': ['path:M4 6h9', 'path:M17 6h3', 'path:M4 12h3', 'path:M11 12h9', 'path:M4 18h11', 'path:M19 18h1', 'circle:15,6,2', 'circle:9,12,2', 'circle:17,18,2'],
  'ui.calendar': ['rect:3,4,18,18,2', 'path:M16 2v4', 'path:M8 2v4', 'path:M3 10h18'],
  'ui.swap': ['path:m16 3 4 4-4 4', 'path:M20 7H4', 'path:m8 21-4-4 4-4', 'path:M4 17h16'],
  'ui.refresh': ['path:M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8', 'path:M21 3v5h-5', 'path:M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16', 'path:M8 16H3v5'],
  'ui.copy': ['rect:8,8,14,14,2', 'path:M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2'],
  'ui.share': ['path:M12 2v13', 'path:m16 6-4-4-4 4', 'path:M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8'],
  'ui.trash': ['path:M3 6h18', 'path:M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6', 'path:M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2'],
  'ui.key': ['circle:7.5,15.5,5.5', 'path:m21 2-9.6 9.6', 'path:m15.5 7.5 3 3L22 7l-3-3'],
  'ui.check': ['path:M20 6 9 17l-5-5'],
  'ui.search': ['circle:11,11,8', 'path:m21 21-4.3-4.3'],
  'ui.user': ['circle:12,8,5', 'path:M20 21a8 8 0 0 0-16 0'],
  'ui.pin': ['path:M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z', 'circle:12,10,3'],
  'ui.info': ['circle:12,12,10', 'path:M12 16v-4', 'path:M12 8h.01'],
  'ui.ticket': ['path:M2 9a3 3 0 0 1 0 6v2a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-2a3 3 0 0 1 0-6V7a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2Z', 'path:M13 5v2', 'path:M13 17v2', 'path:M13 11v2'],
};

const STROKE = 'fill="none" stroke="#000000" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"';

function element(spec) {
  const [kind, value] = [spec.slice(0, spec.indexOf(':')), spec.slice(spec.indexOf(':') + 1)];
  if (kind === 'path') return `<path d="${value}" ${STROKE}/>`;
  const n = value.split(',');
  if (kind === 'circle') return `<circle cx="${n[0]}" cy="${n[1]}" r="${n[2]}" ${STROKE}/>`;
  if (kind === 'rect') return `<rect x="${n[0]}" y="${n[1]}" width="${n[2]}" height="${n[3]}" rx="${n[4]}" ${STROKE}/>`;
  throw new Error(`forme inconnue : ${spec}`);
}

const root = join(process.cwd(), 'App', 'Assets.xcassets');
for (const [name, shapes] of Object.entries(ICONS)) {
  const dir = join(root, `${name}.imageset`);
  mkdirSync(dir, { recursive: true });
  const file = `${name}.svg`;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">\n  ${shapes.map(element).join('\n  ')}\n</svg>\n`;
  writeFileSync(join(dir, file), svg);
  writeFileSync(join(dir, 'Contents.json'), JSON.stringify({
    images: [{ filename: file, idiom: 'universal' }],
    info: { author: 'xcode', version: 1 },
    properties: { 'preserves-vector-representation': true, 'template-rendering-intent': 'template' },
  }, null, 2) + '\n');
}
console.log(`${Object.keys(ICONS).length} icônes SVG générées dans ${root}`);
