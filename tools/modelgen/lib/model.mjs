// Model = skeleton + skinned parts + keyframed animations, written out as GLB.

import fs from 'node:fs';
import { sub, qEuler, qMul, qIdentity, qNormalize } from './math.mjs';
import { meshGroup, shadeGroup } from './sdf.mjs';
import { merge } from './param.mjs';

export const FPS = 30;

export class Model {
  constructor(name) {
    this.name = name;
    this.bones = [];
    this.boneIndex = {};
    this.materials = {};
    this.parts = []; // { material, mesh }
    this.anims = [];
  }

  bone(name, parent, head) {
    const b = { name, parent: parent ?? null, head, index: this.bones.length };
    this.bones.push(b);
    this.boneIndex[name] = b.index;
    return this;
  }

  material(name, props) {
    this.materials[name] = { name, roughness: 0.8, metallic: 0, ...props };
    return this;
  }

  // SDF group -> mesh
  sdf(material, prims, cell = 0.01) {
    const raw = meshGroup(prims, cell);
    this.parts.push({ material, mesh: shadeGroup(prims, raw) });
    return this;
  }

  // explicit mesh (from param.mjs)
  add(material, mesh) {
    this.parts.push({ material, mesh });
    return this;
  }

  // fn(t, pose) where pose.rot(bone, [x, y, z]) / pose.pos(bone, [dx, dy, dz]) / pose.scl(bone, s | [sx, sy, sz])
  anim(name, duration, fn, { loop = true } = {}) {
    this.anims.push({ name, duration, fn, loop });
    return this;
  }

  stats() {
    let v = 0, t = 0;
    for (const p of this.parts) {
      v += p.mesh.positions.length;
      t += p.mesh.tris.length / 3;
    }
    return { vertices: v, triangles: t, bones: this.bones.length, anims: this.anims.map((a) => a.name) };
  }

  write(file) {
    fs.writeFileSync(file, buildGLB(this));
  }
}

class Pose {
  constructor(model) {
    this.r = {};
    this.p = {};
    this.s = {};
    for (const b of model.bones) {
      this.r[b.name] = qIdentity();
      this.p[b.name] = [0, 0, 0];
      this.s[b.name] = [1, 1, 1];
    }
  }
  rot(bone, e) {
    this.r[bone] = qMul(this.r[bone], qEuler(e[0] || 0, e[1] || 0, e[2] || 0));
    return this;
  }
  rotq(bone, q) {
    this.r[bone] = qMul(this.r[bone], q);
    return this;
  }
  pos(bone, d) {
    const p = this.p[bone];
    this.p[bone] = [p[0] + (d[0] || 0), p[1] + (d[1] || 0), p[2] + (d[2] || 0)];
    return this;
  }
  scl(bone, s) {
    const v = typeof s === 'number' ? [s, s, s] : s;
    const c = this.s[bone];
    this.s[bone] = [c[0] * v[0], c[1] * v[1], c[2] * v[2]];
    return this;
  }
}

