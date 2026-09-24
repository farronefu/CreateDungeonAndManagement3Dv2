shader_type spatial;
render_mode diffuse_toon, specular_toon;

// Individual rounded soil blocks (勇者のくせになまいきだ style: separated by gaps).
// Per-instance custom data:
//   r = nutrient / 16   g = random   b = hover 0..1   a = kind (0 soil, 0.5 meadow, 1 rock)
// Soil stages (Balance.SOIL_STAGE_MIN): 0 ① bare, 1-4 ② some plants, 5-9 ③ lush,
// 10-12 ④ starting to wither, 13+ ⑤ withered. Leaves / vines / pebbles are separate meshes.

uniform sampler2D noise_a : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_b : filter_linear_mipmap, repeat_enable;
uniform float block_height = 0.88;
uniform float depth_rows = 26.0;

uniform vec3 soil_a : source_color = vec3(0.56, 0.41, 0.29);
uniform vec3 soil_b : source_color = vec3(0.48, 0.34, 0.24);
uniform vec3 moss_bright : source_color = vec3(0.44, 0.62, 0.22);
uniform vec3 moss_deep : source_color = vec3(0.30, 0.48, 0.18);
uniform vec3 straw_a : source_color = vec3(0.78, 0.64, 0.30);
uniform vec3 straw_b : source_color = vec3(0.64, 0.50, 0.24);
uniform vec3 rock_a : source_color = vec3(0.40, 0.39, 0.40);
uniform vec3 rock_b : source_color = vec3(0.50, 0.49, 0.48);
uniform vec3 meadow : source_color = vec3(0.42, 0.55, 0.26);
uniform vec3 meadow_b : source_color = vec3(0.50, 0.60, 0.30);

// used by standalone meshes (no multimesh custom data); x < 0 means "use INSTANCE_CUSTOM"
uniform vec4 custom_override = vec4(-1.0);

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 cdata;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	cdata = custom_override.x >= 0.0 ? custom_override : INSTANCE_CUSTOM;
}

void fragment() {
	float nut = cdata.r * 16.0;
	float seed = cdata.g;
	float hover = cdata.b;
	float kind = cdata.a;
	float rock = step(0.75, kind);
	float meadow_k = max(step(0.25, kind) * (1.0 - rock), smoothstep(0.1, -0.1, wpos.z));
	vec2 o = vec2(seed * 17.0, seed * 9.0);
	float n1 = texture(noise_a, wpos.xz * 0.35 + o).r;
	float n2 = texture(noise_b, (wpos.xz + wpos.y) * 0.9 + o).r;
	float n3 = texture(noise_a, (wpos.xz + wpos.yy) * 2.4 + o).r;
	float top = smoothstep(0.55, 0.8, wnrm.y);
	float h = clamp(wpos.y / block_height, 0.0, 1.0);

	// soft, slightly mottled clay
	vec3 soil = mix(soil_b, soil_a, smoothstep(0.3, 0.75, n1 * 0.6 + n3 * 0.4));

	// stage weights
	float s2 = step(0.5, nut);                  // ② and above: moss
	float s3 = step(4.5, nut);                  // ③ lush
	float s4 = step(9.5, nut);                  // ④ withering
	float s5 = step(12.5, nut);                 // ⑤ withered
	float moss_cov = mix(0.0, 0.3, s2);
	moss_cov = mix(moss_cov, 0.72, s3);
	moss_cov = mix(moss_cov, 0.55, s4);
	moss_cov = mix(moss_cov, 0.15, s5);
	float straw_cov = mix(0.0, 0.22, s4);
	straw_cov = mix(straw_cov, 0.58, s5);

	// ---- top: moss cushions and dry straw
	float mfield = texture(noise_a, wpos.xz * 0.9 + o).r * 0.7 + n2 * 0.3;
	float moss = smoothstep(1.0 - moss_cov - 0.02, 1.0 - moss_cov + 0.02, mfield);
	float sfield = texture(noise_b, wpos.xz * 0.7 - o).r * 0.7 + n3 * 0.3;
	float straw = smoothstep(1.0 - straw_cov - 0.02, 1.0 - straw_cov + 0.02, sfield);
	vec3 mcol = mix(moss_deep, moss_bright, smoothstep(0.35, 0.7, n3) * (1.0 - s3 * 0.4));
	vec3 scol = mix(straw_b, straw_a, smoothstep(0.35, 0.7, n2));
	vec3 col_top = soil * (0.95 + 0.1 * n2);
	col_top = mix(col_top, mcol, moss);
	col_top = mix(col_top, scol, straw * (1.0 - moss * 0.5));
	col_top = mix(col_top, mix(meadow, meadow_b, smoothstep(0.35, 0.7, n1)), meadow_k);

	// ---- sides: clay with moss / straw creeping over the top edge
	vec3 col_side = soil * (0.9 + 0.12 * n3);
	float drip = smoothstep(0.78, 0.92, h + (n3 - 0.5) * 0.18) * max(s2 * (1.0 - s5), meadow_k);
	col_side = mix(col_side, mix(mcol, scol, s5) * 0.9, drip * (0.4 + 0.6 * s3));
	// contact shadow toward the floor
	col_side *= mix(0.55, 1.0, smoothstep(0.0, 0.45, h));

	vec3 col = mix(col_side, col_top, top);
	vec3 rcol = mix(rock_a, rock_b, smoothstep(0.3, 0.75, n1)) * (0.88 + 0.16 * n3);
	rcol *= mix(mix(0.6, 1.0, smoothstep(0.0, 0.5, h)), 1.0, top);
	col = mix(col, rcol, rock * (1.0 - meadow_k * top));

	// the deeper into the dungeon, the darker
	col *= mix(1.0, 0.66, smoothstep(1.0, depth_rows, wpos.z));

	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	EMISSION = vec3(1.0, 0.78, 0.45) * hover * 0.22;
}
