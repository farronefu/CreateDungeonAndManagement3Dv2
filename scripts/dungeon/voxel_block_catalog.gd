class_name VoxelBlockCatalog
extends RefCounted
## Original six-face atlases, with a cached closed shell and stable connected relief profiles.
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
static var _depth_texture: Texture2D
static var _depth_image: Image

static func _load_assets() -> void:
	if _mesh:
		return
	for path in PATHS:
		var scene := (load(path) as PackedScene).instantiate()
		var mi := scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		_textures.append((mi.get_active_material(0) as BaseMaterial3D).albedo_texture)
		scene.free()
	_mesh = BlockSurfaceMesh.build()
	_depth_texture = load("res://assets/models/blocks/block_surface_depth.png")

static func mesh() -> Mesh:
	_load_assets()
	return _mesh

static func material() -> ShaderMaterial:
	_load_assets()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/voxel_block.gdshader")
	mat.set_shader_parameter("height_atlas", _depth_texture)
	for i in _textures.size():
		mat.set_shader_parameter("atlas_%d" % i, _textures[i])
	return mat

static func debris_color(nutrient: int) -> Color:
	match Balance.soil_stage(nutrient):
		0: return Color(0.40, 0.42, 0.44)
		1: return Color(0.27, 0.43, 0.18)
		2: return Color(0.25, 0.40, 0.13)
	return Color(0.38, 0.23, 0.11)


## Mirrors the vertex shader for bounds/stability validation; never called by the frame loop.
static func surface_height(face: int, cell: Vector2i, nutrient: int, seed_value: float, bedrock: bool = false) -> float:
	_load_assets()
	if _depth_image == null:
		_depth_image = _depth_texture.get_image()
	var variant := int(floorf(seed_value * 1024.0)) % BlockSurfaceMesh.VARIANTS
	var pixel := _depth_image.get_pixel(variant*BlockSurfaceMesh.GRID+cell.x,face*BlockSurfaceMesh.GRID+cell.y)
	var level := pixel.r
	if bedrock:
		level = 0.85 + pixel.r*0.15
	elif nutrient >= 10:
		level = pixel.a
	elif nutrient >= 5:
		level = pixel.b
	elif nutrient >= 1:
		level = pixel.g
	return level * BlockSurfaceMesh.DEPTH
