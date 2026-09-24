// モコゴケ (prey moss) and its evolved forms: ツボミ (bud) and モコバナ (flower).
import { Model } from '../lib/model.mjs';
import { sphere, ellipsoid, capsule } from '../lib/sdf.mjs';
import { blade, tube } from '../lib/param.mjs';
import { hex, cmix, rng, fbm, norm, add, mul, len, sub, qEuler, qRotate, qAxisAngle } from '../lib/math.mjs';
import { seg, bump, wave, backOut, easeIn, easeOut, wobble, TAU } from '../lib/anim.mjs';
import { eye, mossColor } from './parts.mjs';

const MOSS = { low: '#2d5a1c', mid: '#4f9a2c', high: '#86c940', speck: '#c6ea6e' };
const lumpy = (amp, freq) => (p) => amp * (fbm(p, freq, 2) - 0.5);

function materials(m) {
  m.material('body', { roughness: 0.92 });
  m.material('gloss', { roughness: 0.12 });
  m.material('leaf', { roughness: 0.7, doubleSided: true });
  return m;
}

// Fuzzy moss clumps scattered over an upper dome.
function fluffs(center, radii, count, seed, bone, avoid) {
  const r = rng(seed);
  const out = [];
  const cLight = hex('#9fd35e'), cDark = hex('#4c8a2f'), cTip = hex('#c8e886');
  let tries = 0;
  while (out.length < count && tries++ < 400) {
    const th = r() * TAU;
    const ph = 0.15 + r() * 1.05; // from the pole down
    const dir = [Math.sin(ph) * Math.cos(th), Math.cos(ph), Math.sin(ph) * Math.sin(th)];
    const p = add(center, [dir[0] * radii[0] * 0.92, dir[1] * radii[1] * 0.92, dir[2] * radii[2] * 0.92]);
    if (avoid && avoid(p)) continue;
    const rad = 0.03 + r() * 0.03;
    const tone = r();
    out.push(
      sphere(p, rad, {
        bone,
        k: 0.028,
        blend: 0.014,
        color: (q) => {
          const n = fbm(q, 40, 2);
          const base = tone > 0.5 ? cLight : cDark;
          return cmix(base, cTip, Math.max(0, n - 0.45) * 3 + Math.max(0, q[1] - p[1]) * 6);
        },
      }),
    );
  }
  return out;
}

function sproutLeaves(m, base, bone, scale = 1) {
  const stemTop = add(base, [0.004, 0.1 * scale, 0.018]);
  m.add(
    'leaf',
    tube([base, add(base, [0, 0.05 * scale, 0.008]), stemTop], {
      radius: (t) => 0.012 * scale * (1 - t * 0.35),
      color: () => hex('#5f9a33'),
      bone: (t) => (t < 0.3 ? { top: 1 - t / 0.3, [bone]: t / 0.3 } : bone),
      segments: 8,
      rings: 6,
    }),
  );
  for (const sx of [1, -1]) {
    const dir = norm([sx, 0.55, 0.12]);
    m.add(
      'leaf',
      blade({
        origin: stemTop,
        dir,
        side: [0, 0.05, 1],
        up: norm([-sx * 0.55, 1, 0]),
        length: 0.11 * scale,
        width: (u) => 0.036 * scale * Math.pow(Math.sin(Math.PI * Math.min(1, u * 1.02)), 0.75) * (1 - 0.25 * u),
        cup: 0.25,
        curl: (u) => -0.03 * scale * u * u,
        color: (u, x) => (Math.abs(x) < 0.12 ? hex('#4d8a2a') : cmix(hex('#5ea136'), hex('#b3e36a'), u)),
        backColor: (u) => cmix(hex('#4f8a2e'), hex('#8cc152'), u),
        bone,
        nu: 10,
        nv: 6,
      }),
    );
  }
}

