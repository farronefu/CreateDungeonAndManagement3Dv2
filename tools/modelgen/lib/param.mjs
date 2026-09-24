// Parametric surfaces for thin parts that SDF meshing can't resolve well:
// leaves, petals, wings, capes, antennae.

import { add, sub, mul, cross, norm, len, dot, lerp } from './math.mjs';

const boneMap = (b) => (typeof b === 'string' ? { [b]: 1 } : b);

// fn(u, v) -> { p, c, b } with u, v in [0, 1].
export function grid(nu, nv, fn, opts = {}) {
  const { closedV = false, doubleSided = false, thickness = 0.004, backColor = null } = opts;
  const cols = closedV ? nv : nv + 1;
  const samples = [];
  for (let i = 0; i <= nu; i++)
    for (let j = 0; j < cols; j++) {
      const u = i / nu, v = j / nv;
      const s = fn(u, v);
      samples.push({ ...s, u, v, b: boneMap(s.b) });
    }
  const id = (i, j) => i * cols + (closedV ? j % nv : j);
  const tris = [];
  for (let i = 0; i < nu; i++)
    for (let j = 0; j < nv; j++) {
      const a = id(i, j), b = id(i + 1, j), c = id(i + 1, j + 1), d = id(i, j + 1);
      tris.push(a, b, c, a, c, d);
    }
  const positions = samples.map((s) => s.p);
  const normals = computeNormals(positions, tris);
  const front = {
    positions: positions.map((p, k) => (doubleSided ? add(p, mul(normals[k], thickness * 0.5)) : p)),
    normals,
    tris,
    colors: samples.map((s) => s.c),
    bones: samples.map((s) => s.b),
  };
  if (!doubleSided) return front;
  const n0 = positions.length;
  const back = {
    positions: positions.map((p, k) => add(p, mul(normals[k], -thickness * 0.5))),
    normals: normals.map((n) => mul(n, -1)),
    colors: samples.map((s) => (backColor ? backColor(s.u, s.v, s.c) : s.c)),
    bones: samples.map((s) => s.b),
    tris: [],
  };
  for (let t = 0; t < tris.length; t += 3) back.tris.push(tris[t] + n0, tris[t + 2] + n0, tris[t + 1] + n0);
  return merge([front, { ...back, tris: back.tris.map((x) => x - n0) }]);
}

export function computeNormals(positions, tris) {
  const acc = positions.map(() => [0, 0, 0]);
  for (let t = 0; t < tris.length; t += 3) {
    const [a, b, c] = [tris[t], tris[t + 1], tris[t + 2]];
    const n = cross(sub(positions[b], positions[a]), sub(positions[c], positions[a]));
    acc[a] = add(acc[a], n);
    acc[b] = add(acc[b], n);
    acc[c] = add(acc[c], n);
  }
  return acc.map((n) => (len(n) > 1e-12 ? norm(n) : [0, 1, 0]));
}

// Tube along a polyline. radius(t), color(t, angle), bone(t) -> string | map.
export function tube(points, { radius, color, bone, segments = 10, rings = 16 }) {
  // resample by arc length for even rings
  const lens = [0];
  for (let i = 1; i < points.length; i++) lens.push(lens[i - 1] + len(sub(points[i], points[i - 1])));
  const total = lens[lens.length - 1];
  const at = (t) => {
    const s = t * total;
    let i = 1;
    while (i < lens.length - 1 && lens[i] < s) i++;
    const f = (s - lens[i - 1]) / (lens[i] - lens[i - 1] || 1);
    return lerp(points[i - 1], points[i], f);
  };
  const pts = [], tans = [];
  for (let i = 0; i <= rings; i++) {
    const t = i / rings;
    pts.push(at(t));
    tans.push(norm(sub(at(Math.min(1, t + 0.01)), at(Math.max(0, t - 0.01)))));
  }
  // parallel transport frame
  let nrm = norm(cross(tans[0], Math.abs(tans[0][1]) < 0.9 ? [0, 1, 0] : [1, 0, 0]));
  const frames = [];
  for (let i = 0; i <= rings; i++) {
    if (i > 0) {
      const b = cross(tans[i - 1], tans[i]);
      if (len(b) > 1e-6) {
        const axis = norm(b);
        const ang = Math.acos(Math.max(-1, Math.min(1, dot(tans[i - 1], tans[i]))));
        nrm = rotateAxis(nrm, axis, ang);
      }
    }
    frames.push({ n: nrm, b: norm(cross(tans[i], nrm)) });
  }
  return grid(
    rings,
    segments,
    (u, v) => {
      const i = Math.round(u * rings);
      const a = -v * Math.PI * 2;
      const r = radius(u);
      const { n, b } = frames[i];
      const p = add(pts[i], add(mul(n, Math.cos(a) * r), mul(b, Math.sin(a) * r)));
      return { p, c: color(u, a), b: bone(u) };
    },
    { closedV: true },
  );
}

function rotateAxis(v, k, a) {
  const c = Math.cos(a), s = Math.sin(a);
  return add(add(mul(v, c), mul(cross(k, v), s)), mul(k, dot(k, v) * (1 - c)));
}

export function merge(meshes) {
  const out = { positions: [], normals: [], colors: [], bones: [], tris: [] };
  for (const m of meshes) {
    const base = out.positions.length;
    out.positions.push(...m.positions);
    out.normals.push(...m.normals);
    out.colors.push(...m.colors);
    out.bones.push(...m.bones);
    for (const t of m.tris) out.tris.push(t + base);
  }
  return out;
}

// Leaf / petal blade: base at `origin`, growing along `dir`, spreading along `side`,
// cupped towards `up`. width(u) gives half-width, curl(u) bends along the length.
export function blade({ origin, dir, side, up, length, width, cup = 0, curl = () => 0, color, bone, nu = 10, nv = 6, doubleSided = true, backColor = null, thickness = 0.004 }) {
  const d = norm(dir), s = norm(side), n = norm(up);
  const flip = dot(cross(d, s), n) < 0;
  return grid(
    nu,
    nv,
    (u, v) => {
      const x = flip ? (0.5 - v) * 2 : (v - 0.5) * 2; // -1..1 across, front faces `up`
      const w = width(u);
      const along = u * length;
      const bend = curl(u);
      const lift = cup * x * x * w + bend;
      const p = add(origin, add(mul(d, along), add(mul(s, x * w), mul(n, lift))));
      return { p, c: color(u, x), b: typeof bone === 'function' ? bone(u) : bone };
    },
    { doubleSided, backColor: backColor ? (u, v, c) => backColor(u, (v - 0.5) * 2, c) : null, thickness },
  );
}
