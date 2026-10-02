class_name VoxelBlockCatalog
extends RefCounted
## Approved individual GLBs share identical geometry/UVs; only their embedded atlases differ.
const PATHS := [
	"res://assets/models/blocks/Block_Nutrient_00_Rock.glb",
	"res://assets/models/blocks/Block_Nutrient_01_04_Moss.glb",
	"res://assets/models/blocks/Block_Nutrient_05_09_Green.glb",
	"res://assets/models/blocks/Block_Nutrient_10_12_Dry.glb",
	"res://assets/models/blocks/Block_Nutrient_13Plus_Dry.glb",
	"res://assets/models/blocks/Block_Bedrock_Obsidian.glb",
]
static var _mesh: Mesh
static var _textures: Array[Texture2D] = []

static func _load_assets() -> void:
	if _mesh:
		return
	for path in PATHS:
		var scene := (load(path) as PackedScene).instantiate()
		var mi := scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		if _mesh == null:
			_mesh = mi.mesh
		_textures.append((mi.get_active_material(0) as BaseMaterial3D).albedo_texture)
		scene.free()

static func mesh() -> Mesh:
	_load_assets()
	return _mesh

static func material() -> ShaderMaterial:
	_load_assets()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/voxel_block.gdshader")
	for i in _textures.size():
		mat.set_shader_parameter("atlas_%d" % i, _textures[i])
	return mat

static func debris_color(nutrient: int) -> Color:
	match Balance.soil_stage(nutrient):
		0: return Color(0.40, 0.42, 0.44)
		1: return Color(0.27, 0.43, 0.18)
		2: return Color(0.25, 0.40, 0.13)
	return Color(0.38, 0.23, 0.11)
