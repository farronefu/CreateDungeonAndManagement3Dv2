shader_type spatial;
render_mode diffuse_burley;

// Dungeon floor: packed dirt with worn flagstones.
uniform sampler2D noise_a : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_b : filter_linear_mipmap, repeat_enable;
uniform vec3 dirt_a : source_color = vec3(0.26, 0.19, 0.13);
uniform vec3 dirt_b : source_color = vec3(0.36, 0.27, 0.18);
uniform vec3 stone_a : source_color = vec3(0.34, 0.31, 0.28);
uniform vec3 stone_b : source_color = vec3(0.50, 0.46, 0.41);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float n = texture(noise_a, p * 0.21).r;
	float n2 = texture(noise_b, p * 1.3).r;
	float n3 = texture(noise_a, p * 3.7).r;
	// running-bond flagstones, 2 per tile
	vec2 q = p * 2.0;
	q.x += floor(q.y) * 0.5 + (n - 0.5) * 0.3;
	vec2 f = fract(q) - 0.5;
	float edge = max(abs(f.x), abs(f.y));
	float stone = 1.0 - smoothstep(0.36 - n2 * 0.08, 0.46, edge + (n3 - 0.5) * 0.14);
	float present = smoothstep(0.35, 0.55, n + n2 * 0.4);
	vec3 dirt = mix(dirt_a, dirt_b, n) * (0.85 + n3 * 0.3);
	vec3 st = mix(stone_a, stone_b, n2) * (0.85 + 0.25 * n3);
	vec3 col = mix(dirt, st, stone * present * 0.9);
	// scattered pebbles
	col = mix(col, stone_b * 0.9, smoothstep(0.78, 0.82, n3) * 0.6);
	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
}
