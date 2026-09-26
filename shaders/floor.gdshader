shader_type spatial;
render_mode diffuse_toon, specular_toon;

// Dug passages: dark packed earth in a few flat tones, so blocks and monsters stand out.
uniform sampler2D noise_a : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_b : filter_linear_mipmap, repeat_enable;
uniform vec3 dirt_a : source_color = vec3(0.27, 0.2, 0.14);
uniform vec3 dirt_b : source_color = vec3(0.36, 0.265, 0.19);
uniform vec3 pebble : source_color = vec3(0.46, 0.39, 0.31);
uniform float depth_rows = 26.0;
uniform float tone_steps = 3.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float q(float x) {
	return floor(clamp(x, 0.0, 1.0) * tone_steps + 0.5) / tone_steps;
}

void fragment() {
	vec2 p = wpos.xz;
	float n = texture(noise_a, p * 0.09).r;
	float n2 = texture(noise_b, p * 0.6).r;
	float n3 = texture(noise_a, p * 2.1).r;
	vec3 col = mix(dirt_a, dirt_b, q(smoothstep(0.3, 0.75, n * 0.7 + n2 * 0.3)));
	col *= 0.94 + 0.1 * q(n3);
	// sparse pebbles
	float peb = step(0.8, texture(noise_b, p * 3.3).r);
	col = mix(col, pebble, peb * 0.8);
	col *= mix(1.0, 0.65, floor(smoothstep(1.0, depth_rows, wpos.z) * 4.0 + 0.5) / 4.0);
	ALBEDO = col;
	ROUGHNESS = 0.97;
	SPECULAR = 0.05;
}
