shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// Town ground as voxel grass tiles: a world-space grid of `cell`-sized tiles, each one a grass
// shade with the same 8x8 texel noise and dark border as the town_voxel blocks, plus larger
// darker / worn patches so the meadow does not look like wallpaper.

uniform float cell = 0.22;
uniform vec3 grass : source_color = vec3(0.435, 0.627, 0.235);
uniform vec3 grass_dark : source_color = vec3(0.353, 0.541, 0.188);
uniform vec3 grass_light : source_color = vec3(0.525, 0.706, 0.29);
uniform vec3 worn : source_color = vec3(0.49, 0.47, 0.25);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 g = wpos.xz / cell;
	vec2 c = floor(g);
	float h = hash(c);
	vec3 col = h < 0.55 ? grass : (h < 0.8 ? grass_dark : grass_light);
	float patch = vnoise(c * 0.07) * 0.65 + vnoise(c * 0.21) * 0.35;
	if (patch > 0.66) {
		col = mix(col, grass_dark, 0.7);
	} else if (patch < 0.24 && hash(c + 7.3) < 0.55) {
		col = mix(col, worn, 0.55);
	}
	col *= 1.0 + (hash(c + 3.1) * 2.0 - 1.0) * 0.07;
	// texel noise, faded out where a tile gets small on screen (no shimmer in the distance)
	vec2 t = floor(fract(g) * 8.0);
	float n = 0.84 + hash(t + c * 0.37) * 0.16;
	if (t.x < 0.5 || t.y < 0.5 || t.x > 6.5 || t.y > 6.5) {
		n *= 0.9;
	}
	float px = length(fwidth(g));
	n = mix(n, 0.905, smoothstep(0.08, 0.3, px));
	ALBEDO = col * pow(n, 2.2);
	ROUGHNESS = 0.95;
}
