// Generates all procedural monster / prop models into assets/models/monsters.
//   node tools/modelgen/build.mjs            -> all models
//   node tools/modelgen/build.mjs moss bug   -> only models whose name contains an argument
import path from 'node:path';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { buildMoss, buildBud, buildFlower } from './models/moss.mjs';
import { buildLarva, buildPupa, buildAdult } from './models/bug.mjs';
import { buildMaou, buildPickaxe } from './models/maou.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.resolve(here, '../../assets/models/monsters');
fs.mkdirSync(outDir, { recursive: true });

const builders = {
  moss: buildMoss,
  moss_bud: buildBud,
  moss_flower: buildFlower,
  bug_larva: buildLarva,
  bug_pupa: buildPupa,
  bug_adult: buildAdult,
  maou: buildMaou,
  pickaxe: buildPickaxe,
};

const filter = process.argv.slice(2);
for (const [name, build] of Object.entries(builders)) {
  if (filter.length && !filter.some((f) => name.includes(f))) continue;
  const t0 = Date.now();
  const model = build();
  const file = path.join(outDir, name + '.glb');
  model.write(file);
  const s = model.stats();
  console.log(`${name.padEnd(14)} ${String(s.vertices).padStart(6)} verts ${String(s.triangles).padStart(6)} tris ${s.bones} bones  [${s.anims.join(', ')}]  ${(fs.statSync(file).size / 1024).toFixed(0)} KB  ${Date.now() - t0} ms`);
}
