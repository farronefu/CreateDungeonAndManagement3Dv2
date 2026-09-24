class_name Hero
extends Node3D
## The invading hero. Explores the dungeon cell by cell, fights any monster next to it,
## heals with MP, and when it finds the 魔王 carries him back to the entrance.

signal hp_changed
signal died
signal escaped_with_maou
signal picked_up_maou

enum State { WAITING, ENTERING, ACTIVE, DEAD }

var profile: HeroProfile
var grid: DungeonGrid
var eco: Ecosystem
var maou: Maou
var fx: Effects

var state := State.WAITING
var cell := Vector2i.ZERO
var from_cell := Vector2i.ZERO
var move_t := 1.0
var move_dur := 0.5
var dir := Vector2i(0, 1)
var hp := 100.0
var max_hp := 100.0
var mp := 30.0
var max_mp := 30.0
var atk := 8.0
var defense := 1.0
var carrying := false
var knows_maou := false
var busy := 0.0
var attack_cd := 0.0
var actor: ModelActor
var visited := PackedByteArray()
var rng := RandomNumberGenerator.new()

var _pending_hit: Monster
var _hit_timer := -1.0
var _yaw := 0.0
var _enter_t := 0.0
var _dead_t := 0.0


func setup(p: HeroProfile, g: DungeonGrid, e: Ecosystem, mz: Maou, effects: Effects, mult: float) -> void:
	profile = p
	grid = g
	eco = e
	maou = mz
	fx = effects
	max_hp = round(p.max_hp * mult)
	hp = max_hp
	max_mp = p.max_mp
	mp = max_mp
	atk = p.atk * mult
	defense = p.defense + (mult - 1.0) * 3.0
	actor = ModelActor.new()
	add_child(actor)
	actor.setup(load(p.model_path), p.model_height, deg_to_rad(p.model_yaw_offset_deg), false, [p.anim_walk, p.anim_idle])
	actor.play(p.anim_idle, 0.0)
	visited.resize(grid.w * grid.h)
	visible = false


func is_targetable() -> bool:
	return state == State.ACTIVE


func begin_invasion() -> void:
	state = State.ENTERING
	visible = true
	cell = grid.entrance
	from_cell = cell
	dir = Vector2i(0, 1)
	_yaw = 0.0
	_enter_t = 0.0
	visited.fill(0)


func tick(dt: float) -> void:
	match state:
		State.ENTERING:
			_enter_t += dt
			var t := clampf(_enter_t / 1.6, 0.0, 1.0)
			var outside := DungeonGrid.cell_center(grid.entrance) + Vector3(0, 0, -1.4)
			position = outside.lerp(DungeonGrid.cell_center(grid.entrance), t)
			rotation.y = 0.0
			actor.play(profile.anim_walk, 0.1, profile.walk_anim_speed)
			if t >= 1.0:
				state = State.ACTIVE
				_mark_visited()
		State.ACTIVE:
			_logic(dt)
			_visual(dt)
		State.DEAD:
			_dead_t += dt


# ------------------------------------------------------------------ logic
func _logic(dt: float) -> void:
	attack_cd = maxf(0.0, attack_cd - dt)
	if _hit_timer >= 0.0:
		_hit_timer -= dt
		if _hit_timer < 0.0:
			_apply_hit()
	if busy > 0.0:
		busy -= dt
		return
	if move_t < 1.0:
		move_t = minf(1.0, move_t + dt / move_dur)
		if move_t >= 1.0:
			_mark_visited()
		else:
			return
	_decide()


func _decide() -> void:
	if state != State.ACTIVE:
		return
	if hp < max_hp * 0.4 and mp >= profile.heal_cost:
		_heal()
		return
	var target := _pick_target()
	if target:
		_attack(target)
		return
	if carrying:
		if cell == grid.entrance:
			state = State.DEAD
			escaped_with_maou.emit()
			return
		_step_along(grid.find_path(cell, grid.entrance))
		return
	if not knows_maou and maou.placed and _can_see(maou.cell):
		knows_maou = true
	if knows_maou and maou.placed and maou.carrier == null:
		if cell == maou.cell:
			_pick_up()
			return
		var path := grid.find_path(cell, maou.cell)
		if not path.is_empty():
			_step_along(path)
			return
	# explore: nearest unvisited floor cell
	var path2 := grid.path_to_nearest(cell, func(c: Vector2i) -> bool: return visited[grid.idx(c)] == 0)
	if path2.is_empty():
		var n := grid.floor_neighbors(cell)
		if n.is_empty():
			busy = 0.5
			return
		_step(n[rng.randi() % n.size()])
	else:
		_step_along(path2)


