// Easing / timing helpers for procedural keyframes.

export const TAU = Math.PI * 2;
export const clamp01 = (x) => Math.max(0, Math.min(1, x));
// normalised position of t inside [a, b]
export const seg = (t, a, b) => clamp01((t - a) / (b - a));
export const easeInOut = (x) => (x < 0.5 ? 2 * x * x : 1 - Math.pow(-2 * x + 2, 2) / 2);
export const easeOut = (x) => 1 - Math.pow(1 - x, 3);
export const easeIn = (x) => x * x * x;
export const backOut = (x) => {
  const c1 = 1.70158, c3 = c1 + 1;
  return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2);
};
// 0 -> 1 -> 0 bump over [a, b]
export const bump = (t, a, b) => Math.sin(Math.PI * seg(t, a, b));
// damped wobble starting at t0
export const wobble = (t, t0, freq, decay) => (t < t0 ? 0 : Math.sin((t - t0) * freq * TAU) * Math.exp(-(t - t0) * decay));
// periodic sine for looped clips with duration d
export const wave = (t, d, cycles = 1, phase = 0) => Math.sin(TAU * (cycles * t / d + phase));
