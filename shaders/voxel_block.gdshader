shader_type spatial;
render_mode diffuse_toon, specular_toon;
// Keep authored six-face UVs and colors. Custom data: nutrient/16, seed, hover, bedrock.
uniform sampler2D atlas_0 : source_color, filter_nearest_mipmap, repeat_disable;
uniform sampler2D atlas_1 : source_color, filter_nearest_mipmap, repeat_disable;
uniform sampler2D atlas_2 : source_color, filter_nearest_mipmap, repeat_disable;
uniform sampler2D atlas_3 : source_color, filter_nearest_mipmap, repeat_disable;
uniform sampler2D atlas_4 : source_color, filter_nearest_mipmap, repeat_disable;
uniform sampler2D atlas_5 : source_color, filter_nearest_mipmap, repeat_disable;
uniform sampler2D height_atlas : filter_nearest, repeat_disable;
uniform vec4 custom_override = vec4(-1.0);
varying vec4 cdata;
// Static geometric displacement, not a bump/normal map. No frame-time input.
vec3 surface_normal(float face) {
	if (face < 0.5) { return vec3(0.0,1.0,0.0); }
	if (face < 1.5) { return vec3(0.0,0.0,1.0); }
	if (face < 2.5) { return vec3(1.0,0.0,0.0); }
	if (face < 3.5) { return vec3(0.0,0.0,-1.0); }
	if (face < 4.5) { return vec3(-1.0,0.0,0.0); }
	return vec3(0.0,-1.0,0.0);
}
float plateau_height(vec2 cell, float face, float variant, float n, bool bedrock) {
	if (cell.x > 0.99 && cell.y > 0.99) { return 0.0; } // closed outer wall down to core
	vec2 texel = vec2(variant*6.0+floor(cell.x*6.0)+0.5,face*6.0+floor(cell.y*6.0)+0.5);
	vec4 levels = textureLod(height_atlas,texel/vec2(24.0,36.0),0.0);
	float level = levels.r;
	if (bedrock) { level = 0.85 + levels.r*0.15; }
	else if (n >= 10.0) { level = levels.a; }
	else if (n >= 5.0) { level = levels.b; }
	else if (n >= 1.0) { level = levels.g; }
	return level*0.12;
}
void vertex() {
	cdata = custom_override.x >= 0.0 ? custom_override : INSTANCE_CUSTOM;
	float n = round(cdata.r*16.0);
	bool bedrock = cdata.a > 0.75;
	float variant = mod(floor(cdata.g*1024.0),4.0);
	float a = plateau_height(COLOR.xy,UV2.x,variant,n,bedrock);
	float b = plateau_height(COLOR.zw,UV2.x,variant,n,bedrock);
	VERTEX += surface_normal(UV2.x)*(mix(a,b,UV2.y)-0.12);
	if (distance(COLOR.xy,COLOR.zw) > 0.001 && a < b) { NORMAL = -NORMAL; }
}
void fragment() {
	float n = round(cdata.r * 16.0);
	bool bedrock = cdata.a > 0.75;
	vec3 color;
	if (bedrock) { color = texture(atlas_5, UV).rgb; }
	else if (n < 1.0) { color = texture(atlas_0, UV).rgb; }
	else if (n < 5.0) { color = texture(atlas_1, UV).rgb; }
	else if (n < 10.0) { color = texture(atlas_2, UV).rgb; }
	else if (n < 13.0) { color = texture(atlas_3, UV).rgb; }
	else { color = texture(atlas_4, UV).rgb; }
	ALBEDO = color;
	METALLIC = 0.0;
	ROUGHNESS = bedrock ? 0.76 : 0.94;
	SPECULAR = bedrock ? 0.48 : 0.30;
	EMISSION = vec3(1.0, 0.78, 0.45) * cdata.b * 0.22;
}