// ---------------------------------------------------------------- moss
export function buildMoss() {
  const m = materials(new Model('moss'));
  m.bone('root', null, [0, 0, 0]).bone('body', 'root', [0, 0.1, 0]).bone('top', 'body', [0, 0.24, 0]).bone('sprout', 'top', [0, 0.365, 0]);

  const bodyCol = mossColor({ ...MOSS, y0: 0.0, y1: 0.42 });
  const blush = hex('#e98f86');
  const topCenter = [0, 0.255, 0], topR = [0.2, 0.125, 0.19];
  const withBlush = (p) => {
    let c = bodyCol(p);
    for (const sx of [1, -1]) {
      const d = len(sub(p, [sx * 0.14, 0.205, 0.215]));
      if (d < 0.05) c = cmix(c, blush, (1 - d / 0.05) * 0.85);
    }
    return c;
  };
  const avoidFace = (p) => p[2] > 0.08 && p[1] < 0.37;
  m.sdf(
    'body',
    [
      ellipsoid([0, 0.055, 0], [0.3, 0.065, 0.28], { bone: 'body', color: hex('#2f5520'), k: 0.06 }),
      ellipsoid([0, 0.15, 0], [0.29, 0.155, 0.27], { bone: 'body', color: withBlush, k: 0.08, displace: lumpy(0.018, 16) }),
      ellipsoid(topCenter, topR, { bone: 'top', color: withBlush, k: 0.09, displace: lumpy(0.016, 16) }),
      ...fluffs(topCenter, topR, 24, 7, 'top', avoidFace),
      ...fluffs([0, 0.15, 0], [0.29, 0.155, 0.27], 14, 21, 'body', (p) => p[2] > 0.05 || p[1] < 0.12),
      ellipsoid([0, 0.19, 0.262], [0.06, 0.022, 0.04], { bone: 'top', op: 'sub', k: 0.01, rot: qEuler(0.35, 0, 0), color: (p) => (p[1] < 0.182 ? hex('#d8606a') : hex('#3a1418')) }),
    ],
    0.015,
  );
  // tiny mushroom growing on the back
  m.sdf(
    'body',
    [
      capsule([0.13, 0.29, -0.11], [0.15, 0.36, -0.12], 0.016, { bone: 'top', color: hex('#efe2c0'), k: 0.004 }),
      ellipsoid([0.152, 0.372, -0.122], [0.045, 0.024, 0.045], {
        bone: 'top',
        k: 0.006,
        color: (p) => (fbm(p, 55, 1) > 0.62 ? hex('#fff6e6') : p[1] < 0.365 ? hex('#8a2a22') : hex('#d8463a')),
      }),
    ],
    0.008,
  );
  for (const sx of [1, -1]) m.sdf('gloss', [eye([sx * 0.078, 0.262, 0.172], 0.052, [sx * 0.12, 0.12, 1], 'top', { iris: '#2e3d18' })], 0.0065);
  sproutLeaves(m, [0, 0.36, 0.0], 'sprout');

  const squash = (p, sy) => p.scl('root', [1 / Math.sqrt(sy), sy, 1 / Math.sqrt(sy)]);

  m.anim('idle', 2.0, (t, p) => {
    squash(p, 1 + 0.035 * wave(t, 2));
    p.rot('top', [0.03 * wave(t, 2, 1, 0.15), 0, 0.02 * wave(t, 2, 1, 0.4)]);
    p.rot('sprout', [0.06 * wave(t, 2, 2), 0, 0.14 * wave(t, 2, 1, 0.3)]);
  });
  m.anim('move', 0.8, (t, p) => {
    const ph = t / 0.8;
    const sy = 1 - 0.17 * bump(ph, 0, 0.3) + 0.14 * bump(ph, 0.24, 0.62) - 0.15 * bump(ph, 0.58, 0.9);
    squash(p, sy);
    p.pos('root', [0, 0.07 * bump(ph, 0.27, 0.64), 0]);
    p.rot('body', [0.16 * bump(ph, 0.18, 0.72), 0, 0]);
    p.rot('top', [-0.1 * bump(ph, 0.3, 0.8), 0, 0]);
    p.rot('sprout', [-0.35 * bump(ph, 0.3, 0.8) + 0.22 * bump(ph, 0.72, 1), 0, 0]);
  });
  m.anim('absorb', 1.2, (t, p) => {
    squash(p, 1 + 0.06 * wave(t, 1.2, 2));
    p.rot('body', [0.22, 0, 0]);
    p.rot('top', [0.12 + 0.05 * wave(t, 1.2, 2, 0.25), 0, 0]);
    p.rot('sprout', [0.1, 0.5 * wave(t, 1.2, 1), 0.12 * wave(t, 1.2, 2)]);
  });
  m.anim(
    'attack',
    0.7,
    (t, p) => {
      const back = bump(t, 0, 0.3), lunge = bump(t, 0.26, 0.52), settle = wobble(t, 0.5, 4, 8);
      squash(p, 1 - 0.12 * back + 0.08 * lunge + 0.05 * settle);
      p.pos('body', [0, 0.02 * lunge, -0.05 * back + 0.17 * lunge]);
      p.rot('body', [-0.28 * back + 0.42 * lunge, 0, 0]);
      p.rot('top', [-0.1 * back + 0.25 * lunge, 0, 0]);
      p.rot('sprout', [0.4 * back - 0.5 * lunge + 0.2 * settle, 0, 0]);
    },
    { loop: false },
  );
  m.anim(
    'hurt',
    0.45,
    (t, p) => {
      const hit = bump(t, 0, 0.18);
      squash(p, 1 - 0.2 * hit + 0.08 * wobble(t, 0.15, 5, 9));
      p.rot('body', [-0.25 * hit, 0, 0.1 * wobble(t, 0.05, 6, 8)]);
      p.rot('sprout', [0.5 * hit, 0, 0]);
    },
    { loop: false },
  );
  m.anim(
    'die',
    1.1,
    (t, p) => {
      const f = easeIn(seg(t, 0.1, 0.75));
      const sy = 1 - 0.8 * f;
      p.scl('root', [1 + 0.35 * f, sy, 1 + 0.35 * f]);
      p.rot('sprout', [0, 0, 1.2 * f]);
      p.rot('top', [0.2 * f, 0, 0]);
      const gone = seg(t, 0.8, 1.1);
      p.scl('root', 1 - 0.99 * gone);
    },
    { loop: false },
  );
  m.anim(
    'spawn',
    0.6,
    (t, p) => {
      const s = Math.max(0.01, backOut(seg(t, 0, 0.5)));
      p.scl('root', [s, s * (1 + 0.15 * wobble(t, 0.3, 4, 10)), s]);
      p.rot('sprout', [0.4 * wobble(t, 0.2, 3, 6), 0, 0]);
    },
    { loop: false },
  );
  return m;
}

