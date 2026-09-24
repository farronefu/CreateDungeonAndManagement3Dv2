// Signed-distance modelling + surface-nets meshing.
//
// A "group" is a list of primitives that are smooth-unioned (or smooth-subtracted)
// into one closed surface. Each primitive carries a colour and the bone it belongs
// to; after meshing, vertex colours and skin weights are blended from nearby
// primitives, so soft organic shapes deform smoothly.

import { add, sub, mul, dot, len, norm, clamp, qConj, qRotate } from './math.mjs';

// ---------- primitive distance functions (local space) ----------
function sdEllipsoid(p, r) {
  const k0 = Math.hypot(p[0] / r[0], p[1] / r[1], p[2] / r[2]);
  const k1 = Math.hypot(p[0] / (r[0] * r[0]), p[1] / (r[1] * r[1]), p[2] / (r[2] * r[2]));
  if (k1 === 0) return -Math.min(r[0], r[1], r[2]);
  return (k0 * (k0 - 1)) / k1;
}

function sdRoundCone(p, a, b, r1, r2) {
  const ba = sub(b, a);
  const l2 = dot(ba, ba);
  const rr = r1 - r2;
  const a2 = l2 - rr * rr;
  const il2 = 1 / l2;
  const pa = sub(p, a);
  const y = dot(pa, ba);
  const z = y - l2;
  const q = sub(mul(pa, l2), mul(ba, y));
  const x2 = dot(q, q);
  const y2 = y * y * l2;
  const z2 = z * z * l2;
  const k = Math.sign(rr) * rr * rr * x2;
  if (Math.sign(z) * a2 * z2 > k) return Math.sqrt(x2 + z2) * il2 - r2;
  if (Math.sign(y) * a2 * y2 < k) return Math.sqrt(x2 + y2) * il2 - r1;
  return (Math.sqrt(x2 * a2 * il2) + y * rr) * il2 - r1;
}

function sdRoundBox(p, b, r) {
  const q = [Math.abs(p[0]) - b[0] + r, Math.abs(p[1]) - b[1] + r, Math.abs(p[2]) - b[2] + r];
  const o = [Math.max(q[0], 0), Math.max(q[1], 0), Math.max(q[2], 0)];
  return len(o) + Math.min(Math.max(q[0], q[1], q[2]), 0) - r;
}

function sdTorus(p, R, r) {
  const qx = Math.hypot(p[0], p[2]) - R;
  return Math.hypot(qx, p[1]) - r;
}

// ---------- primitive constructors ----------
function makePrim(kind, dist, opts, bounds) {
  return {
    kind,
    dist,
    bone: opts.bone ?? 'root',
    color: opts.color ?? [0.8, 0.8, 0.8],
    k: opts.k ?? 0.02,
    op: opts.op ?? 'add',
    blend: opts.blend ?? 0.012,
    boneBlend: opts.boneBlend ?? 0.05,
    displace: opts.displace ?? null,
    bounds,
  };
}

function withRot(center, rot, fn) {
  if (!rot) return (p) => fn(sub(p, center));
  const inv = qConj(rot);
  return (p) => fn(qRotate(inv, sub(p, center)));
}

export function sphere(c, r, opts = {}) {
  return makePrim('sphere', (p) => len(sub(p, c)) - r, opts, box(c, r));
}
export function ellipsoid(c, radii, opts = {}) {
  const m = Math.max(...radii);
  return makePrim('ellipsoid', withRot(c, opts.rot, (q) => sdEllipsoid(q, radii)), opts, box(c, m));
}
export function roundCone(a, b, ra, rb, opts = {}) {
  const m = Math.max(ra, rb);
  const bb = { min: [Math.min(a[0], b[0]) - m, Math.min(a[1], b[1]) - m, Math.min(a[2], b[2]) - m], max: [Math.max(a[0], b[0]) + m, Math.max(a[1], b[1]) + m, Math.max(a[2], b[2]) + m] };
  if (Math.abs(ra - rb) >= len(sub(b, a)) * 0.999) {
    // degenerate: one sphere contains the other
    const big = ra > rb ? [a, ra] : [b, rb];
    return makePrim('sphere', (p) => len(sub(p, big[0])) - big[1], opts, bb);
  }
  return makePrim('roundCone', (p) => sdRoundCone(p, a, b, ra, rb), opts, bb);
}
export function capsule(a, b, r, opts = {}) {
  return roundCone(a, b, r, r * 0.999, opts);
}
export function roundBox(c, half, r, opts = {}) {
  const m = Math.hypot(...half);
  return makePrim('roundBox', withRot(c, opts.rot, (q) => sdRoundBox(q, half, r)), opts, box(c, m));
}
export function torus(c, R, r, opts = {}) {
  return makePrim('torus', withRot(c, opts.rot, (q) => sdTorus(q, R, r)), opts, box(c, R + r));
}
// A tapered chain of round cones through a list of points (horns, mandibles, legs).
export function chain(points, radii, opts = {}) {
  const out = [];
  for (let i = 0; i < points.length - 1; i++) {
    const o = { ...opts };
    if (Array.isArray(opts.bones)) o.bone = opts.bones[Math.min(i, opts.bones.length - 1)];
    if (typeof opts.colorAt === 'function') {
      const t0 = i / (points.length - 1), t1 = (i + 1) / (points.length - 1);
      const a = points[i], b = points[i + 1];
      o.color = (p) => {
        const ab = sub(b, a);
        const t = clamp(dot(sub(p, a), ab) / dot(ab, ab), 0, 1);
        return opts.colorAt(t0 + (t1 - t0) * t, p);
      };
    }
    out.push(roundCone(points[i], points[i + 1], radii[i], radii[i + 1], o));
  }
  return out;
}

