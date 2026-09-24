shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Soil block. Per-instance custom data:
//   r = nutrient / 16 (0: plain soil, 1-9: 養分の土, 10+: 肥えた土)   g = random seed
//   b = cursor highlight 0..1         a = bedrock look (undiggable)

uniform sampler2D noise_a : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_b : filter_linear_mipmap, repeat_enable;
uniform vec3 dirt_light : source_color = vec3(0.50, 0.35, 0.23);
uniform vec3 dirt_dark : source_color = vec3(0.27, 0.18, 0.11);
uniform vec3 stone_col : source_color = vec3(0.52, 0.47, 0.40);
uniform vec3 moss_dark : source_color = vec3(0.20, 0.34, 0.09);
uniform vec3 moss_light : source_color = vec3(0.46, 0.62, 0.18);
uniform vec3 moss_tip : source_color = vec3(0.68, 0.80, 0.30);
uniform vec3 rock_col : source_color = vec3(0.30, 0.28, 0.30);
uniform vec3 lush_dark : source_color = vec3(0.10, 0.30, 0.07);
uniform vec3 lush_light : source_color = vec3(0.28, 0.52, 0.13);
uniform float block_height = 0.9;
// used by standalone meshes (no multimesh custom data); x < 0 means "use INSTANCE_CUSTOM"
uniform vec4 custom_override = vec4(-1.0);

varying vec3 wpos;
varying vec3 wnrm;
varying vec3 lpos;
varying vec4 cdata;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	lpos = VERTEX;
	cdata = custom_override.x >= 0.0 ? custom_override : INSTANCE_CUSTOM;
}

float tri(sampler2D tex, vec3 p, vec3 n, float s) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(tex, p.zy * s).r * w.x + texture(tex, p.xz * s).r * w.y + texture(tex, p.xy * s).r * w.z;
}

void fragment() {
	float moss = cdata.r;
	float seed = cdata.g;
	float hover = cdata.b;
	float rock = cdata.a;
	vec3 p = wpos + vec3(seed * 13.7, 0.0, seed * 7.3);
	float n1 = tri(noise_a, p, wnrm, 0.45);
	float n2 = tri(noise_b, p, wnrm, 1.4);
	float n3 = tri(noise_a, p, wnrm, 3.1);
	float h = clamp(lpos.y / block_height + 0.5, 0.0, 1.0); // 0 bottom .. 1 top
	float top = smoothstep(0.5, 0.85, wnrm.y);

	// soil: two-tone with strata bands and pebbles
	float strata = sin(wpos.y * 24.0 + n1 * 7.0 + seed * 3.0) * 0.5 + 0.5;
	vec3 col = mix(dirt_dark, dirt_light, smoothstep(0.2, 0.8, n1 * 0.65 + n2 * 0.35));
	col *= mix(0.8, 1.06, mix(strata, 1.0, top));
	float peb = smoothstep(0.66, 0.71, n3) * (1.0 - top * 0.5);
	col = mix(col, stone_col * (0.75 + n2 * 0.5), peb * 0.85);
	// cracks
	float crack = smoothstep(0.02, 0.0, abs(n2 - 0.5)) * 0.45;
	col *= 1.0 - crack;

	// three readable soil types:
	//   養分なし  -> bare soil
	//   養分 1-9  -> grass & vines, a little more with more nutrient
	//   養分 10+  -> lush emerald moss with small flowers
	float nut = moss * 16.0;
	float rich = step(9.5, nut) * (1.0 - rock);
	float grow = nut < 0.5 ? 0.0 : (nut < 9.5 ? mix(0.3, 0.62, (nut - 1.0) / 8.0) : 0.9);
	float cover_top = smoothstep(1.0 - grow * 1.05, 1.08 - grow * 1.05, n1 * 0.55 + n2 * 0.45);
	float streak = texture(noise_b, vec2((wpos.x + wpos.z) * 2.1 + seed * 5.0, wpos.y * 0.18)).r;
	float reach = grow * (0.18 + streak * 1.1) + (n3 - 0.5) * 0.12;
	float cover_side = step(1.0 - h, reach) * smoothstep(0.38, 0.5, streak + grow * 0.25) * step(0.01, grow);
	float cover = mix(cover_side, cover_top, top) * (1.0 - rock);
	vec3 mcol = mix(moss_dark, moss_light, smoothstep(0.25, 0.8, n2 * 0.5 + n3 * 0.5));
	mcol = mix(mcol, moss_tip, smoothstep(0.72, 0.86, n3) * 0.7 * top);
	vec3 lush = mix(lush_dark, lush_light, smoothstep(0.3, 0.75, n2 * 0.6 + n3 * 0.4));
	mcol = mix(mcol, lush, rich);
	mcol *= mix(0.75, 1.0, h);
	col = mix(col, mcol, cover);
	// flowers dotting the rich soil
	float petal = texture(noise_b, wpos.xz * 9.0 + seed * 3.0).r;
	float flower = smoothstep(0.76, 0.79, petal) * top * rich;
	vec3 fcol = mix(vec3(1.0, 0.86, 0.3), vec3(1.0, 0.95, 0.95), step(0.5, fract(n2 * 7.0)));
	col = mix(col, fcol, flower);

	// bedrock / undiggable
	vec3 rcol = rock_col * (0.7 + n1 * 0.5 + n3 * 0.2);
	col = mix(col, rcol, rock);

	// fake ambient occlusion towards the floor
	col *= mix(0.45, 1.0, smoothstep(0.0, 0.4, h));

	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.78, cover);
	SPECULAR = 0.3;
	// small bumps on top of moss
	vec3 bump = vec3(n3 - 0.5, 0.0, n2 - 0.5) * 0.35 * cover * top;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(bump, 0.0)).xyz);
	EMISSION = vec3(1.0, 0.55, 0.12) * hover * 0.45 ;
}
