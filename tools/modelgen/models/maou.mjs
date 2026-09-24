// 魔王 (demon lord) and the player's pickaxe cursor.
import { Model } from '../lib/model.mjs';
import { sphere, ellipsoid, capsule, roundCone, chain, torus } from '../lib/sdf.mjs';
import { blade, tube, grid } from '../lib/param.mjs';
import { hex, cmix, fbm, norm, add, sub, mul, len, qEuler, smoothstep, clamp } from '../lib/math.mjs';
import { seg, bump, wave, backOut, easeIn, easeOut, easeInOut, wobble, TAU } from '../lib/anim.mjs';

export function buildMaou() {
  const m = new Model('maou');
  m.material('cloth', { roughness: 0.8 });
  m.material('skin', { roughness: 0.6 });
  m.material('metal', { roughness: 0.3, metallic: 0.6 });
  m.material('glow', { roughness: 0.4, emissive: [1.0, 0.62, 0.05], emissiveStrength: 1.4 });
  m.material('orb', { roughness: 0.15, emissive: [0.55, 0.15, 1.0], emissiveStrength: 1.6 });
  m.material('cape', { roughness: 0.85, doubleSided: true });

  m.bone('root', null, [0, 0, 0]);
  m.bone('body', 'root', [0, 0.12, 0]);
  m.bone('head', 'body', [0, 0.36, 0]);
  m.bone('armL', 'body', [0.12, 0.32, 0]);
  m.bone('handL', 'armL', [0.2, 0.2, 0.06]);
  m.bone('armR', 'body', [-0.12, 0.32, 0]);
  m.bone('handR', 'armR', [-0.2, 0.2, 0.06]);
  m.bone('staff', 'handR', [-0.2, 0.2, 0.06]);
  m.bone('cape', 'body', [0, 0.34, -0.08]);
  m.bone('cape2', 'cape', [0, 0.15, -0.14]);
  m.bone('footL', 'root', [0.06, 0.03, 0.02]);
  m.bone('footR', 'root', [-0.06, 0.03, 0.02]);

  const robe = hex('#3a1d5a'), robeDark = hex('#1f0e33'), gold = hex('#e0b040'), goldDark = hex('#8a6418'), red = hex('#9a1c2c');
  const robeCol = (p) => {
    let c = cmix(robeDark, robe, smoothstep(0.02, 0.3, p[1]));
    if (p[1] < 0.06) c = cmix(gold, goldDark, fbm(p, 60, 1)); // hem
    if (Math.abs(p[0]) < 0.022 && p[2] > 0) c = gold; // front trim
    if (Math.abs(p[1] - 0.2) < 0.018) c = p[2] > 0.1 && Math.abs(p[0]) < 0.04 ? hex('#d0302a') : hex('#2a1810'); // belt + gem
    return cmix(c, robeDark, Math.max(0, fbm(p, 20, 2) - 0.6));
  };
  // ---- robe body, sleeves, shoulders
  m.sdf(
    'cloth',
    [
      roundCone([0, 0.07, 0], [0, 0.3, 0], 0.17, 0.1, { bone: 'body', k: 0.02, color: robeCol, displace: (p) => 0.006 * Math.sin(Math.atan2(p[2], p[0]) * 8) * smoothstep(0.25, 0.05, p[1]) }),
      ellipsoid([0, 0.04, 0], [0.19, 0.045, 0.18], { bone: 'body', k: 0.04, color: robeCol }),
      ...[1, -1].flatMap((sx) => [
        roundCone([sx * 0.1, 0.31, 0], [sx * 0.18, 0.22, 0.05], 0.045, 0.05, { bone: sx > 0 ? 'armL' : 'armR', k: 0.03, color: (p) => (len(sub(p, [sx * 0.185, 0.215, 0.052])) > 0.04 ? robe : gold) }),
        // spiked pauldrons
        ellipsoid([sx * 0.12, 0.34, 0], [0.065, 0.04, 0.06], { bone: 'body', k: 0.02, color: (p) => (p[1] < 0.325 ? gold : hex('#2a1a3a')) }),
        roundCone([sx * 0.15, 0.36, 0], [sx * 0.22, 0.42, -0.01], 0.022, 0.003, { bone: 'body', k: 0.008, color: gold }),
      ]),
      // high collar
      roundCone([0, 0.3, -0.05], [0, 0.42, -0.1], 0.1, 0.13, { bone: 'body', k: 0.02, color: (p) => (p[1] > 0.4 ? gold : hex('#5a1020')), displace: (p) => 0.006 * Math.cos(Math.atan2(p[0], -p[2]) * 10) }),
      roundCone([0, 0.3, 0.02], [0, 0.44, 0.06], 0.09, 0.11, { bone: 'body', op: 'sub', k: 0.02, color: hex('#5a1020') }),
    ],
    0.016,
  );
  // ---- head
  const skin = hex('#7a62a8'), skinDark = hex('#43336a');
  m.sdf(
    'skin',
    [
      sphere([0, 0.5, 0.01], 0.15, { bone: 'head', k: 0.02, color: (p) => cmix(skinDark, skin, smoothstep(0.38, 0.55, p[1]) * smoothstep(-0.05, 0.1, p[2])) }),
      // pointy ears
      ...[1, -1].map((sx) => roundCone([sx * 0.13, 0.5, 0], [sx * 0.23, 0.55, -0.03], 0.035, 0.004, { bone: 'head', k: 0.03, color: skin })),
      // grin
      ellipsoid([0, 0.43, 0.14], [0.06, 0.018, 0.04], { bone: 'head', op: 'sub', k: 0.012, rot: qEuler(-0.15, 0, 0), color: hex('#2a0a14') }),
      // hands
      sphere([0.2, 0.2, 0.06], 0.04, { bone: 'handL', k: 0.01, color: skin }),
      sphere([-0.2, 0.2, 0.06], 0.04, { bone: 'handR', k: 0.01, color: skin }),
      // feet peeking out
      ellipsoid([0.06, 0.03, 0.12], [0.04, 0.03, 0.06], { bone: 'footL', k: 0.01, color: hex('#2a1a1a') }),
      ellipsoid([-0.06, 0.03, 0.12], [0.04, 0.03, 0.06], { bone: 'footR', k: 0.01, color: hex('#2a1a1a') }),
    ],
    0.013,
  );
  // fangs
  m.sdf(
    'skin',
    [1, -1].map((sx) => roundCone([sx * 0.03, 0.438, 0.145], [sx * 0.028, 0.405, 0.15], 0.012, 0.002, { bone: 'head', k: 0.004, color: hex('#fffaf0') })),
    0.004,
  );
  // ---- helmet + horns + crown gem
  const helm = hex('#2a1c42'), helmHi = hex('#5c4488');
  m.sdf(
    'metal',
    [
      ellipsoid([0, 0.56, -0.005], [0.162, 0.125, 0.162], {
        bone: 'head',
        k: 0.01,
        color: (p) => (p[1] < 0.49 ? gold : cmix(helm, helmHi, smoothstep(0.55, 0.68, p[1]) * 0.7)),
      }),
      // visor cutout to expose the face
      ellipsoid([0, 0.49, 0.13], [0.12, 0.08, 0.1], { bone: 'head', op: 'sub', k: 0.02, color: gold }),
      ...[1, -1].flatMap((sx) =>
        chain(
          [[sx * 0.11, 0.6, 0.0], [sx * 0.2, 0.64, 0.02], [sx * 0.27, 0.72, 0.04], [sx * 0.28, 0.82, 0.07], [sx * 0.25, 0.88, 0.09]],
          [0.045, 0.036, 0.026, 0.015, 0.004],
          { bone: 'head', k: 0.015, colorAt: (t) => cmix(hex('#d8c08a'), hex('#fff4d0'), t) },
        ),
      ),
      sphere([0, 0.66, 0.1], 0.025, { bone: 'head', k: 0.01, color: gold }),
    ],
    0.012,
  );
  m.sdf('glow', [sphere([0, 0.665, 0.12], 0.016, { bone: 'head', k: 0, color: hex('#ff3040') })], 0.003);
  // glowing eyes
  for (const sx of [1, -1])
    m.sdf('glow', [ellipsoid([sx * 0.055, 0.5, 0.135], [0.034, 0.024, 0.016], { bone: 'head', k: 0, rot: qEuler(0, 0, sx * -0.3), color: (p) => (len(sub(p, [sx * 0.05, 0.505, 0.15])) < 0.01 ? hex('#fff8d0') : hex('#ffc020')) })], 0.003);
  // ---- staff with orb
  const staffTop = [-0.22, 0.52, 0.08], staffBot = [-0.19, 0.0, 0.05];
  m.add(
    'metal',
    tube([staffBot, [-0.2, 0.2, 0.06], staffTop], {
      radius: (t) => 0.014,
      color: (t) => (Math.abs(t - 0.4) < 0.04 || t > 0.93 ? gold : hex('#3a2418')),
      bone: () => 'staff',
      segments: 8,
      rings: 12,
    }),
  );
  m.sdf(
    'metal',
    [0, 1, 2, 3].map((i) => {
      const a = (i / 4) * TAU;
      return roundCone(add(staffTop, [0, -0.01, 0]), add(staffTop, [Math.cos(a) * 0.04, 0.07, Math.sin(a) * 0.04]), 0.01, 0.004, { bone: 'staff', k: 0.01, color: gold });
    }),
    0.004,
  );
  m.sdf('orb', [sphere(add(staffTop, [0, 0.055, 0]), 0.045, { bone: 'staff', k: 0, color: (p) => cmix(hex('#9a40ff'), hex('#ffd8ff'), smoothstep(0.5, 0.8, fbm(p, 40, 2))) })], 0.005);
  // ---- cape (outer dark purple, inner crimson)
  m.add(
    'cape',
    grid(
      12,
      14,
      (u, v) => {
        // u: top -> bottom, v: left -> right
        const x = (v - 0.5) * (0.24 + 0.16 * u);
        const y = 0.4 - u * 0.37;
        const z = -0.1 - 0.06 * u - 0.03 * Math.cos((v - 0.5) * Math.PI) * (1 - u) + 0.015 * Math.sin(v * TAU * 2.5) * u - 0.04 * u * u;
        const bone = u < 0.45 ? { cape: 1 } : { cape: 1 - (u - 0.45) / 0.55, cape2: (u - 0.45) / 0.55 };
        const c = u > 0.93 ? gold : cmix(hex('#2c1446'), hex('#1a0a2a'), u);
        return { p: [x, y, z], c, b: bone };
      },
      { doubleSided: true, thickness: 0.006, backColor: (u) => (u > 0.93 ? gold : cmix(red, hex('#5a0c18'), u)) },
    ),
  );

  const arms = (p, l, r) => {
    p.rot('armL', l);
    p.rot('armR', r);
  };
  m.anim('idle', 2.4, (t, p) => {
    const b = wave(t, 2.4);
    p.scl('body', [1 - 0.015 * b, 1 + 0.02 * b, 1 - 0.015 * b]);
    p.rot('head', [0.04 * wave(t, 2.4, 1, 0.2), 0.12 * wave(t, 2.4, 1, 0.1), 0.06 * wave(t, 2.4, 1, 0.35)]);
    arms(p, [0, 0, 0.08 * b], [0, 0, -0.05 * b]);
    p.rot('cape', [0.06 + 0.04 * wave(t, 2.4, 1, 0.3), 0, 0]);
    p.rot('cape2', [0.08 * wave(t, 2.4, 1, 0.5), 0, 0]);
  });
  // being carried away by the hero: flailing
  m.anim('carried', 0.6, (t, p) => {
    const f = wave(t, 0.6);
    p.rot('body', [0.1, 0, 0.18 * f]);
    p.rot('head', [-0.15, 0.25 * wave(t, 0.6, 2), -0.1 * f]);
    arms(p, [0.4 * wave(t, 0.6, 1, 0.25), 0, 0.9 + 0.5 * f], [0.4 * wave(t, 0.6, 1, 0.75), 0, -0.9 + 0.5 * f]);
    p.rot('footL', [0.6 * wave(t, 0.6, 2), 0, 0]);
    p.rot('footR', [-0.6 * wave(t, 0.6, 2), 0, 0]);
    p.rot('cape', [0.4 + 0.15 * wave(t, 0.6, 2), 0, 0]);
    p.rot('cape2', [0.3 * wave(t, 0.6, 2, 0.3), 0, 0]);
  });
  m.anim('scared', 0.5, (t, p) => {
    const s = 0.03 * Math.sin((t / 0.5) * TAU * 4);
    p.pos('body', [s, 0, 0]);
    p.scl('body', [1.03, 0.94, 1.03]);
    p.rot('head', [0.2, 0, s * 3]);
    arms(p, [-0.6, 0, 1.4], [-0.6, 0, -1.4]);
    p.rot('cape', [0.1, 0, 0]);
  });
  m.anim('cheer', 1.0, (t, p) => {
    const j = Math.abs(Math.sin((t / 1.0) * TAU));
    p.pos('root', [0, 0.06 * j, 0]);
    p.scl('body', [1, 1 + 0.04 * j, 1]);
    arms(p, [0, 0, 1.6 + 0.2 * wave(t, 1, 2)], [0, 0, -1.6 - 0.2 * wave(t, 1, 2)]);
    p.rot('head', [-0.25, 0, 0.15 * wave(t, 1)]);
    p.rot('cape', [0.2 + 0.1 * j, 0, 0]);
  });
  // plopped down onto the chosen cell
  m.anim(
    'land',
    0.7,
    (t, p) => {
      const drop = 1 - easeIn(seg(t, 0, 0.3));
      p.pos('root', [0, 0.4 * drop, 0]);
      const sq = bump(t, 0.28, 0.5);
      p.scl('root', [1 + 0.15 * sq, 1 - 0.2 * sq + 0.06 * wobble(t, 0.5, 4, 8), 1 + 0.15 * sq]);
      arms(p, [0, 0, 0.6 * drop], [0, 0, -0.6 * drop]);
    },
    { loop: false },
  );
  return m;
}

