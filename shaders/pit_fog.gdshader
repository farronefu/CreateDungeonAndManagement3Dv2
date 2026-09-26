shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// One static layer of the fog that fills the pit between the town and the dungeon.
// Several of these are stacked; each fades out towards its front edge (z_front) so the
// dungeon rows stay clear. `vertical` layers stand upright in front of the cliff and fade
// towards their top instead.

uniform vec3 fog_dark : source_color = vec3(0.16, 0.19, 0.27);
uniform vec3 fog_light : source_color = vec3(0.46, 0.52, 0.64);
uniform float density = 0.85;
uniform float seed = 0.0;
uniform float z_front = 0.0;
uniform float fade = 1.6;
uniform bool vertical = false;
uniform float y_top = 4.0;
uniform float y_bottom = 1.0;
// vertical layers only: (x centre, top height, half width) of a dense plume that swallows the
// bottom of the steps completely
uniform vec3 plume = vec3(0.0, -10.0, 1.0);

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = vertical ? vec2(wpos.x * 0.22, wpos.y * 0.8) : vec2(wpos.x * 0.2, wpos.z * 0.75);
	vec2 o = vec2(seed * 0.137, seed * 0.291);
	float n = texture(noise_tex, p * 0.09 + o).r * 0.7 + texture(noise_tex, p * 0.3 - o).r * 0.3;
	float a = (0.45 + 0.55 * smoothstep(0.3, 0.68, n)) * density;
	float wave = (n - 0.5) * 2.2;
	if (vertical) {
		a *= 1.0 - smoothstep(y_bottom, y_top, wpos.y + wave);
		a = max(a, (1.0 - smoothstep(y_bottom, y_bottom + 1.5, wpos.y)) * 0.97);
		float pd = abs(wpos.x - plume.x) / plume.z + (n - 0.5) * 0.5;
		a = max(a, (1.0 - smoothstep(0.55, 1.0, pd)) * (1.0 - smoothstep(plume.y - 0.7, plume.y + 0.3, wpos.y + wave * 0.25)));
	} else {
		a *= 1.0 - smoothstep(z_front - fade, z_front, wpos.z + wave * 0.6);
	}
	ALBEDO = mix(fog_dark, fog_light, smoothstep(0.4, 0.8, n));
	ALPHA = clamp(a, 0.0, 1.0);
}
