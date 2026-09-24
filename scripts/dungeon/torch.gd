class_name Torch
extends Node3D
## Standing torch: wooden pole, animated flame billboard and a flickering light.

static var _flame_mat: ShaderMaterial
static var _pole_mesh: CylinderMesh
static var _pole_mat: StandardMaterial3D

var _light: OmniLight3D
var _t := 0.0


func _ready() -> void:
	if _flame_mat == null:
		_flame_mat = ShaderMaterial.new()
		_flame_mat.shader = load("res://shaders/flame.gdshader")
		_flame_mat.set_shader_parameter("noise_a", ProcGen.noise_b())
		_pole_mesh = CylinderMesh.new()
		_pole_mesh.top_radius = 0.03
		_pole_mesh.bottom_radius = 0.04
		_pole_mesh.height = 0.55
		_pole_mesh.radial_segments = 8
		_pole_mat = StandardMaterial3D.new()
		_pole_mat.albedo_color = Color("5a3a22")
		_pole_mat.roughness = 0.8
	_t = randf() * 10.0
	var pole := MeshInstance3D.new()
	pole.mesh = _pole_mesh
	pole.material_override = _pole_mat
	pole.position.y = 0.275
	add_child(pole)
	var bowl := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.08
	bm.bottom_radius = 0.04
	bm.height = 0.07
	bm.radial_segments = 10
	bowl.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color("3a3438")
	bmat.metallic = 0.6
	bmat.roughness = 0.4
	bowl.material_override = bmat
	bowl.position.y = 0.58
	add_child(bowl)
	var flame := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.34, 0.5)
	flame.mesh = q
	flame.material_override = _flame_mat
	flame.position.y = 0.8
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flame)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.68, 0.36)
	_light.omni_range = 4.2
	_light.omni_attenuation = 1.4
	_light.light_energy = 2.2
	_light.position.y = 0.85
	add_child(_light)


func _process(delta: float) -> void:
	_t += delta
	_light.light_energy = 2.1 + sin(_t * 9.0) * 0.15 + sin(_t * 23.0) * 0.1
