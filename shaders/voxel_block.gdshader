shader_type spatial;
render_mode diffuse_toon, specular_toon;
// Keep authored six-face UVs and colors. Custom data: nutrient/16, seed, hover, bedrock.
uniform sampler2D atlas_0 : source_color, filter_nearest_mipmap, repeat_disable;
uniform sampler2D atlas_1 : source_color, filter_nearest_mipmap, repeat_disable;
uniform sampler2D atlas_2 : source_color, filter_nearest_mipmap, repeat_disable;
uniform sampler2D atlas_3 : source_color, filter_nearest_mipmap, repeat_disable;
uniform sampler2D atlas_4 : source_color, filter_nearest_mipmap, repeat_disable;
uniform sampler2D atlas_5 : source_color, filter_nearest_mipmap, repeat_disable;
uniform vec4 custom_override = vec4(-1.0);
varying vec4 cdata;
void vertex() {
	cdata = custom_override.x >= 0.0 ? custom_override : INSTANCE_CUSTOM;
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
