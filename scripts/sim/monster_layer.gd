class_name MonsterLayer
extends Node3D
## Creates / updates / removes the 3D visuals for every monster in the Ecosystem.

var eco: Ecosystem
var fx: Effects
var _visuals := {}  # Monster.id -> MonsterVisual


func setup(e: Ecosystem, effects: Effects) -> void:
	eco = e
	fx = effects
	eco.spawned.connect(_on_spawned)
	eco.died.connect(_on_died)
	eco.evolved.connect(_on_evolved)
	eco.nutrient_flow.connect(_on_flow)
	eco.ate.connect(_on_ate)
	for m in eco.monsters:
		_on_spawned(m, "load")


func _on_spawned(m: Monster, cause: String) -> void:
	var v := MonsterVisual.new()
	add_child(v)
	v.setup(m, cause != "load")
	_visuals[m.id] = v
	if cause == "dig" or cause == "birth":
		var col := Color(0.55, 1.0, 0.3) if m.kind == Monster.Kind.MOSS else Color(1.0, 0.6, 0.2)
		fx.sparkle(v.position + Vector3(0, 0.25, 0), col, 10)
		Sfx.play("spawn_moss" if m.kind == Monster.Kind.MOSS else "spawn_bug", v.position)


func _on_died(m: Monster, cause: String) -> void:
	var v: MonsterVisual = _visuals.get(m.id)
	if v == null:
		return
	_visuals.erase(m.id)
	v.die(cause)
	if cause == "killed":
		Sfx.play("monster_die", v.position)
	if cause != "eaten":
		fx.dust(v.position + Vector3(0, 0.15, 0), Color(0.55, 0.75, 0.35, 0.6) if m.kind == Monster.Kind.MOSS else Color(0.6, 0.45, 0.3, 0.6), 0.7)


func _on_evolved(m: Monster) -> void:
	var v: MonsterVisual = _visuals.get(m.id)
	if v:
		if m.kind == Monster.Kind.MOSS and m.stage == Monster.BUD:
			v.play_evolution()
		else:
			v.swap_model()
		fx.ring(v.position, Color(1.0, 0.9, 0.4))
		fx.sparkle(v.position + Vector3(0, 0.3, 0), Color(1.0, 0.9, 0.4), 16)
		Sfx.play("evolve", v.position)


func _on_flow(block: Vector2i, m: Monster, into_monster: bool) -> void:
	var v: MonsterVisual = _visuals.get(m.id)
	if v == null:
		return
	var b := DungeonGrid.cell_center(block, Balance.BLOCK_H * 0.6)
	var p := v.position + Vector3(0, 0.25, 0)
	if into_monster:
		fx.motes(b, p, Color(0.55, 1.0, 0.3))
	else:
		fx.motes(p, b, Color(0.9, 0.85, 0.3))


func _on_ate(pred: Monster, prey: Monster) -> void:
	var v: MonsterVisual = _visuals.get(prey.id)
	if v:
		fx.sparkle(v.position + Vector3(0, 0.2, 0), Color(0.6, 0.9, 0.3), 10)
	Sfx.play("eat", v.position if v else Vector3.ZERO)


func visual_of(m: Monster) -> MonsterVisual:
	return _visuals.get(m.id)


func _process(delta: float) -> void:
	for v in _visuals.values():
		(v as MonsterVisual).sync(delta)