function box(c, r) {
  return { min: [c[0] - r, c[1] - r, c[2] - r], max: [c[0] + r, c[1] + r, c[2] + r] };
}

// ---------- group evaluation ----------
const smin = (a, b, k) => {
  if (k <= 0) return Math.min(a, b);
  const h = Math.max(k - Math.abs(a - b), 0) / k;
  return Math.min(a, b) - h * h * k * 0.25;
};
const smax = (a, b, k) => -smin(-a, -b, k);

function primDist(pr, p) {
  let d = pr.dist(p);
  if (pr.displace) d += pr.displace(p);
  return d;
}

export function groupSDF(prims) {
  return (p) => {
    let d = 1e9;
    for (const pr of prims) {
      const di = primDist(pr, p);
      if (pr.op === 'sub') d = smax(d, -di, pr.k);
      else d = d === 1e9 ? di : smin(d, di, pr.k);
    }
    return d;
  };
}

function groupBounds(prims, pad) {
  const min = [1e9, 1e9, 1e9], max = [-1e9, -1e9, -1e9];
  for (const pr of prims) {
    if (pr.op === 'sub') continue;
    for (let i = 0; i < 3; i++) {
      min[i] = Math.min(min[i], pr.bounds.min[i] - pad);
      max[i] = Math.max(max[i], pr.bounds.max[i] + pad);
    }
  }
  return { min, max };
}

