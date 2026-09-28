class_name Maou
extends Node3D
## The demon lord. Stands near the entrance from the start of each stage; if the hero drags him
## out through the entrance, the stage is lost.
##
## Models: assets/models/demon-king/demon-king.glb (idle, look_around, cower_in, cower, cower_out)
## while free, and demon-king-wrapped.glb (struggle) once captured. The moods the game asks for:
##   idle     stands; every LOOK_EVERY seconds he looks around once
##   scared   (hero close by) crouches on the floor hiding his face and trembles (cower_in, then
##            cower on a loop); once the hero is gone he gets back up (cower_out)
##   cheer    hops on the spot
##   land     (placed / dropped) a small squash on touching down
##   captured the hero grabs him from the next cell: wrapped in bandages he lies on the floor
##            kicking, and is dragged one cell behind the hero, head towards it

const LOOK_EVERY := Vector2(7.0, 12.0)

var cell := Vector2i(-1, -1)
var placed := false
var carrier: Node3D
var actor: ModelActor
var mood := "idle"
var _wrapped: ModelActor
var _ring: MeshInstance3D
var _look_in := 5.0
var _t := 0.0
var _squash: Tween
var _base_scale := Vector3.ONE
var _drag_from := Vector2i(-1, -1)   # cell he is being dragged out of (lerps with the hero's step)
enum Cower { STANDING, GOING_DOWN, DOWN, GETTING_UP }
var _cower := Cower.STANDING


func _ready() -> void:
	actor = MonsterCatalog.make_actor("maou")
	add_child(actor)
	_base_scale = actor.scale
	actor.play("idle", 0.0)
	# the wrapped model's origin is at the legs: centre the body on the cell
	_wrapped = MonsterCatalog.make_actor("maou_wrapped")
	var holder := Node3D.new()
	add_child(holder)
	holder.add_child(_wrapped)
	var box := _wrapped.local_aabb()
	_wrapped.position = -Vector3(box.get_center().x, 0, box.get_center().z)
	_wrapped.play("idle", 0.0)
	holder.visible = false
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


## Puts him on `c`. `quiet`: no landing squash / sound (set up at the start of the stage).
func place(c: Vector2i, quiet: bool = false) -> void:
	cell = c
	placed = true
	visible = true
	position = DungeonGrid.cell_center(c)
	rotation.y = 0.0
	_cower = Cower.STANDING
	if quiet:
		actor.play("idle", 0.0, 1.0, true)
		return
	_land()
	Sfx.play("place", position)


## Captured by the hero standing in the next cell: he stays in his cell, now wrapped up.
func pick_up(hero: Node3D) -> void:
	carrier = hero
	_drag_from = cell
	_ring.visible = false
	actor.visible = false
	_wrapped.get_parent().visible = true
	_wrapped.play("idle", 0.0)
	_face(hero.position, 1.0)


## The hero stepped out of \`hero_cell\`: he is dragged into it.
func follow_step(hero_cell: Vector2i) -> void:
	_drag_from = cell
	cell = hero_cell


func drop(c: Vector2i) -> void:
	carrier = null
	cell = c
	position = DungeonGrid.cell_center(c)
	rotation = Vector3.ZERO
	actor.visible = true
	_wrapped.get_parent().visible = false
	_ring.visible = true
	_cower = Cower.STANDING
	actor.play("idle", 0.0, 1.0, true)
	_land()


func set_mood(m: String) -> void:
	mood = m


func _face(p: Vector3, k: float) -> void:
	var d := p - position
	if Vector2(d.x, d.z).length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), k)


## Crouching while the hero is close: cower_in -> cower (loop) -> cower_out when it has gone.
## Returns true while the cower animations are in charge.
func _update_cower() -> bool:
	var scared := mood == "scared"
	match _cower:
		Cower.STANDING:
			if not scared:
				return false
			actor.play_once("cower_in", 1.0, 0.2)
			_cower = Cower.GOING_DOWN
		Cower.GOING_DOWN:
			if not scared:
				actor.play_once("cower_out", 1.0, 0.15)
				_cower = Cower.GETTING_UP
			elif not actor.is_busy():
				actor.play("cower", 0.1, 1.0, true)
				_cower = Cower.DOWN
		Cower.DOWN:
			if not scared:
				actor.play_once("cower_out", 1.0, 0.1)
				_cower = Cower.GETTING_UP
		Cower.GETTING_UP:
			if scared:
				actor.play_once("cower_in", 1.0, 0.2)
				_cower = Cower.GOING_DOWN
			elif not actor.is_busy():
				actor.play("idle", 0.2, 1.0, true)
				_look_in = randf_range(LOOK_EVERY.x, LOOK_EVERY.y)
				_cower = Cower.STANDING
				return false
	return true


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
		# one cell behind the hero, sliding in step with it, head towards it
		var t: float = carrier.get("move_t")
		position = DungeonGrid.cell_center(_drag_from).lerp(DungeonGrid.cell_center(cell), clampf(t, 0.0, 1.0))
		_face(carrier.position, clampf(delta * 8.0, 0.0, 1.0))
		return
	# cheering: hop on the spot
	actor.position.y = absf(sin(_t * 7.0)) * 0.14 if mood == "cheer" else 0.0
	if _update_cower():
		return
	if actor.is_busy():
		return
	_look_in -= delta
	if _look_in <= 0.0:
		_look_in = randf_range(LOOK_EVERY.x, LOOK_EVERY.y)
		actor.play_once("look_around", 1.0, 0.3)
	else:
		actor.play("idle", 0.3)
