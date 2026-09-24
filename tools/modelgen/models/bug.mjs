// ザクザクムシ (predator bug): larva -> pupa -> adult.
import { Model } from '../lib/model.mjs';
import { sphere, ellipsoid, capsule, roundCone, chain } from '../lib/sdf.mjs';
import { blade, tube } from '../lib/param.mjs';
import { hex, cmix, fbm, norm, add, sub, mul, len, qEuler, qRotate, qAxisAngle, smoothstep } from '../lib/math.mjs';
import { seg, bump, wave, backOut, easeIn, easeOut, easeInOut, wobble, TAU } from '../lib/anim.mjs';
import { eye } from './parts.mjs';

// ---------------------------------------------------------------- larva
export function buildLarva() {
  const m = new Model('bug_larva');
  m.material('body', { roughness: 0.55 });
  m.material('chitin', { roughness: 0.32 });
  m.material('gloss', { roughness: 0.1 });

  const Z = [0.2, 0.105, 0.0, -0.1, -0.185, -0.255];
  const R = [0.09, 0.098, 0.106, 0.098, 0.082, 0.06];
  const Y = R.map((r) => r * 0.95);
  const names = ['s0', 's1', 's2', 's3', 's4', 's5'];
  m.bone('root', null, [0, 0, 0]);
  m.bone('s2', 'root', [0, Y[2], Z[2]]);
  m.bone('s1', 's2', [0, Y[1], Z[1]]);
  m.bone('s0', 's1', [0, Y[0], Z[0]]);
  m.bone('s3', 's2', [0, Y[3], Z[3]]);
  m.bone('s4', 's3', [0, Y[4], Z[4]]);
  m.bone('s5', 's4', [0, Y[5], Z[5]]);
  m.bone('mandL', 's0', [0.045, 0.075, 0.27]);
  m.bone('mandR', 's0', [-0.045, 0.075, 0.27]);

  const back = hex('#e0892c'), backDark = hex('#a5541a'), belly = hex('#f3dca4'), spot = hex('#3c1d0e');
  const segColor = (i) => (p) => {
    const t = (p[1] - Y[i]) / R[i];
    let c = cmix(belly, back, smoothstep(-0.35, 0.15, t));
    // darker rim where segments meet
    const dz = Math.abs(p[2] - Z[i]) / (R[i] * 0.62);
    c = cmix(c, backDark, smoothstep(0.55, 0.95, dz) * smoothstep(-0.2, 0.3, t));
    // dorsal spots
    for (const sx of [1, -1]) {
      const d = len(sub(p, [sx * 0.04, Y[i] + R[i] * 0.85, Z[i]]));
      if (d < 0.028 && i > 0) c = cmix(c, spot, 1 - d / 0.028);
    }
    const n = fbm(p, 45, 2);
    return cmix(c, backDark, Math.max(0, n - 0.6) * 1.5);
  };
  const prims = [];
  for (let i = 1; i < 6; i++) prims.push(ellipsoid([0, Y[i], Z[i]], [R[i], R[i] * 0.93, R[i] * 0.64], { bone: names[i], k: 0.035, color: segColor(i), boneBlend: 0.03 }));
  // back spikes + stubby legs
  const spike = hex('#3a2214'), spikeTip = hex('#f2c46a');
  for (let i = 1; i < 5; i++) {
    for (const sx of [1, -1]) {
      const base = [sx * 0.045, Y[i] + R[i] * 0.72, Z[i]];
      const tip = add(base, [sx * 0.03, 0.05, -0.01]);
      prims.push(
        roundCone(base, tip, 0.018, 0.003, {
          bone: names[i],
          k: 0.012,
          color: (p) => cmix(spike, spikeTip, smoothstep(0.5, 1, len(sub(p, base)) / 0.06)),
        }),
      );
      if (i <= 3) prims.push(capsule([sx * R[i] * 0.55, 0.05, Z[i]], [sx * R[i] * 0.95, 0.012, Z[i] + 0.012], 0.014, { bone: names[i], k: 0.015, color: hex('#6b3a18') }));
    }
  }
  m.sdf('body', prims, 0.012);

  // head capsule
  const headC = [0, Y[0] + 0.005, Z[0]];
  const headCol = (p) => {
    const f = (p[2] - Z[0]) / R[0];
    const c = cmix(hex('#6d2c14'), hex('#b0542a'), smoothstep(0.1, 0.9, f));
    return cmix(c, hex('#2a0f06'), Math.max(0, fbm(p, 50, 2) - 0.62) * 2);
  };
  const mandCol = (t) => cmix(hex('#f2e2b8'), hex('#5a2210'), smoothstep(0.55, 1, t));
  m.sdf(
    'chitin',
    [
      ellipsoid(headC, [0.085, 0.078, 0.078], { bone: 's0', k: 0.02, color: headCol }),
      ellipsoid(add(headC, [0, -0.03, 0.05]), [0.05, 0.03, 0.04], { bone: 's0', k: 0.03, color: headCol }),
      ...[1, -1].flatMap((sx) =>
        chain(
          [[sx * 0.045, 0.075, 0.26], [sx * 0.075, 0.068, 0.305], [sx * 0.058, 0.062, 0.35], [sx * 0.018, 0.06, 0.37]],
          [0.022, 0.017, 0.011, 0.004],
          { bone: sx > 0 ? 'mandL' : 'mandR', k: 0.01, colorAt: (t) => mandCol(t) },
        ),
      ),
    ],
    0.007,
  );
  for (const sx of [1, -1]) m.sdf('gloss', [eye([sx * 0.046, 0.132, 0.262], 0.026, [sx * 0.35, 0.25, 1], 's0', { iris: '#1a0a04', irisSize: 0.3, pupilSize: 0.45, sclera: '#1a0d08' })], 0.0035);
  for (const sx of [1, -1])
    m.add(
      'chitin',
      tube([[sx * 0.03, 0.16, 0.24], [sx * 0.045, 0.2, 0.27], [sx * 0.07, 0.22, 0.31]], {
        radius: (t) => 0.008 * (1 - t * 0.5),
        color: (t) => cmix(hex('#5a2a14'), hex('#f0b050'), smoothstep(0.7, 1, t)),
        bone: () => 's0',
        segments: 6,
        rings: 6,
      }),
    );

  // traveling undulation: lift per segment, converted to parent-relative offsets
  const parentOf = { s0: 's1', s1: 's2', s3: 's2', s4: 's3', s5: 's4' };
  const applyLift = (p, lift) => {
    for (const n of names) {
      const own = lift[n] ?? 0;
      const par = parentOf[n] ? lift[parentOf[n]] ?? 0 : 0;
      p.pos(n, [0, own - par, 0]);
    }
  };
  const mand = (p, open) => {
    p.rot('mandL', [0, open, 0]);
    p.rot('mandR', [0, -open, 0]);
  };

  m.anim('idle', 1.6, (t, p) => {
    for (let i = 1; i < 6; i++) p.scl(names[i], 1 + 0.03 * wave(t, 1.6, 1, -i * 0.12));
    p.rot('s0', [0.06 * wave(t, 1.6, 1, 0.2), 0.12 * wave(t, 1.6, 1), 0]);
    mand(p, 0.1 + 0.12 * wave(t, 1.6, 2));
  });
  m.anim('move', 0.9, (t, p) => {
    const lift = {};
    names.forEach((n, i) => {
      lift[n] = 0.024 * Math.max(0, Math.sin(TAU * (t / 0.9) - i * 0.95));
    });
    applyLift(p, lift);
    names.forEach((n, i) => p.scl(n, [1, 1, 1 + 0.1 * Math.sin(TAU * (t / 0.9) - i * 0.95)]));
    p.rot('s0', [0, 0.1 * wave(t, 0.9), 0]);
    mand(p, 0.12 + 0.1 * wave(t, 0.9, 2));
  });
  m.anim(
    'attack',
    0.7,
    (t, p) => {
      const rear = bump(t, 0, 0.36), strike = bump(t, 0.3, 0.58);
      p.rot('s1', [-0.45 * rear + 0.3 * strike, 0, 0]);
      p.rot('s0', [-0.3 * rear + 0.25 * strike, 0, 0]);
      p.pos('s1', [0, 0, 0.07 * strike]);
      p.rot('s3', [0.1 * rear, 0, 0]);
      mand(p, 0.55 * seg(t, 0, 0.32) * (1 - seg(t, 0.36, 0.44)) - 0.12 * bump(t, 0.4, 0.6));
    },
    { loop: false },
  );
  m.anim('eat', 0.9, (t, p) => {
    p.rot('s1', [0.22, 0, 0]);
    p.rot('s0', [0.28 + 0.12 * wave(t, 0.9, 2), 0, 0]);
    mand(p, 0.12 + 0.3 * Math.max(0, wave(t, 0.9, 2)));
    p.scl('s2', 1 + 0.04 * wave(t, 0.9, 2, 0.25));
  });
  m.anim(
    'hurt',
    0.45,
    (t, p) => {
      const h = bump(t, 0, 0.2);
      p.rot('s1', [-0.35 * h, 0, 0.1 * wobble(t, 0.1, 6, 9)]);
      p.rot('s3', [0.3 * h, 0, 0]);
      mand(p, 0.4 * h);
    },
    { loop: false },
  );
  m.anim(
    'die',
    1.3,
    (t, p) => {
      const f = easeOut(seg(t, 0, 0.5));
      p.rot('root', [0, 0, 1.5 * f]);
      p.pos('root', [0.02 * f, 0.07 * f, 0]);
      const c = easeInOut(seg(t, 0.2, 0.8));
      p.rot('s1', [0.4 * c, 0, 0]);
      p.rot('s0', [0.4 * c, 0, 0]);
      p.rot('s3', [-0.4 * c, 0, 0]);
      p.rot('s4', [-0.4 * c, 0, 0]);
      mand(p, 0.5 * c);
      p.scl('root', 1 - 0.99 * seg(t, 0.95, 1.3));
    },
    { loop: false },
  );
  m.anim(
    'spawn',
    0.6,
    (t, p) => {
      p.scl('root', Math.max(0.01, backOut(seg(t, 0, 0.5))));
      mand(p, 0.4 * wobble(t, 0.2, 3, 6));
    },
    { loop: false },
  );
  return m;
}

