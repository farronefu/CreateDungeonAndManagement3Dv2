// Reusable model parts.
import { sphere, ellipsoid } from '../lib/sdf.mjs';
import { norm, sub, dot, hex, cmix, fbm } from '../lib/math.mjs';

// Glossy cartoon eye: sclera, iris ring, pupil and a baked highlight.
export function eye(c, r, look, bone, { iris = '#3b2a1a', pupil = '#0c0808', sclera = '#fbf7ee', irisSize = 0.62, pupilSize = 0.8, highlight = [0.45, 0.6, 0.66], lid = null } = {}) {
  const L = norm(look), H = norm(highlight);
  const cIris = hex(iris), cPupil = hex(pupil), cSclera = hex(sclera), white = hex('#ffffff');
  const cLid = lid ? hex(lid.color) : null;
  return sphere(c, r, {
    bone,
    k: 0,
    blend: 0.002,
    color: (p) => {
      const d = norm(sub(p, c));
      if (lid && d[1] > lid.height) return cLid;
      if (dot(d, H) > 0.955) return white;
      const f = dot(d, L);
      if (f > pupilSize) return cPupil;
      if (f > irisSize) return cmix(cIris, cPupil, (f - irisSize) / (pupilSize - irisSize) * 0.5);
      return cSclera;
    },
  });
}

// Colour function helper: two-tone vertical gradient with speckle noise.
export function mossColor({ low, mid, high, y0, y1, speck = '#b8e070', speckAmt = 0.55, freq = 22 }) {
  const cl = hex(low), cm = hex(mid), ch = hex(high), cs = hex(speck);
  return (p) => {
    const t = (p[1] - y0) / (y1 - y0);
    let c = t < 0.5 ? cmix(cl, cm, t * 2) : cmix(cm, ch, (t - 0.5) * 2);
    const n = fbm(p, freq, 3);
    if (n > speckAmt) c = cmix(c, cs, (n - speckAmt) * 4);
    if (n < 0.34) c = cmix(c, cl, (0.34 - n) * 3);
    return c;
  };
}

export { hex };
