shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// Voxel-art look for the town: each face gets an 8x8 grid of texels with a little brightness
// noise and a darker border row, so every block reads as a separate cube.
//   COLOR   linear block colour (palette kind + brightness variant)
//   UV      0..1 across the face
//   UV2.x   noise pattern (0..3), UV2.y emission strength (windows, lanterns, forge fire)

uniform float emission_energy = 1.0;
uniform float border_dark = 0.9;

varying vec2 extra;

void vertex() {
	extra = UV2;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 cell = floor(clamp(UV, 0.0, 0.9999) * 8.0);
	float n = 0.84 + hash(cell + extra.x * 17.0) * 0.16;
	if (cell.x < 0.5 || cell.y < 0.5 || cell.x > 6.5 || cell.y > 6.5) {
		n *= border_dark;
	}
	n = pow(n, 2.2);   // the noise is authored in sRGB
	vec3 c = COLOR.rgb * n;
	ALBEDO = c;
	ROUGHNESS = 0.95;
	EMISSION = c * extra.y * emission_energy;
}