// ---------------------------------------------------------------- pupa
export function buildPupa() {
  const m = new Model('bug_pupa');
  m.material('body', { roughness: 0.65 });
  m.bone('root', null, [0, 0, 0]).bone('body', 'root', [0, 0.05, 0]).bone('top', 'body', [0, 0.24, 0]);
  const silk = hex('#efe4c6'), silkDark = hex('#b8a47a'), glow = hex('#f0a84a');
  const spiral = (p) => {
    const a = Math.atan2(p[2], p[0]);
    return Math.sin(a * 2 + p[1] * 60);
  };
  const cocoonCol = (p) => {
    const s = spiral(p);
    let c = cmix(silk, silkDark, smoothstep(0.55, 0.95, s));
    const n = fbm(p, 12, 3);
    c = cmix(c, glow, smoothstep(0.55, 0.75, n) * 0.55);
    // closed sleepy eyes
    for (const sx of [1, -1]) {
      const e = [sx * 0.042, 0.345, 0.1];
      const d = len(sub(p, e));
      if (d < 0.03 && p[1] < e[1] + 0.004 && p[1] > e[1] - 0.012) c = hex('#4a3420');
    }
    return c;
  };
  m.sdf(
    'body',
    [
      ellipsoid([0, 0.035, 0], [0.18, 0.04, 0.17], { bone: 'root', k: 0.05, color: (p) => cmix(hex('#d8d0bc'), hex('#8c8068'), fbm(p, 30, 2)), displace: (p) => 0.006 * Math.sin(Math.atan2(p[2], p[0]) * 9) }),
      ellipsoid([0, 0.2, 0], [0.12, 0.19, 0.115], { bone: 'body', k: 0.06, color: cocoonCol, displace: (p) => -0.004 * spiral(p) }),
      ellipsoid([0, 0.35, 0.02], [0.085, 0.075, 0.08], { bone: 'top', k: 0.06, color: cocoonCol, displace: (p) => -0.003 * spiral(p) }),
      ...[0, 1, 2, 3, 4].map((i) => {
        const a = (i / 5) * TAU + 0.3;
        return capsule([Math.cos(a) * 0.19, 0.012, Math.sin(a) * 0.19], [Math.cos(a) * 0.07, 0.16, Math.sin(a) * 0.07], 0.006, { bone: 'body', k: 0.02, color: hex('#f4efe0') });
      }),
    ],
    0.009,
  );
  m.anim('idle', 2.0, (t, p) => {
    p.rot('body', [0.03 * wave(t, 2, 1, 0.25), 0, 0.05 * wave(t, 2)]);
    const beat = Math.pow(Math.max(0, wave(t, 1.0, 1)), 8) + 0.6 * Math.pow(Math.max(0, wave(t, 1.0, 1, -0.12)), 8);
    p.scl('body', [1 + 0.03 * beat, 1 + 0.02 * beat, 1 + 0.03 * beat]);
    p.rot('top', [0.05 * wave(t, 2, 1, 0.5), 0, 0]);
  });
  m.anim(
    'hatch',
    1.4,
    (t, p) => {
      const shake = seg(t, 0, 1.0);
      const f = 6 + 18 * shake;
      p.rot('body', [0.05 * shake * Math.sin(t * f * 1.3), 0, 0.14 * shake * Math.sin(t * f)]);
      p.scl('body', [1 - 0.08 * bump(t, 0.9, 1.15), 1 + 0.25 * bump(t, 0.9, 1.15), 1 - 0.08 * bump(t, 0.9, 1.15)]);
      p.scl('top', 1 + 0.25 * seg(t, 0.95, 1.15));
      p.scl('root', 1 - 0.99 * seg(t, 1.15, 1.4));
    },
    { loop: false },
  );
  m.anim(
    'hurt',
    0.45,
    (t, p) => {
      p.rot('body', [0, 0, 0.15 * wobble(t, 0, 5, 7)]);
      p.scl('body', [1, 1 - 0.1 * bump(t, 0, 0.2), 1]);
    },
    { loop: false },
  );
  m.anim(
    'die',
    1.2,
    (t, p) => {
      const f = easeIn(seg(t, 0, 0.8));
      p.scl('body', [1 + 0.2 * f, 1 - 0.6 * f, 1 + 0.2 * f]);
      p.rot('body', [0, 0, 0.4 * f]);
      p.scl('root', 1 - 0.99 * seg(t, 0.85, 1.2));
    },
    { loop: false },
  );
  m.anim(
    'spawn',
    0.8,
    (t, p) => {
      p.scl('root', Math.max(0.01, backOut(seg(t, 0, 0.6))));
      p.rot('body', [0, 0.8 * (1 - easeOut(seg(t, 0, 0.8))), 0]);
    },
    { loop: false },
  );
  return m;
}