func _can_see(c: Vector2i) -> bool:
	var d := absi(c.x - cell.x) + absi(c.y - cell.y)
	if d > profile.sight:
		return false
	var path := grid.find_path(cell, c)
	return path.size() <= profile.sight + 2 or d == 0


func _mark_visited() -> void:
	visited[grid.idx(cell)] = 1
	for d in DungeonGrid.DIRS:
		if grid.is_floor(cell + d):
			visited[grid.idx(cell + d)] = 1


func _step_along(path: Array[Vector2i]) -> void:
	if path.is_empty():
		busy = 0.3
		return
	_step(path[0])


func _step(to: Vector2i) -> void:
	from_cell = cell
	dir = to - cell
	cell = to
	move_t = 0.0
	move_dur = profile.carry_move_time if carrying else profile.move_time


func _pick_target() -> Monster:
	var best: Monster = null
	for m in eco.monsters_near(cell, 1):
		if best == null or m.threat() > best.threat() or (m.threat() == best.threat() and m.hp < best.hp):
			best = m
	return best


func _attack(m: Monster) -> void:
	var d := m.cell - cell
	if d != Vector2i.ZERO:
		dir = d
	if attack_cd > 0.0:
		busy = minf(attack_cd, 0.15)
		return
	attack_cd = profile.attack_interval
	var dur := actor.play_once(profile.anim_attack, profile.attack_anim_speed)
	busy = minf(dur, profile.attack_interval) if dur > 0.0 else 0.6
	_pending_hit = m
	_hit_timer = profile.attack_hit_time / profile.attack_anim_speed
	Sfx.play("swing", position)


func _apply_hit() -> void:
	var m := _pending_hit
	_pending_hit = null
	if m == null or not m.alive:
		return
	if absi(m.cell.x - cell.x) + absi(m.cell.y - cell.y) > 1:
		return
	var dmg := int(round(atk * rng.randf_range(0.85, 1.2)))
	m.hp -= dmg
	var v := m.visual as MonsterVisual
	if v:
		fx.number(v.position + Vector3(0, 0.6, 0), str(dmg), Color(1, 1, 1))
		v.hurt()
	Sfx.play("hit", position)
	if m.hp <= 0.0:
		eco.kill(m, "killed")


func take_damage(d: int, _from: Monster) -> void:
	if state != State.ACTIVE:
		return
	var dmg := maxi(1, d - int(defense))
	hp -= dmg
	actor.flash(Color(1, 0.2, 0.15))
	fx.number(position + Vector3(0, 1.0, 0), str(dmg), Color(1.0, 0.35, 0.3), true)
	Sfx.play("hero_hurt", position)
	hp_changed.emit()
	if hp <= 0.0:
		_die()


func _heal() -> void:
	mp -= profile.heal_cost
	var before := hp
	hp = minf(max_hp, hp + profile.heal_amount)
	busy = 1.0
	actor.play(profile.anim_idle, 0.1, 1.0, true)
	fx.sparkle(position + Vector3(0, 0.5, 0), Color(0.5, 1.0, 0.6), 22)
	fx.ring(position, Color(0.5, 1.0, 0.6))
	fx.number(position + Vector3(0, 1.1, 0), "+%d" % int(hp - before), Color(0.5, 1.0, 0.6), true)
	Sfx.play("heal", position)
	hp_changed.emit()


func _pick_up() -> void:
	carrying = true
	busy = 0.8
	maou.pick_up(self)
	picked_up_maou.emit()
	Sfx.play("grab", position)


func _die() -> void:
	state = State.DEAD
	hp = 0
	if carrying:
		carrying = false
		maou.drop(cell)
	died.emit()
	# fall over and fade
	var tw := create_tween().set_parallel(true)
	tw.tween_property(actor, "rotation:x", -PI / 2.0, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(actor, "position:y", 0.12, 0.6)
	tw.chain().tween_interval(1.2)
	tw.chain().tween_method(actor.set_fade, 1.0, 0.0, 0.8)
	fx.dust(position + Vector3(0, 0.2, 0), Color(0.8, 0.75, 0.7, 0.7), 1.2)


# ------------------------------------------------------------------ visuals
func _visual(dt: float) -> void:
	var a := DungeonGrid.cell_center(from_cell)
	var b := DungeonGrid.cell_center(cell)
	position = a.lerp(b, move_t)
	var target := atan2(float(dir.x), float(dir.y))
	_yaw = lerp_angle(_yaw, target, clampf(dt * 12.0, 0.0, 1.0))
	rotation.y = _yaw
	if actor.is_busy():
		return
	if move_t < 1.0:
		actor.play(profile.anim_walk, 0.12, profile.walk_anim_speed * profile.move_time / move_dur)
	else:
		actor.play(profile.anim_idle, 0.2)
