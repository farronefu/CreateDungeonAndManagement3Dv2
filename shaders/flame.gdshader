shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D noise_a : filter_linear_mipmap, repeat_enable;

varying float seed;

void vertex() {
	// cylindrical billboard (keeps upright)
	vec3 cam_right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 world = MODEL_MATRIX[3].xyz + cam_right * VERTEX.x + up * VERTEX.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	seed = MODEL_MATRIX[3].x * 3.1 + MODEL_MATRIX[3].z * 1.7;
}

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y); // y: 0 bottom .. 1 top
	float n = texture(noise_a, vec2(uv.x * 0.8 + seed, uv.y * 0.9 - TIME * 1.6)).r;
	float n2 = texture(noise_a, vec2(uv.x * 1.7 - seed, uv.y * 1.6 - TIME * 2.4)).r;
	float width = mix(0.42, 0.04, pow(uv.y, 0.8));
	float dx = abs(uv.x - 0.5 + (n - 0.5) * 0.25 * uv.y);
	float body = 1.0 - smoothstep(width * 0.55, width, dx);
	body *= smoothstep(0.0, 0.12, uv.y) * (1.0 - smoothstep(0.55 + n2 * 0.35, 1.0, uv.y));
	float core = body * (1.0 - smoothstep(0.0, 0.5, uv.y + dx * 2.0));
	vec3 col = mix(vec3(1.0, 0.25, 0.03), vec3(1.0, 0.62, 0.15), body * 0.6) + vec3(1.0, 0.85, 0.45) * core * 0.6;
	ALBEDO = col * 1.3;
	ALPHA = clamp(body, 0.0, 1.0);
}