// ---------------------------------------------------------------- adult
export function buildAdult() {
  const m = new Model('bug_adult');
  m.material('armor', { roughness: 0.28, metallic: 0.15 });
  m.material('gloss', { roughness: 0.08 });
  m.material('wing', { roughness: 0.25, alpha: 0.55, doubleSided: true });

  m.bone('root', null, [0, 0, 0]);
  m.bone('thorax', 'root', [0, 0.2, 0.03]);
  m.bone('head', 'thorax', [0, 0.24, 0.12]);
  m.bone('mandL', 'head', [0.035, 0.21, 0.21]);
  m.bone('mandR', 'head', [-0.035, 0.21, 0.21]);
  m.bone('abdomen', 'thorax', [0, 0.23, -0.05]);
  m.bone('sting', 'abdomen', [0, 0.2, -0.31]);
  m.bone('wingL', 'thorax', [0.04, 0.3, 0.0]);
  m.bone('wingR', 'thorax', [-0.04, 0.3, 0.0]);
  const legZ = [0.09, 0.03, -0.04];
  const legs = [];
  for (const [side, sx] of [['L', 1], ['R', -1]])
    legZ.forEach((z, i) => {
      const hip = [sx * 0.07, 0.19, z];
      const knee = [sx * 0.155, 0.23, z * 1.35 + (i - 1) * -0.03];
      const foot = [sx * 0.215, 0.0, z * 1.6 + (i - 1) * -0.055];
      const up = `leg${side}${i}u`, lo = `leg${side}${i}l`;
      m.bone(up, 'thorax', hip).bone(lo, up, knee);
      legs.push({ side, sx, i, hip, knee, foot, up, lo });
    });

  const armor = hex('#2c2138'), armorHi = hex('#5a3f78'), orange = hex('#f2a41f'), black = hex('#1a1320');
  const armorCol = (p) => {
    const n = fbm(p, 25, 2);
    return cmix(armor, armorHi, smoothstep(0.1, 0.4, p[1] - 0.18) * 0.6 + Math.max(0, n - 0.55));
  };
  const abdC = [0, 0.225, -0.19];
  const abdRot = qEuler(0.18, 0, 0);
  const abdCol = (p) => {
    const lz = qRotate(qEuler(-0.18, 0, 0), sub(p, abdC))[2];
    const band = Math.floor((lz + 0.2) / 0.052);
    let c = band % 2 === 0 ? orange : black;
    if (band <= 0) c = black;
    const n = fbm(p, 40, 2);
    return cmix(c, band % 2 === 0 ? hex('#ffd264') : hex('#3a2a48'), Math.max(0, n - 0.5) * 1.5);
  };
  const prims = [
    ellipsoid([0, 0.22, 0.03], [0.09, 0.082, 0.095], { bone: 'thorax', k: 0.03, color: armorCol }),
    ellipsoid([0, 0.27, 0.02], [0.07, 0.04, 0.07], { bone: 'thorax', k: 0.03, color: armorCol }),
    ellipsoid(abdC, [0.105, 0.095, 0.165], {
      bone: 'abdomen',
      rot: abdRot,
      k: 0.025,
      color: abdCol,
      displace: (p) => {
        const lz = qRotate(qEuler(-0.18, 0, 0), sub(p, abdC))[2];
        return 0.004 * Math.cos(((lz + 0.2) / 0.052) * TAU);
      },
    }),
    roundCone([0, 0.2, -0.32], [0, 0.16, -0.41], 0.022, 0.002, { bone: 'sting', k: 0.02, color: (p) => cmix(black, hex('#c83a2a'), smoothstep(-0.36, -0.41, p[2])) }),
    // head + horn
    sphere([0, 0.25, 0.15], 0.072, { bone: 'head', k: 0.025, color: armorCol }),
    ...chain([[0, 0.29, 0.18], [0, 0.34, 0.235], [0, 0.39, 0.265], [0, 0.425, 0.25]], [0.032, 0.024, 0.014, 0.004], {
      bone: 'head',
      k: 0.02,
      colorAt: (t) => cmix(hex('#6a4a8a'), hex('#f2c85a'), smoothstep(0.2, 0.9, t)),
    }),
    // mandibles
    ...[1, -1].flatMap((sx) =>
      chain([[sx * 0.035, 0.205, 0.2], [sx * 0.055, 0.195, 0.24], [sx * 0.042, 0.188, 0.272], [sx * 0.012, 0.185, 0.285]], [0.015, 0.011, 0.007, 0.0025], {
        bone: sx > 0 ? 'mandL' : 'mandR',
        k: 0.008,
        colorAt: (t) => cmix(hex('#b8742a'), hex('#3a1208'), smoothstep(0.4, 1, t)),
      }),
    ),
  ];
  // legs: segments with orange joints
  for (const L of legs) {
    prims.push(roundCone(L.hip, L.knee, 0.03, 0.021, { bone: L.up, k: 0.012, color: armorCol, boneBlend: 0.02 }));
    prims.push(sphere(L.knee, 0.02, { bone: L.lo, k: 0.008, color: orange, boneBlend: 0.015 }));
    prims.push(roundCone(L.knee, L.foot, 0.02, 0.007, { bone: L.lo, k: 0.008, color: (p) => cmix(armor, black, smoothstep(0.1, 0.0, p[1])), boneBlend: 0.02 }));
    prims.push(roundCone(add(L.knee, [0, 0.005, 0]), add(L.knee, [L.sx * 0.02, 0.045, -0.01]), 0.01, 0.002, { bone: L.lo, k: 0.006, color: orange }));
  }
  m.sdf('armor', prims, 0.0105);
  // compound eyes
  for (const sx of [1, -1])
    m.sdf(
      'gloss',
      [
        ellipsoid([sx * 0.055, 0.27, 0.185], [0.032, 0.038, 0.032], {
          bone: 'head',
          k: 0,
          color: (p) => {
            const d = norm(sub(p, [sx * 0.055, 0.27, 0.185]));
            if (d[1] > 0.55 && d[2] > 0.3) return hex('#ffd0c0');
            return cmix(hex('#c8201c'), hex('#5a0808'), Math.max(0, fbm(p, 160, 1) - 0.4) * 2);
          },
        }),
      ],
      0.004,
    );
  // antennae
  for (const sx of [1, -1])
    m.add(
      'armor',
      tube([[sx * 0.025, 0.3, 0.19], [sx * 0.05, 0.37, 0.24], [sx * 0.09, 0.41, 0.29], [sx * 0.13, 0.42, 0.32]], {
        radius: (t) => (t > 0.85 ? 0.011 : 0.007),
        color: (t) => (t > 0.85 ? orange : armor),
        bone: () => 'head',
        segments: 6,
        rings: 14,
      }),
    );
  // wings
  const wingCol = (u, x) => {
    const edge = smoothstep(0.75, 1, Math.abs(x)) + smoothstep(0.9, 1, u);
    const vein = Math.abs(x) < 0.06 || Math.abs(Math.abs(x) - 0.5) < 0.05 || Math.abs(Math.sin(u * 14)) < 0.08;
    const c = cmix(hex('#f7d67a'), hex('#e9a93a'), u);
    return vein ? hex('#7a4a14') : cmix(c, hex('#8a5a1a'), edge * 0.7);
  };
  for (const [sx, bone] of [[1, 'wingL'], [-1, 'wingR']]) {
    for (const [len2, wid, dir, org] of [
      [0.3, 0.065, [sx * 0.42, 0.28, -1], [sx * 0.04, 0.3, 0.02]],
      [0.23, 0.052, [sx * 0.75, 0.18, -0.8], [sx * 0.045, 0.29, 0.0]],
    ]) {
      const d = norm(dir);
      const side = norm([d[2], 0, -d[0]]);
      m.add(
        'wing',
        blade({
          origin: org,
          dir: d,
          side,
          up: [0, 1, 0],
          length: len2,
          width: (u) => wid * Math.pow(Math.sin(Math.PI * Math.min(1, 0.08 + u * 0.95)), 0.55),
          cup: 0.05,
          curl: (u) => -0.02 * u * u,
          color: wingCol,
          bone,
          nu: 12,
          nv: 6,
          thickness: 0.002,
        }),
      );
    }
  }

  const mand = (p, open) => {
    p.rot('mandL', [0, open, 0]);
    p.rot('mandR', [0, -open, 0]);
  };
  const wings = (p, lift, spread = 0) => {
    p.rot('wingL', [0, spread, lift]);
    p.rot('wingR', [0, -spread, -lift]);
  };
  const legPose = (p, L, swing, liftAmt) => {
    // swing: rotate about Y (forward/back); lift: raise the knee
    p.rot(L.up, [0, swing * L.sx, liftAmt * L.sx]);
    p.rot(L.lo, [0, 0, -liftAmt * 0.5 * L.sx]);
  };

  m.anim('idle', 1.4, (t, p) => {
    p.pos('thorax', [0, 0.006 * wave(t, 1.4), 0]);
    p.rot('abdomen', [0.05 * wave(t, 1.4, 1, 0.2), 0, 0]);
    p.rot('head', [0.04 * wave(t, 1.4, 1, 0.4), 0.12 * wave(t, 1.4, 1), 0]);
    wings(p, 0.08 + 0.05 * wave(t, 1.4, 4), 0.05 * wave(t, 1.4, 2));
    mand(p, 0.1 + 0.1 * Math.max(0, wave(t, 1.4, 2)));
  });
  m.anim('move', 0.6, (t, p) => {
    const ph = TAU * (t / 0.6);
    for (const L of legs) {
      const group = (L.i + (L.side === 'L' ? 0 : 1)) % 2;
      const s = Math.sin(ph + group * Math.PI);
      legPose(p, L, 0.32 * s, 0.35 * Math.max(0, Math.cos(ph + group * Math.PI)));
    }
    p.pos('thorax', [0, 0.01 * Math.abs(Math.sin(ph)), 0]);
    p.rot('thorax', [0, 0, 0.04 * Math.sin(ph)]);
    p.rot('abdomen', [0.04 * Math.sin(ph * 2), 0.06 * Math.sin(ph), 0]);
    wings(p, 0.1, 0);
    mand(p, 0.15);
  });
  m.anim(
    'attack',
    0.8,
    (t, p) => {
      const rear = bump(t, 0, 0.42), strike = bump(t, 0.36, 0.62), after = wobble(t, 0.6, 3, 8);
      p.rot('thorax', [-0.5 * rear + 0.32 * strike, 0, 0]);
      p.pos('thorax', [0, 0.04 * rear, 0.06 * strike]);
      p.rot('head', [-0.2 * rear + 0.2 * strike, 0, 0]);
      p.rot('abdomen', [0.3 * rear - 0.1 * strike, 0, 0]);
      wings(p, 0.1 + 0.7 * rear + 0.2 * after, 0.3 * rear);
      mand(p, 0.6 * seg(t, 0, 0.38) * (1 - seg(t, 0.42, 0.5)) - 0.1 * strike);
      for (const L of legs) if (L.i === 0) legPose(p, L, 0.6 * rear, 0.5 * rear);
    },
    { loop: false },
  );
  m.anim(
    'lay_egg',
    1.6,
    (t, p) => {
      const f = bump(t, 0, 1.6);
      const pump = Math.max(0, Math.sin(seg(t, 0.3, 1.3) * TAU * 3));
      p.rot('abdomen', [-0.45 * f - 0.12 * pump, 0, 0]);
      p.rot('sting', [-0.3 * f, 0, 0]);
      p.scl('abdomen', [1 + 0.06 * pump, 1 + 0.06 * pump, 1]);
      p.rot('thorax', [-0.1 * f, 0, 0]);
      wings(p, 0.25 * f, 0.1 * f);
    },
    { loop: false },
  );
  m.anim(
    'hurt',
    0.45,
    (t, p) => {
      const h = bump(t, 0, 0.22);
      p.rot('thorax', [-0.25 * h, 0, 0.12 * wobble(t, 0.1, 6, 9)]);
      wings(p, 0.5 * h, 0);
      mand(p, 0.5 * h);
    },
    { loop: false },
  );
  m.anim(
    'die',
    1.5,
    (t, p) => {
      const flip = easeInOut(seg(t, 0.05, 0.55));
      p.rot('root', [0, 0, Math.PI * flip]);
      p.pos('root', [0, 0.46 * flip + 0.12 * bump(t, 0.05, 0.55), 0]);
      const curl = easeOut(seg(t, 0.4, 1.0));
      const twitch = 0.15 * Math.sin(t * 40) * (1 - seg(t, 0.5, 1.1));
      for (const L of legs) {
        p.rot(L.up, [0, 0, (0.6 * curl + twitch) * L.sx]);
        p.rot(L.lo, [0, 0, 0.9 * curl * L.sx]);
      }
      wings(p, -0.2 * curl, 0);
      mand(p, 0.5 * curl);
      p.scl('root', 1 - 0.99 * seg(t, 1.15, 1.5));
    },
    { loop: false },
  );
  m.anim(
    'spawn',
    0.9,
    (t, p) => {
      p.scl('root', Math.max(0.01, backOut(seg(t, 0, 0.5))));
      const w = bump(t, 0.2, 0.9);
      wings(p, 0.1 + 0.8 * w, 0.2 * w);
      p.rot('thorax', [-0.2 * w, 0, 0]);
    },
    { loop: false },
  );
  return m;
}