// Player cursor: pickaxe. Handle along +Y, head across X at the top.
export function buildPickaxe() {
  const m = new Model('pickaxe');
  m.material('wood', { roughness: 0.7 });
  m.material('iron', { roughness: 0.28, metallic: 0.85 });
  const wood = hex('#8a5a2e'), woodDark = hex('#5a3616'), leather = hex('#3a2012');
  m.sdf(
    'wood',
    [
      capsule([0, 0, 0], [0, 0.62, 0], 0.026, {
        k: 0.01,
        color: (p) => {
          if (p[1] > 0.08 && p[1] < 0.22) return Math.sin(p[1] * 180) > 0.2 ? leather : hex('#5a3420');
          return cmix(wood, woodDark, fbm([p[0] * 8, p[1] * 0.6, p[2] * 8], 30, 3));
        },
      }),
      sphere([0, 0.0, 0], 0.034, { k: 0.02, color: woodDark }),
    ],
    0.006,
  );
  const iron = hex('#8b919c'), ironHi = hex('#d8dde6'), ironDark = hex('#4a4e58');
  const pts = [];
  const radii = [];
  for (let i = 0; i <= 8; i++) {
    const x = -0.26 + (i / 8) * 0.52;
    pts.push([x, 0.62 - 0.35 * x * x, 0]);
    const t = Math.abs(x) / 0.26;
    radii.push(0.04 * (1 - t) + 0.005);
  }
  m.sdf(
    'iron',
    [
      ...chain(pts, radii, { k: 0.02, colorAt: (t, p) => cmix(iron, ironHi, smoothstep(0.35, 0.05, Math.abs(t - 0.5)) * 0.2 + smoothstep(0.6, 0.66, p[1]) * 0.6) }),
      roundCone([0, 0.56, 0], [0, 0.66, 0], 0.045, 0.045, { k: 0.015, color: ironDark }),
    ],
    0.006,
  );
  return m;
}
