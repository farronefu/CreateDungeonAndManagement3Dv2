class_name Maou
extends Node3D
## The demon lord. Placed by the player before the invasion; if the hero carries him
## out through the entrance, the stage is lost.

var cell := Vector2i(-1, -1)
var placed := false
var carrier: Node3D
var actor: ModelActor
var mood := "idle"
var _ring: MeshInstance3D


func _ready() -> void:
	actor = MonsterCatalog.make_actor("maou")
	add_child(actor)
	actor.play("idle", 0.0)
	# soft purple aura ring on the floor so the player can always spot him
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.32
	tm.outer_radius = 0.4
	tm.rings = 32
	tm.ring_segments = 4
	_ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.75, 0.35, 1.0, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring.material_override = mat
	_ring.scale = Vector3(1, 0.1, 1)
	_ring.position.y = 0.02
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	visible = false


func place(c: Vector2i) -> void:
	cell = c
	placed = true
	visible = true
	position = DungeonGrid.cell_center(c)
	rotation.y = 0.0
	actor.play_once("land")
	Sfx.play("place", position)


func pick_up(hero: Node3D) -> void:
	carrier = hero
	_ring.visible = false
	actor.play("carried", 0.1, 1.0, true)


func drop(c: Vector2i) -> void:
	carrier = null
	cell = c
	position = DungeonGrid.cell_center(c)
	rotation = Vector3.ZERO
	_ring.visible = true
	actor.play_once("land")


func set_mood(m: String) -> void:
	mood = m


func _process(delta: float) -> void:
	if not placed:
		return
	_ring.rotation.y += delta * 0.8
	if carrier:
		position = carrier.position + Vector3(0, 0.78, 0) + carrier.basis.z * -0.05
		rotation.y = carrier.rotation.y
		cell = carrier.get("cell")
		actor.play("carried")
		return
	actor.play(mood)