// Shared mossy mound for bud / flower.
function mound(m, seed) {
  const bodyCol = mossColor({ ...MOSS, y0: 0.0, y1: 0.26 });
  m.sdf(
    'body',
    [
      ellipsoid([0, 0.05, 0], [0.3, 0.07, 0.29], { bone: 'base', color: hex('#2f5520'), k: 0.05 }),
      ellipsoid([0, 0.1, 0], [0.26, 0.13, 0.25], { bone: 'base', color: bodyCol, k: 0.07, displace: lumpy(0.018, 16) }),
      ...fluffs([0, 0.1, 0], [0.26, 0.13, 0.25], 26, seed, 'base', (p) => p[2] > 0.1 && p[1] < 0.2 && Math.abs(p[0]) < 0.16),
    ],
    0.015,
  );
  // sleepy half-closed eyes on the mound
  for (const sx of [1, -1])
    m.sdf('gloss', [eye([sx * 0.075, 0.15, 0.2], 0.042, [sx * 0.1, -0.05, 1], 'base', { iris: '#3a2410', lid: { color: '#4c8a2f', height: 0.12 } })], 0.006);
  // leaves at the base of the stem
  for (let i = 0; i < 4; i++) {
    const a = (i / 4) * TAU + 0.4;
    const dir = norm([Math.cos(a), 0.35, Math.sin(a)]);
    const side = norm([-Math.sin(a), 0, Math.cos(a)]);
    m.add(
      'leaf',
      blade({
        origin: [Math.cos(a) * 0.04, 0.245, Math.sin(a) * 0.04],
        dir,
        side,
        up: norm(add([0, 1, 0], mul(dir, -0.35))),
        length: 0.16,
        width: (u) => 0.045 * Math.pow(Math.sin(Math.PI * Math.min(1, u * 1.02)), 0.7),
        cup: 0.3,
        curl: (u) => -0.05 * u * u,
        color: (u, x) => (Math.abs(x) < 0.1 ? hex('#3f7a22') : cmix(hex('#4f9230'), hex('#a4d85e'), u)),
        backColor: (u) => cmix(hex('#3e6f25'), hex('#7fb449'), u),
        bone: (u) => (u < 0.4 ? 'base' : { base: 0.4, stem1: 0.6 }),
      }),
    );
  }
}