// ---------- surface nets ----------
export function meshGroup(prims, cell) {
  const f = groupSDF(prims);
  const { min, max } = groupBounds(prims, cell * 3);
  const nx = Math.ceil((max[0] - min[0]) / cell) + 1;
  const ny = Math.ceil((max[1] - min[1]) / cell) + 1;
  const nz = Math.ceil((max[2] - min[2]) / cell) + 1;
  const idx = (i, j, k) => i + nx * (j + ny * k);
  const vals = new Float32Array(nx * ny * nz);
  for (let k = 0; k < nz; k++)
    for (let j = 0; j < ny; j++)
      for (let i = 0; i < nx; i++)
        vals[idx(i, j, k)] = f([min[0] + i * cell, min[1] + j * cell, min[2] + k * cell]);

  // one vertex per sign-changing cell
  const cellVert = new Int32Array((nx - 1) * (ny - 1) * (nz - 1)).fill(-1);
  const cidx = (i, j, k) => i + (nx - 1) * (j + (ny - 1) * k);
  const positions = [];
  const EDGES = [
    [0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7],
  ];
  const corner = new Float32Array(8);
  for (let k = 0; k < nz - 1; k++)
    for (let j = 0; j < ny - 1; j++)
      for (let i = 0; i < nx - 1; i++) {
        let inside = 0;
        for (let c = 0; c < 8; c++) {
          const v = vals[idx(i + (c & 1), j + ((c >> 1) & 1), k + ((c >> 2) & 1))];
          corner[c] = v;
          if (v < 0) inside++;
        }
        if (inside === 0 || inside === 8) continue;
        let sx = 0, sy = 0, sz = 0, n = 0;
        for (const [a, b] of EDGES) {
          const va = corner[a], vb = corner[b];
          if (va < 0 === vb < 0) continue;
          const t = va / (va - vb);
          const ax = a & 1, ay = (a >> 1) & 1, az = (a >> 2) & 1;
          const bx = b & 1, by = (b >> 1) & 1, bz = (b >> 2) & 1;
          sx += ax + (bx - ax) * t;
          sy += ay + (by - ay) * t;
          sz += az + (bz - az) * t;
          n++;
        }
        let p = [min[0] + (i + sx / n) * cell, min[1] + (j + sy / n) * cell, min[2] + (k + sz / n) * cell];
        // project onto the true surface for smoother results
        for (let it = 0; it < 3; it++) {
          const d = f(p);
          const g = gradient(f, p, cell * 0.5);
          const step = clamp(d, -cell * 0.6, cell * 0.6);
          p = sub(p, mul(g, step));
        }
        cellVert[cidx(i, j, k)] = positions.length;
        positions.push(p);
      }

  const tris = [];
  const quad = (a, b, c, d, flip) => {
    if (a < 0 || b < 0 || c < 0 || d < 0) return;
    if (flip) [b, d] = [d, b];
    // split along the shorter diagonal
    const ac = len(sub(positions[a], positions[c]));
    const bd = len(sub(positions[b], positions[d]));
    if (ac <= bd) tris.push(a, b, c, a, c, d);
    else tris.push(a, b, d, b, c, d);
  };
  for (let k = 0; k < nz; k++)
    for (let j = 0; j < ny; j++)
      for (let i = 0; i < nx; i++) {
        const v0 = vals[idx(i, j, k)];
        if (i < nx - 1 && j > 0 && k > 0 && j < ny - 1 && k < nz - 1) {
          const v1 = vals[idx(i + 1, j, k)];
          if (v0 < 0 !== v1 < 0)
            quad(cellVert[cidx(i, j - 1, k - 1)], cellVert[cidx(i, j, k - 1)], cellVert[cidx(i, j, k)], cellVert[cidx(i, j - 1, k)], !(v0 < 0));
        }
        if (j < ny - 1 && i > 0 && k > 0 && i < nx - 1 && k < nz - 1) {
          const v1 = vals[idx(i, j + 1, k)];
          if (v0 < 0 !== v1 < 0)
            quad(cellVert[cidx(i - 1, j, k - 1)], cellVert[cidx(i - 1, j, k)], cellVert[cidx(i, j, k)], cellVert[cidx(i, j, k - 1)], !(v0 < 0));
        }
        if (k < nz - 1 && i > 0 && j > 0 && i < nx - 1 && j < ny - 1) {
          const v1 = vals[idx(i, j, k + 1)];
          if (v0 < 0 !== v1 < 0)
            quad(cellVert[cidx(i - 1, j - 1, k)], cellVert[cidx(i, j - 1, k)], cellVert[cidx(i, j, k)], cellVert[cidx(i - 1, j, k)], !(v0 < 0));
        }
      }

  const normals = positions.map((p) => gradient(f, p, cell * 0.35));
  return { positions, normals, tris };
}

function gradient(f, p, e) {
  const dx = f([p[0] + e, p[1], p[2]]) - f([p[0] - e, p[1], p[2]]);
  const dy = f([p[0], p[1] + e, p[2]]) - f([p[0], p[1] - e, p[2]]);
  const dz = f([p[0], p[1], p[2] + e]) - f([p[0], p[1], p[2] - e]);
  return norm([dx, dy, dz]);
}

// Vertex colour + skin weights from the primitives nearest to each vertex.
export function shadeGroup(prims, mesh) {
  const colors = [], bones = [];
  for (const p of mesh.positions) {
    const ds = prims.map((pr) => Math.abs(primDist(pr, p)));
    const dmin = Math.min(...ds);
    let cw = 0, c = [0, 0, 0];
    const bw = {};
    ds.forEach((d, i) => {
      const pr = prims[i];
      const w = Math.exp(-(d - dmin) / pr.blend);
      if (w > 1e-4) {
        const col = typeof pr.color === 'function' ? pr.color(p) : pr.color;
        c = add(c, mul(col, w));
        cw += w;
      }
      const wb = Math.exp(-(d - dmin) / pr.boneBlend);
      bw[pr.bone] = (bw[pr.bone] || 0) + wb;
    });
    colors.push(cw > 0 ? mul(c, 1 / cw) : [1, 0, 1]);
    bones.push(bw);
  }
  return { ...mesh, colors, bones };
}
