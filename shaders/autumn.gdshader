shader_type spatial;
render_mode cull_disabled;
uniform sampler2D color_tex : source_color, filter_linear_mipmap;
uniform float autumn=0.0;
void fragment(){
 vec3 color=texture(color_tex,UV).rgb;
 float leaf_mask=step(color.r*0.78,color.g);
 ALBEDO=mix(color,color*vec3(1.25,0.46,0.12),leaf_mask*autumn);
 ROUGHNESS=0.8;
}
