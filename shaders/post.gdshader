shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;

// Full-screen pass that ties every asset into one look:
//   * ink outlines from depth + normal discontinuities
//   * warm/cool colour grade and a gentle vignette
//   * distance blur on the town: beyond the dungeon (world z < town_blur_start) it softens
//     progressively, the sky / far hills most

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, repeat_disable, filter_nearest;

uniform vec3 ink = vec3(0.16, 0.1, 0.07);
uniform float line_width = 1.2;
uniform float depth_sense = 0.05;
uniform float normal_sense = 0.45;
uniform float line_strength = 0.75;
uniform float vignette = 0.42;
uniform float saturation = 1.02;
// linear multipliers (no source_color: these must not be sRGB-converted)
uniform vec3 shadow_tint = vec3(0.94, 0.96, 1.0);
uniform vec3 light_tint = vec3(1.02, 1.0, 0.97);
uniform float town_blur_start = -17.0;  // world z where the blur begins (behind the town buildings)
uniform float town_blur_full = -28.0;   // world z where it is strongest
uniform float town_blur_radius = 6.0;   // pixels at 1080p at full strength

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float lin_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

vec3 nrm(vec2 uv) {
	return texture(normal_tex, uv).xyz * 2.0 - 1.0;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = line_width * (VIEWPORT_SIZE.y / 1080.0) / VIEWPORT_SIZE;
	vec3 col = texture(screen_tex, uv).rgb;

	float d0 = lin_depth(uv, INV_PROJECTION_MATRIX);

	// --- town distance blur -------------------------------------------------
	float raw = texture(depth_tex, uv).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, raw, 1.0);
	vp /= vp.w;
	vec3 wp = (INV_VIEW_MATRIX * vec4(vp.xyz, 1.0)).xyz;
	float far_k = smoothstep(120.0, 300.0, d0);            // sky
	float blur = max(smoothstep(town_blur_start, town_blur_full, wp.z), far_k);
	if (blur > 0.001) {
		vec2 r = blur * town_blur_radius * (VIEWPORT_SIZE.y / 1080.0) / VIEWPORT_SIZE;
		float lod = blur * 2.2;
		vec3 acc = textureLod(screen_tex, uv, lod).rgb * 0.2;
		acc += textureLod(screen_tex, uv + vec2(r.x, 0.0), lod).rgb * 0.1;
		acc += textureLod(screen_tex, uv - vec2(r.x, 0.0), lod).rgb * 0.1;
		acc += textureLod(screen_tex, uv + vec2(0.0, r.y), lod).rgb * 0.1;
		acc += textureLod(screen_tex, uv - vec2(0.0, r.y), lod).rgb * 0.1;
		acc += textureLod(screen_tex, uv + r * 0.7, lod).rgb * 0.1;
		acc += textureLod(screen_tex, uv - r * 0.7, lod).rgb * 0.1;
		acc += textureLod(screen_tex, uv + vec2(r.x, -r.y) * 0.7, lod).rgb * 0.1;
		acc += textureLod(screen_tex, uv + vec2(-r.x, r.y) * 0.7, lod).rgb * 0.1;
		col = mix(col, acc, smoothstep(0.0, 0.35, blur));
	}
	float d1 = lin_depth(uv + vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float d2 = lin_depth(uv - vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float d3 = lin_depth(uv + vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	float d4 = lin_depth(uv - vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	float dd = abs(d1 + d2 + d3 + d4 - 4.0 * d0) / max(d0, 0.001);
	float e_depth = smoothstep(depth_sense, depth_sense * 2.5, dd);

	vec3 n0 = nrm(uv);
	float nd = 0.0;
	nd = max(nd, 1.0 - dot(n0, nrm(uv + vec2(px.x, 0.0))));
	nd = max(nd, 1.0 - dot(n0, nrm(uv - vec2(px.x, 0.0))));
	nd = max(nd, 1.0 - dot(n0, nrm(uv + vec2(0.0, px.y))));
	nd = max(nd, 1.0 - dot(n0, nrm(uv - vec2(0.0, px.y))));
	float e_norm = smoothstep(normal_sense, normal_sense + 0.3, nd);

	// fade lines with distance (the sky / far mountains stay soft)
	float fade = 1.0 - smoothstep(45.0, 90.0, d0);
	float edge = max(e_depth, e_norm) * line_strength * fade * (1.0 - blur);
	col = mix(col, col * ink * 2.2, edge);

	// grade: cool shadows, warm highlights, a touch more colour
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col *= mix(shadow_tint, light_tint, smoothstep(0.1, 0.7, lum));
	col = mix(vec3(lum), col, saturation);

	// vignette
	vec2 c = uv - 0.5;
	c.x *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	float v = smoothstep(0.35, 1.05, length(c));
	col *= 1.0 - vignette * v;

	ALBEDO = col;
}