// ---------------------------------------------------------------- bud
export function buildBud() {
  const m = materials(new Model('moss_bud'));
  m.material('petal', { roughness: 0.55 });
  m.bone('root', null, [0, 0, 0]).bone('base', 'root', [0, 0.08, 0]).bone('stem1', 'base', [0, 0.2, 0]).bone('stem2', 'stem1', [0, 0.34, 0]).bone('bulb', 'stem2', [0, 0.47, 0]);
  mound(m, 11);
  m.add(
    'leaf',
    tube([[0, 0.18, 0], [0.01, 0.3, 0.01], [0.0, 0.4, 0.015], [0, 0.48, 0]], {
      radius: (t) => 0.026 - 0.008 * t,
      color: (t) => cmix(hex('#4c8a2c'), hex('#79b545'), t),
      bone: (t) => (t < 0.45 ? 'stem1' : t < 0.85 ? 'stem2' : 'bulb'),
      segments: 10,
      rings: 12,
    }),
  );
  const bulbCol = (p) => {
    const t = (p[1] - 0.46) / 0.2;
    const ang = Math.atan2(p[2], p[0]);
    const stripe = Math.pow(Math.abs(Math.sin(ang * 3)), 6);
    return cmix(cmix(hex('#b0306a'), hex('#f07aa8'), t), hex('#ffd0e2'), stripe * 0.5 * t);
  };
  m.sdf(
    'petal',
    [
      ellipsoid([0, 0.53, 0], [0.085, 0.09, 0.085], { bone: 'bulb', color: bulbCol, k: 0.05 }),
      sphere([0, 0.61, 0], 0.035, { bone: 'bulb', color: bulbCol, k: 0.07 }),
      sphere([0, 0.655, 0], 0.012, { bone: 'bulb', color: bulbCol, k: 0.05 }),
    ],
    0.009,
  );
  // sepals hugging the bulb
  for (let i = 0; i < 5; i++) {
    const a = (i / 5) * TAU;
    const out = [Math.cos(a), 0, Math.sin(a)];
    m.add(
      'leaf',
      blade({
        origin: [out[0] * 0.05, 0.465, out[2] * 0.05],
        dir: norm(add([0, 1, 0], mul(out, 0.45))),
        side: [-Math.sin(a), 0, Math.cos(a)],
        up: norm(add(mul(out, 1), [0, -0.6, 0])),
        length: 0.085,
        width: (u) => 0.03 * Math.sin(Math.PI * Math.min(1, 0.15 + u * 0.9)),
        cup: -0.2,
        curl: (u) => -0.06 * u * u,
        color: (u) => cmix(hex('#3f7a22'), hex('#86c34c'), u),
        bone: 'bulb',
        nu: 8,
        nv: 4,
      }),
    );
  }
  m.anim('idle', 2.6, (t, p) => {
    p.rot('stem1', [0.05 * wave(t, 2.6, 1, 0.1), 0, 0.07 * wave(t, 2.6)]);
    p.rot('stem2', [0.05 * wave(t, 2.6, 1, 0.3), 0, 0.08 * wave(t, 2.6, 1, 0.2)]);
    p.scl('bulb', 1 + 0.03 * wave(t, 2.6, 2));
    p.scl('base', [1, 1 + 0.02 * wave(t, 2.6, 1, 0.5), 1]);
  });
  m.anim('absorb', 1.0, (t, p) => {
    p.scl('bulb', 1 + 0.1 * Math.pow(Math.max(0, wave(t, 1.0)), 2));
    p.scl('base', [1 + 0.04 * wave(t, 1.0, 1, 0.5), 1 - 0.04 * wave(t, 1.0, 1, 0.5), 1 + 0.04 * wave(t, 1.0, 1, 0.5)]);
    p.rot('stem2', [0, 0.2 * wave(t, 1.0), 0]);
  });
  m.anim(
    'hurt',
    0.45,
    (t, p) => {
      p.rot('stem1', [-0.3 * bump(t, 0, 0.2) + 0.1 * wobble(t, 0.15, 4, 8), 0, 0]);
      p.scl('base', [1, 1 - 0.15 * bump(t, 0, 0.2), 1]);
    },
    { loop: false },
  );
  m.anim(
    'die',
    1.2,
    (t, p) => {
      const f = easeIn(seg(t, 0, 0.8));
      p.rot('stem1', [0.9 * f, 0, 0.3 * f]);
      p.rot('stem2', [0.6 * f, 0, 0]);
      p.scl('bulb', 1 - 0.4 * f);
      p.scl('root', 1 - 0.99 * seg(t, 0.8, 1.2));
    },
    { loop: false },
  );
  m.anim(
    'spawn',
    0.8,
    (t, p) => {
      const s = Math.max(0.01, backOut(seg(t, 0, 0.6)));
      p.scl('root', s);
      p.scl('stem1', [1, Math.max(0.01, easeOut(seg(t, 0.1, 0.7))), 1]);
    },
    { loop: false },
  );
  return m;
}