// ---------------- GLB writer ----------------
function buildGLB(model) {
  const bin = [];
  let binLength = 0;
  const gltf = {
    asset: { version: '2.0', generator: 'CDM3D modelgen' },
    scene: 0,
    scenes: [{ name: model.name, nodes: [] }],
    nodes: [],
    meshes: [],
    materials: [],
    buffers: [],
    bufferViews: [],
    accessors: [],
  };

  function pushView(typed, target) {
    const pad = (4 - (binLength % 4)) % 4;
    if (pad) {
      bin.push(Buffer.alloc(pad));
      binLength += pad;
    }
    const buf = Buffer.from(typed.buffer, typed.byteOffset, typed.byteLength);
    const view = { buffer: 0, byteOffset: binLength, byteLength: buf.length };
    if (target) view.target = target;
    bin.push(buf);
    binLength += buf.length;
    gltf.bufferViews.push(view);
    return gltf.bufferViews.length - 1;
  }
  function accessor(typed, type, componentType, count, extra = {}, target) {
    const bufferView = pushView(typed, target);
    gltf.accessors.push({ bufferView, componentType, count, type, ...extra });
    return gltf.accessors.length - 1;
  }
  const FLOAT = 5126, USHORT = 5123, UINT = 5125;

  const skinned = model.bones.length > 0;

  // --- skeleton nodes ---
  if (skinned) {
    for (const b of model.bones) {
      const parent = b.parent ? model.bones[model.boneIndex[b.parent]] : null;
      const t = parent ? sub(b.head, parent.head) : b.head;
      gltf.nodes.push({ name: b.name, translation: t });
    }
    for (const b of model.bones) {
      if (!b.parent) continue;
      const pn = gltf.nodes[model.boneIndex[b.parent]];
      (pn.children ??= []).push(b.index);
    }
  }

  // --- materials ---
  const matNames = [...new Set(model.parts.map((p) => p.material))];
  for (const mn of matNames) {
    const m = model.materials[mn] ?? { name: mn, roughness: 0.8, metallic: 0 };
    const mat = {
      name: mn,
      pbrMetallicRoughness: { baseColorFactor: [1, 1, 1, m.alpha ?? 1], metallicFactor: m.metallic, roughnessFactor: m.roughness },
    };
    if (m.emissive) {
      mat.emissiveFactor = m.emissive;
      if (m.emissiveStrength && m.emissiveStrength !== 1) {
        mat.extensions = { KHR_materials_emissive_strength: { emissiveStrength: m.emissiveStrength } };
        gltf.extensionsUsed = ['KHR_materials_emissive_strength'];
      }
    }
    if (m.alpha !== undefined && m.alpha < 1) mat.alphaMode = 'BLEND';
    if (m.doubleSided) mat.doubleSided = true;
    gltf.materials.push(mat);
  }

  // --- mesh primitives, one per material ---
  const primitives = [];
  matNames.forEach((mn, mi) => {
    const mesh = merge(model.parts.filter((p) => p.material === mn).map((p) => p.mesh));
    const n = mesh.positions.length;
    const pos = new Float32Array(n * 3), nrm = new Float32Array(n * 3), col = new Float32Array(n * 4);
    const min = [1e9, 1e9, 1e9], max = [-1e9, -1e9, -1e9];
    for (let i = 0; i < n; i++) {
      for (let k = 0; k < 3; k++) {
        const v = mesh.positions[i][k];
        pos[i * 3 + k] = v;
        min[k] = Math.min(min[k], v);
        max[k] = Math.max(max[k], v);
        nrm[i * 3 + k] = mesh.normals[i][k];
        col[i * 4 + k] = Math.max(0, Math.min(1, mesh.colors[i][k]));
      }
      col[i * 4 + 3] = 1;
    }
    const attributes = {
      POSITION: accessor(pos, 'VEC3', FLOAT, n, { min, max }, 34962),
      NORMAL: accessor(nrm, 'VEC3', FLOAT, n, {}, 34962),
      COLOR_0: accessor(col, 'VEC4', FLOAT, n, {}, 34962),
    };
    if (skinned) {
      const joints = new Uint16Array(n * 4), weights = new Float32Array(n * 4);
      for (let i = 0; i < n; i++) {
        const entries = Object.entries(mesh.bones[i])
          .map(([b, w]) => {
            if (!(b in model.boneIndex)) throw new Error(`${model.name}: unknown bone '${b}'`);
            return [model.boneIndex[b], w];
          })
          .sort((a, b) => b[1] - a[1])
          .slice(0, 4);
        const sum = entries.reduce((s, e) => s + e[1], 0) || 1;
        entries.forEach(([j, w], k) => {
          joints[i * 4 + k] = j;
          weights[i * 4 + k] = w / sum;
        });
        // make the weights sum to exactly 1 in float32
        let s = 0;
        for (let k = 0; k < 4; k++) s += weights[i * 4 + k];
        weights[i * 4] += 1 - s;
      }
      attributes.JOINTS_0 = accessor(joints, 'VEC4', USHORT, n, {}, 34962);
      attributes.WEIGHTS_0 = accessor(weights, 'VEC4', FLOAT, n, {}, 34962);
    }
    const big = n > 65535;
    const idx = big ? new Uint32Array(mesh.tris) : new Uint16Array(mesh.tris);
    const indices = accessor(idx, 'SCALAR', big ? UINT : USHORT, mesh.tris.length, {}, 34963);
    primitives.push({ attributes, indices, material: mi, mode: 4 });
  });
  gltf.meshes.push({ name: model.name + '_mesh', primitives });

  const meshNode = gltf.nodes.length;
  gltf.nodes.push({ name: model.name + '_mesh', mesh: 0, ...(skinned ? { skin: 0 } : {}) });

  if (skinned) {
    const ibm = new Float32Array(model.bones.length * 16);
    model.bones.forEach((b, i) => {
      const o = i * 16;
      ibm[o] = ibm[o + 5] = ibm[o + 10] = ibm[o + 15] = 1;
      ibm[o + 12] = -b.head[0];
      ibm[o + 13] = -b.head[1];
      ibm[o + 14] = -b.head[2];
    });
    const rootBones = model.bones.filter((b) => !b.parent).map((b) => b.index);
    gltf.skins = [{ name: model.name + '_skin', joints: model.bones.map((b) => b.index), inverseBindMatrices: accessor(ibm, 'MAT4', FLOAT, model.bones.length), skeleton: rootBones[0] }];
    const rootNode = gltf.nodes.length;
    gltf.nodes.push({ name: model.name, children: [...rootBones, meshNode] });
    gltf.scenes[0].nodes = [rootNode];

    // --- animations ---
    gltf.animations = [];
    for (const a of model.anims) {
      const frames = Math.max(2, Math.round(a.duration * FPS) + 1);
      const times = new Float32Array(frames);
      const poses = [];
      for (let f = 0; f < frames; f++) {
        const t = Math.min(a.duration, f / FPS);
        times[f] = t;
        const pose = new Pose(model);
        a.fn(a.loop && f === frames - 1 ? 0 : t, pose);
        poses.push(pose);
      }
      const input = accessor(times, 'SCALAR', FLOAT, frames, { min: [0], max: [times[frames - 1]] });
      const samplers = [], channels = [];
      for (const b of model.bones) {
        const parent = b.parent ? model.bones[model.boneIndex[b.parent]] : null;
        const rest = parent ? sub(b.head, parent.head) : b.head;
        const rot = new Float32Array(frames * 4), tr = new Float32Array(frames * 3), sc = new Float32Array(frames * 3);
        let prev = null;
        poses.forEach((p, f) => {
          let q = qNormalize(p.r[b.name]);
          // keep quaternion hemisphere continuous for clean interpolation
          if (prev && prev[0] * q[0] + prev[1] * q[1] + prev[2] * q[2] + prev[3] * q[3] < 0) q = q.map((x) => -x);
          prev = q;
          rot.set(q, f * 4);
          tr.set([rest[0] + p.p[b.name][0], rest[1] + p.p[b.name][1], rest[2] + p.p[b.name][2]], f * 3);
          sc.set(p.s[b.name], f * 3);
        });
        for (const [path, data, type] of [['rotation', rot, 'VEC4'], ['translation', tr, 'VEC3'], ['scale', sc, 'VEC3']]) {
          samplers.push({ input, output: accessor(data, type, FLOAT, frames), interpolation: 'LINEAR' });
          channels.push({ sampler: samplers.length - 1, target: { node: b.index, path } });
        }
      }
      gltf.animations.push({ name: a.name, samplers, channels });
    }
  } else {
    gltf.scenes[0].nodes = [meshNode];
  }

  gltf.buffers.push({ byteLength: binLength });
  const binBuf = Buffer.concat(bin, binLength);
  let json = Buffer.from(JSON.stringify(gltf), 'utf8');
  const jpad = (4 - (json.length % 4)) % 4;
  json = Buffer.concat([json, Buffer.alloc(jpad, 0x20)]);
  const bpad = (4 - (binBuf.length % 4)) % 4;
  const binChunk = Buffer.concat([binBuf, Buffer.alloc(bpad)]);
  const header = Buffer.alloc(12);
  header.writeUInt32LE(0x46546c67, 0);
  header.writeUInt32LE(2, 4);
  header.writeUInt32LE(12 + 8 + json.length + 8 + binChunk.length, 8);
  const jh = Buffer.alloc(8);
  jh.writeUInt32LE(json.length, 0);
  jh.writeUInt32LE(0x4e4f534a, 4);
  const bh = Buffer.alloc(8);
  bh.writeUInt32LE(binChunk.length, 0);
  bh.writeUInt32LE(0x004e4942, 4);
  return Buffer.concat([header, jh, json, bh, binChunk]);
}
