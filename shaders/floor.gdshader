shader_type spatial;
render_mode diffuse_toon, specular_toon;

// Dug passages: plain packed earth, darker than the untouched soil so paths read clearly.
uniform sampler2D noise_a : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_b : filter_linear_mipmap, repeat_enable;
uniform vec3 dirt_a : source_color = vec3(0.24, 0.17, 0.12);
uniform vec3 dirt_b : source_color = vec3(0.30, 0.22, 0.15);
uniform vec3 pebble : source_color = vec3(0.40, 0.34, 0.28);
uniform float depth_rows = 26.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float n = texture(noise_a, p * 0.09).r;
	float n2 = texture(noise_b, p * 0.6).r;
	float n3 = texture(noise_a, p * 2.1).r;
	vec3 col = mix(dirt_a, dirt_b, smoothstep(0.3, 0.75, n * 0.7 + n2 * 0.3));
	// trodden, slightly lighter middle of the passages is too costly to compute; subtle mottling instead
	col *= 0.93 + 0.1 * n3;
	// sparse pebbles
	float peb = smoothstep(0.79, 0.81, texture(noise_b, p * 3.3).r);
	col = mix(col, pebble * (0.8 + 0.3 * n3), peb * 0.8);
	col *= mix(1.0, 0.6, smoothstep(1.0, depth_rows, wpos.z));
	ALBEDO = col;
	ROUGHNESS = 0.97;
	SPECULAR = 0.1;
}