// ---------------------------------------------------------------- flower
export function buildFlower() {
  const m = materials(new Model('moss_flower'));
  m.material('petal', { roughness: 0.5, doubleSided: true });
  m.bone('root', null, [0, 0, 0]).bone('base', 'root', [0, 0.08, 0]).bone('stem1', 'base', [0, 0.2, 0]).bone('stem2', 'stem1', [0, 0.38, 0]).bone('flower', 'stem2', [0, 0.56, 0.02]);
  // the whole flower head is built in a frame tilted towards the (top-down) camera
  const tilt = qEuler(0.55, 0, 0);
  const C = [0, 0.585, 0.035];
  const T = (v) => add(C, qRotate(tilt, v));
  const N = qRotate(tilt, [0, 1, 0]);
  const PET = 8;
  const petalAxis = [];
  for (let i = 0; i < PET; i++) {
    const a = (i / PET) * TAU;
    petalAxis.push(qRotate(tilt, [-Math.sin(a), 0, Math.cos(a)]));
    m.bone('petal' + i, 'flower', T([Math.cos(a) * 0.06, 0, Math.sin(a) * 0.06]));
  }
  mound(m, 13);
  m.add(
    'leaf',
    tube([[0, 0.18, 0], [0.012, 0.32, 0.0], [0.0, 0.46, 0.012], [0, 0.57, 0.03]], {
      radius: (t) => 0.03 - 0.01 * t,
      color: (t) => cmix(hex('#4c8a2c'), hex('#7fbb48'), t),
      bone: (t) => (t < 0.4 ? 'stem1' : t < 0.9 ? 'stem2' : 'flower'),
      segments: 10,
      rings: 12,
    }),
  );
  const disc = hex('#f4c534'), discDark = hex('#b8781a');
  m.sdf(
    'body',
    [
      ellipsoid(C, [0.08, 0.035, 0.08], {
        bone: 'flower',
        rot: tilt,
        k: 0.02,
        color: (p) => {
          const r = len(sub(p, C));
          const n = fbm(p, 70, 1);
          if (r > 0.066) return hex('#e79a22');
          return n > 0.62 ? discDark : cmix(disc, hex('#ffe68a'), 0.5 - r * 5);
        },
      }),
      ellipsoid(T([0, -0.03, 0]), [0.05, 0.035, 0.05], { bone: 'flower', rot: tilt, color: hex('#5f9a33'), k: 0.03 }),
      ellipsoid(T([0, 0.03, 0.022]), [0.022, 0.01, 0.012], { bone: 'flower', rot: tilt, op: 'sub', k: 0.006, color: hex('#5a2010') }),
    ],
    0.006,
  );
  for (const sx of [1, -1]) m.sdf('gloss', [eye(T([sx * 0.03, 0.028, -0.012]), 0.017, add(N, [sx * 0.15, 0, 0.3]), 'flower', { iris: '#1a1208', irisSize: 0.5, pupilSize: 0.7, highlight: [0.3, 1, 0.4] })], 0.003);
  for (let i = 0; i < PET; i++) {
    const a = (i / PET) * TAU;
    const out = qRotate(tilt, [Math.cos(a), 0, Math.sin(a)]);
    m.add(
      'petal',
      blade({
        origin: T([Math.cos(a) * 0.055, -0.004, Math.sin(a) * 0.055]),
        dir: norm(add(out, mul(N, 0.28))),
        side: petalAxis[i],
        up: norm(add(N, mul(out, -0.28))),
        length: 0.15,
        width: (u) => 0.048 * Math.pow(Math.sin(Math.PI * Math.min(1, 0.12 + u * 0.92)), 0.6) * (0.7 + 0.45 * u),
        cup: 0.3,
        curl: (u) => -0.03 * u * u,
        color: (u, x) => cmix(cmix(hex('#c23a78'), hex('#ff8fbd'), Math.min(1, u * 1.6)), hex('#ffe3ef'), Math.pow(u, 3) + Math.abs(x) * 0.1),
        backColor: (u) => cmix(hex('#9a2c60'), hex('#e27aa6'), u),
        bone: 'petal' + i,
        nu: 10,
        nv: 6,
      }),
    );
  }
  // rx > 0 droops/opens the petals, rx < 0 closes them
  const petals = (p, rx) => {
    for (let i = 0; i < PET; i++) p.rotq('petal' + i, qAxisAngle(petalAxis[i], -rx));
  };
  m.anim('idle', 3.0, (t, p) => {
    p.rot('stem1', [0.04 * wave(t, 3, 1, 0.1), 0, 0.07 * wave(t, 3)]);
    p.rot('stem2', [0.05 * wave(t, 3, 1, 0.3), 0, 0.08 * wave(t, 3, 1, 0.2)]);
    p.rot('flower', [0, 0.25 * wave(t, 3, 1, 0.1), 0]);
    petals(p, 0.08 * wave(t, 3, 2));
  });
  m.anim('absorb', 1.0, (t, p) => {
    petals(p, -0.25 * Math.max(0, wave(t, 1)));
    p.scl('flower', 1 + 0.06 * Math.max(0, wave(t, 1)));
    p.scl('base', [1 + 0.04 * wave(t, 1, 1, 0.5), 1 - 0.04 * wave(t, 1, 1, 0.5), 1 + 0.04 * wave(t, 1, 1, 0.5)]);
  });
  // spits out new moss: petals flare, flower recoils
  m.anim(
    'spawn_child',
    1.0,
    (t, p) => {
      const charge = bump(t, 0, 0.45), burst = bump(t, 0.4, 0.7);
      petals(p, -0.45 * charge + 0.55 * burst);
      p.rot('stem2', [-0.25 * charge + 0.35 * burst, 0, 0]);
      p.scl('flower', 1 - 0.1 * charge + 0.18 * burst);
      p.scl('base', [1, 1 - 0.1 * burst, 1]);
    },
    { loop: false },
  );
  m.anim(
    'hurt',
    0.45,
    (t, p) => {
      p.rot('stem1', [-0.3 * bump(t, 0, 0.2) + 0.1 * wobble(t, 0.15, 4, 8), 0, 0]);
      petals(p, 0.3 * bump(t, 0, 0.25));
    },
    { loop: false },
  );
  m.anim(
    'die',
    1.4,
    (t, p) => {
      const f = easeIn(seg(t, 0, 0.9));
      petals(p, 0.9 * f);
      p.rot('stem1', [0.7 * f, 0, 0.35 * f]);
      p.rot('stem2', [0.8 * f, 0, 0]);
      p.scl('root', 1 - 0.99 * seg(t, 0.95, 1.4));
    },
    { loop: false },
  );
  m.anim(
    'spawn',
    1.0,
    (t, p) => {
      p.scl('root', Math.max(0.01, backOut(seg(t, 0, 0.4))));
      petals(p, -1.1 * (1 - easeOut(seg(t, 0.3, 1.0))));
    },
    { loop: false },
  );
  return m;
}
