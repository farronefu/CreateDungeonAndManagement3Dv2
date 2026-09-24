shader_type spatial;
render_mode diffuse_toon, specular_toon;

// Soil mass. Blocks are flush cubes; everything is textured in world space from a per-cell
// "field" texture so neighbouring blocks read as one continuous body of earth.
//   field.r = nutrient / 16   field.g = rock (undiggable)   field.b = dug (floor)
// Per-instance custom data: g = random, b = hover 0..1.
// The surface (world z < 0, and the tops of row 0) blends into the meadow of the world above.

uniform sampler2D field : filter_linear, repeat_disable;
uniform vec2 field_origin = vec2(-20.0, 0.0);
uniform vec2 field_size = vec2(76.0, 42.0);
uniform sampler2D noise_a : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_b : filter_linear_mipmap, repeat_enable;
uniform float block_height = 0.9;
uniform float depth_rows = 26.0;

uniform vec3 soil_top : source_color = vec3(0.40, 0.30, 0.21);
uniform vec3 soil_top_dry : source_color = vec3(0.47, 0.36, 0.26);
uniform vec3 strata_a : source_color = vec3(0.42, 0.28, 0.18);
uniform vec3 strata_b : source_color = vec3(0.33, 0.21, 0.14);
uniform vec3 strata_c : source_color = vec3(0.50, 0.36, 0.24);
uniform vec3 grass_a : source_color = vec3(0.34, 0.42, 0.19);
uniform vec3 grass_b : source_color = vec3(0.44, 0.52, 0.23);
uniform vec3 moss_a : source_color = vec3(0.13, 0.36, 0.17);
uniform vec3 moss_b : source_color = vec3(0.20, 0.47, 0.22);
uniform vec3 bloom : source_color = vec3(1.0, 0.86, 0.45);
uniform vec3 rock_a : source_color = vec3(0.31, 0.30, 0.31);
uniform vec3 rock_b : source_color = vec3(0.37, 0.36, 0.36);
uniform vec3 meadow : source_color = vec3(0.42, 0.53, 0.27);
uniform vec3 meadow_b : source_color = vec3(0.50, 0.58, 0.30);

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

vec3 fld(vec2 xz) {
	return texture(field, (xz - field_origin) / field_size).rgb;
}

void fragment() {
	float hover = cdata.b;
	float n1 = texture(noise_a, wpos.xz * 0.11).r;
	float n2 = texture(noise_b, wpos.xz * 0.9 + wpos.y * 0.3).r;
	float n3 = texture(noise_a, wpos.xz * 2.3).r;
	float top = step(0.6, wnrm.y);
	// sample the field slightly inside the block, warped by noise for organic borders
	vec2 inside = wpos.xz - wnrm.xz * 0.12 + (vec2(n1, n2) - 0.5) * 0.55;
	vec3 f = fld(inside);
	float nut = f.r * 16.0;
	float rock = smoothstep(0.35, 0.65, f.g);
	float surface = smoothstep(1.05, 0.35, wpos.z);   // 1 on the meadow above (row 0 and beyond)

	// ---------------- top face
	vec3 col_top = mix(soil_top, soil_top_dry, smoothstep(0.35, 0.75, n1)) * (0.92 + 0.12 * n3);
	// nutrient soil: sparse olive moss specks that thicken with nutrient (the soil stays soil)
	float g_amt = nut < 0.6 ? 0.0 : mix(0.3, 0.55, clamp((nut - 1.0) / 8.0, 0.0, 1.0));
	float nm = texture(noise_a, wpos.xz * 0.42).r * 0.75 + texture(noise_b, wpos.xz * 1.1).r * 0.25;
	float g_mask = smoothstep(1.0 - g_amt - 0.03, 1.0 - g_amt + 0.03, nm);
	vec3 gcol = mix(grass_a, grass_b, smoothstep(0.3, 0.8, n3));
	col_top = mix(col_top, gcol, g_mask);
	// rich soil: deep moss carpet with small blooms
	float rich = smoothstep(9.0, 10.5, nut);
	vec3 mcol = mix(moss_a, moss_b, smoothstep(0.3, 0.75, n2));
	col_top = mix(col_top, mcol, rich);
	float blooms = rich * step(0.8, texture(noise_b, wpos.xz * 7.0).r);
	col_top = mix(col_top, bloom, blooms);
	// meadow on the surface
	vec3 mcol2 = mix(meadow, meadow_b, smoothstep(0.35, 0.7, n1)) * (0.93 + 0.12 * n3);
	col_top = mix(col_top, mcol2, surface);

	// ---------------- side faces: soil cross-section
	float h = clamp(wpos.y / block_height, 0.0, 1.0);
	// soft mottled earth: two broad layers blended by low-frequency noise (no stripes)
	vec2 sp = vec2(wpos.x + wpos.z, wpos.y);
	float m1 = texture(noise_a, sp * vec2(0.35, 0.9)).r;
	float m2 = texture(noise_b, sp * 1.6).r;
	vec3 col_side = mix(strata_a, strata_b, smoothstep(0.35, 0.7, m1 + (0.5 - h) * 0.35));
	col_side = mix(col_side, strata_c, smoothstep(0.62, 0.8, m2) * 0.35);
	col_side *= 0.92 + 0.12 * m2;
	// embedded stones
	float stn = smoothstep(0.74, 0.77, texture(noise_b, vec2(wpos.x + wpos.z, wpos.y) * 2.6).r);
	col_side = mix(col_side, rock_b * 1.1, stn * 0.7);
	col_side *= 0.9 + 0.18 * texture(noise_b, vec2(wpos.x + wpos.z, wpos.y) * 1.3).r;
	// grass / moss lip hanging over the top edge
	float lip = smoothstep(0.86 - rich * 0.12, 0.9, h + (n3 - 0.5) * 0.08) * max(rich, surface);
	col_side = mix(col_side, mix(gcol, mcol, rich) * 0.85, lip);
	// ambient occlusion toward the floor
	col_side *= mix(0.42, 1.0, smoothstep(0.0, 0.55, h));

	vec3 col = mix(col_side, col_top, top);
	// rock (outer border): plain stone
	vec3 rcol = mix(rock_a, rock_b, smoothstep(0.3, 0.75, n1)) * (0.85 + 0.2 * n3);
	rcol *= mix(mix(0.5, 1.0, smoothstep(0.0, 0.6, h)), 1.0, top);
	col = mix(col, rcol, rock * (1.0 - surface * top));

	// the deeper into the dungeon, the darker
	float depth = smoothstep(1.0, depth_rows, wpos.z);
	col *= mix(1.0, 0.62, depth);

	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
	EMISSION = vec3(1.0, 0.72, 0.35) * hover * 0.18 + bloom * blooms * 0.12;
}
