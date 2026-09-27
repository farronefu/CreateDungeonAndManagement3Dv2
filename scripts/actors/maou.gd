class_name Maou
extends Node3D
## The demon lord. Placed by the player before the invasion; if the hero carries him
## out through the entrance, the stage is lost.
##
## Model: assets/models/demon-king/demon-king.glb (clips: idle, look_around). The moods the game
## asks for are built from those plus a little procedural motion:
##   idle     stands; every LOOK_EVERY seconds he looks around once
##   scared   (hero close by) keeps looking around, a bit faster
##   cheer    hops on the spot
##   carried  lies across the hero's shoulders
##   land     (placed / dropped) a small squash on touching down

const LOOK_EVERY := Vector2(7.0, 12.0)
const CARRY_HEIGHT := 0.78

var cell := Vector2i(-1, -1)
var placed := false
var carrier: Node3D
var actor: ModelActor
var mood := "idle"
var _ring: MeshInstance3D
var _look_in := 5.0
var _t := 0.0
var _squash: Tween
var _base_scale := Vector3.ONE


func _ready() -> void:
	actor = MonsterCatalog.make_actor("maou")
	add_child(actor)
	_base_scale = actor.scale
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
	_land()
	Sfx.play("place", position)


func pick_up(hero: Node3D) -> void:
	carrier = hero
	_ring.visible = false
	# lying across the hero's shoulders: body along the hero's left-right axis
	actor.rotation = Vector3(0, 0, PI * 0.5)
	actor.position = Vector3(0.56, 0, 0)
	actor.play("idle", 0.1, 1.0, true)


func drop(c: Vector2i) -> void:
	carrier = null
	cell = c
	position = DungeonGrid.cell_center(c)
	rotation = Vector3.ZERO
	actor.rotation = Vector3.ZERO
	actor.position = Vector3.ZERO
	_ring.visible = true
	_land()


func set_mood(m: String) -> void:
	mood = m


## Touch-down squash (the model has no landing clip).
func _land() -> void:
	if _squash:
		_squash.kill()
	var b := _base_scale
	_squash = create_tween()
	_squash.tween_property(actor, "scale", Vector3(b.x * 1.12, b.y * 0.82, b.z * 1.12), 0.08)
	_squash.tween_property(actor, "scale", b, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if not placed:
		return
	_t += delta
	_ring.rotation.y += delta * 0.8
	if carrier:
		position = carrier.position + Vector3(0, CARRY_HEIGHT, 0) + carrier.basis.z * -0.05
		rotation.y = carrier.rotation.y
		cell = carrier.get("cell")
		actor.play("idle")
		return
	# cheering: hop on the spot
	actor.position.y = absf(sin(_t * 7.0)) * 0.14 if mood == "cheer" else 0.0
	if mood == "scared":
		actor.play("look_around", 0.25, 1.35)
		_look_in = randf_range(LOOK_EVERY.x, LOOK_EVERY.y)
		return
	if actor.is_busy():
		return
	_look_in -= delta
	if _look_in <= 0.0:
		_look_in = randf_range(LOOK_EVERY.x, LOOK_EVERY.y)
		actor.play_once("look_around", 1.0, 0.3)
	else:
		actor.play("idle", 0.3)
