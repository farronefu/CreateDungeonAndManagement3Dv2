class_name Hero
extends Node3D
## The invading hero. During the build phase it walks down the cliff steps into the fog and
## disappears (the countdown is the time it wanders there); when the invasion starts the gate
## doors open and it walks in. Then it explores the dungeon cell by cell, fights any monster
## next to it, heals with MP, and when it finds the 魔王 carries him back to the entrance.

signal hp_changed
signal died
signal escaped_with_maou
signal picked_up_maou
signal found_maou
## asks the game to plant a torch here (the game owns the torch nodes, see `torches`)
signal torch_request(cell: Vector2i)

enum State { WAITING, DESCENDING, ENTERING, ACTIVE, DEAD }

const DOOR_DELAY := 0.9     # seconds the doors take to swing open before the hero steps out
const FADE_DIST := 1.4      # the hero fades out over the last cells of the descent

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
var _grab_timer := -1.0
## world-space walks (set by main from SurfaceWorld): town -> into the fog, gate -> dungeon
var descent_path := PackedVector3Array()
var entry_path := PackedVector3Array()
## the surface world, which owns the gate doors
var gate: SurfaceWorld
var _descent_t := 0.0
## the dungeon as it was when the hero came in (1 = floor then); tunnels dug later are ignored
var known := PackedByteArray()
## corridor forks where the hero already looked around
var _looked := {}
## torches in the dungeon: cell -> node (shared with main, which adds and removes them)
var torches := {}
var _seen_since_torch := 0
var _on_torch := Vector2i(-999, -999)


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
	if p.plastic_look:
		actor.plasticize(p.armor_tint, p.armor_roughness)
	actor.play(p.anim_idle, 0.0)
	visited.resize(grid.w * grid.h)
	visible = false


func is_targetable() -> bool:
	return state == State.ACTIVE


## Build phase: walk from the road down the steps into the fog and vanish there.
func begin_descent() -> void:
	if descent_path.size() < 2:
		return
	state = State.DESCENDING
	visible = true
	actor.set_fade(1.0)
	_descent_t = 0.0
	position = descent_path[0]


## Invasion: the gate doors open and the hero, waiting behind them, walks in.
func begin_invasion() -> void:
	state = State.ENTERING
	visible = true
	actor.set_fade(1.0)
	cell = grid.entrance
	from_cell = cell
	dir = Vector2i(0, 1)
	_yaw = 0.0
	rotation.y = 0.0
	_enter_t = -DOOR_DELAY if gate else 0.0
	if entry_path.size() > 0:
		position = entry_path[0]
	if gate:
		gate.open_gate()
	visited.fill(0)
	_looked.clear()
	_seen_since_torch = 0
	known.resize(grid.w * grid.h)
	for i in known.size():
		known[i] = 1 if grid.types[i] == DungeonGrid.FLOOR else 0


func tick(dt: float) -> void:
	match state:
		State.DESCENDING:
			_descent_t += dt
			var dist := _descent_t / profile.move_time
			var left := _path_length(descent_path) - dist
			actor.set_fade(clampf(left / FADE_DIST, 0.0, 1.0))
			actor.play(profile.anim_walk, 0.1, profile.walk_anim_speed)
			if _walk(descent_path, dist):
				visible = false
				state = State.WAITING
		State.ENTERING:
			_enter_t += dt
			if _enter_t < 0.0:
				actor.play(profile.anim_idle, 0.1)
				return
			var done := _walk(entry_path, _enter_t / profile.move_time)
			actor.play(profile.anim_walk, 0.1, profile.walk_anim_speed)
			if done:
				state = State.ACTIVE
				_mark_visited()
		State.ACTIVE:
			# the door stands open while the hero is in or right next to the entrance cell
			if gate:
				var near := cell.x == grid.entrance.x and cell.y <= grid.entrance.y + 1 and from_cell.y <= grid.entrance.y + 1
				if near:
					gate.open_gate()
				else:
					gate.close_gate()
			_logic(dt)
			_visual(dt)
		State.DEAD:
			_dead_t += dt


func _path_length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in path.size() - 1:
		total += path[i].distance_to(path[i + 1])
	return total


## Walks `dist` cells along `path`; returns true at the end.
func _walk(path: PackedVector3Array, dist: float) -> bool:
	if path.size() < 2:
		path = PackedVector3Array([DungeonGrid.cell_center(grid.entrance) + Vector3(0, 0, -1.4), DungeonGrid.cell_center(grid.entrance)])
	var left := dist
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var seg := a.distance_to(b)
		if left <= seg:
			position = a.lerp(b, left / maxf(seg, 0.001))
			var d := b - a
			if Vector2(d.x, d.z).length() > 0.01:
				rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), 0.25)
			return false
		left -= seg
	position = path[path.size() - 1]
	return true


# ------------------------------------------------------------------ logic
func _logic(dt: float) -> void:
	attack_cd = maxf(0.0, attack_cd - dt)
	if _grab_timer >= 0.0:
		_grab_timer -= dt
		if _grab_timer < 0.0 and cell == maou.cell and maou.carrier == null:
			_pick_up()
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
			if gate:
				gate.open_gate()
			state = State.DEAD
			escaped_with_maou.emit()
			return
		_step_along(grid.find_path(cell, grid.entrance, known))
		return
	if not knows_maou and maou.placed and _can_see(maou.cell):
		knows_maou = true
	if knows_maou and maou.placed and maou.carrier == null:
		if cell == maou.cell:
			_celebrate_then_grab()
			return
		var path := grid.find_path(cell, maou.cell, known)
		if not path.is_empty():
			_step_along(path)
			return
	# at a fork of one-block-wide corridors, look around once (not again when passing back)
	if not _looked.has(cell) and _is_corridor_fork(cell) and actor.has_anim(profile.anim_look):
		_looked[cell] = true
		busy = actor.play_once(profile.anim_look, profile.look_anim_speed)
		return
	# explore: nearest unvisited floor cell
	var path2 := grid.path_to_nearest(cell, func(c: Vector2i) -> bool: return visited[grid.idx(c)] == 0, 9999, known)
	if path2.is_empty():
		var n := grid.floor_neighbors(cell, known)
		if n.is_empty():
			busy = 0.5
			return
		_step(n[rng.randi() % n.size()])
	else:
		_step_along(path2)


## Three or more real ways out, and the cell is part of a one-block-wide corridor (no 2x2 patch
## of floor around it, so open rooms do not count). A branch that is a single dug block (a dead
## end right next to the corridor) is not a way out.
func _is_corridor_fork(c: Vector2i) -> bool:
	var ways := 0
	for n in grid.floor_neighbors(c, known):
		if grid.floor_neighbors(n, known).size() > 1:
			ways += 1
	if ways < 3:
		return false
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			if grid.walkable(c + Vector2i(sx, 0), known) and grid.walkable(c + Vector2i(0, sy), known) and grid.walkable(c + Vector2i(sx, sy), known):
				return false
	return true


func _can_see(c: Vector2i) -> bool:
	var d := absi(c.x - cell.x) + absi(c.y - cell.y)
	if d > profile.sight:
		return false
	var path := grid.find_path(cell, c, known)
	return path.size() <= profile.sight + 2 or d == 0


## Everything the hero can see from here counts as explored: floor within HERO_SIGHT cells with
## a clear line of sight (walls and corners block it), so a big room is taken in at a glance
## while corridors are still walked cell by cell. Also handles torches (heal / plant).
func _mark_visited() -> void:
	var r := Balance.HERO_SIGHT
	var fresh := 0
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r + 1:
				continue
			var c := cell + Vector2i(dx, dy)
			if not grid.in_bounds(c) or visited[grid.idx(c)] == 1:
				continue
			if grid.walkable(c, known) and _line_clear(cell, c):
				visited[grid.idx(c)] = 1
				fresh += 1
	_seen_since_torch += fresh
	_torch_step()


## True when every cell on the straight line between the two cell centres is walkable.
func _line_clear(a: Vector2i, b: Vector2i) -> bool:
	var n := maxi(absi(b.x - a.x), absi(b.y - a.y)) * 2
	for i in range(1, n):
		var t := float(i) / float(n)
		var p := Vector2(a) + Vector2(b - a) * t
		if not grid.walkable(Vector2i(roundi(p.x), roundi(p.y)), known):
			return false
	return true


## Walking onto a torch heals a tenth of HP and MP (once per visit); after exploring enough
## new ground the hero plants one, so the player can see how far it has searched.
func _torch_step() -> void:
	if torches.has(cell):
		if _on_torch != cell:
			_on_torch = cell
			var dh := minf(max_hp - hp, max_hp * Balance.TORCH_HEAL)
			var dm := minf(max_mp - mp, max_mp * Balance.TORCH_HEAL)
			hp += dh
			mp += dm
			if dh > 0.0 or dm > 0.0:
				fx.sparkle(position + Vector3(0, 0.5, 0), Color(1.0, 0.8, 0.4), 14)
				if dh >= 1.0:
					fx.number(position + Vector3(0, 1.1, 0), "+%d" % int(dh), Color(0.5, 1.0, 0.6))
				hp_changed.emit()
		return
	_on_torch = Vector2i(-999, -999)
	if carrying or _seen_since_torch < Balance.TORCH_EVERY or cell == grid.entrance:
		return
	for t in torches:
		var tc: Vector2i = t
		if absi(tc.x - cell.x) + absi(tc.y - cell.y) < Balance.TORCH_SPACING:
			return
	_seen_since_torch = 0
	torch_request.emit(cell)
	_on_torch = cell   # no heal from the torch just planted


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


## 魔王を見つけた勇者はまず喜ぶ（その間は無防備）→ 担ぎ上げる
func _celebrate_then_grab() -> void:
	var dur := 0.0
	if actor.has_anim(profile.anim_joy):
		dur = actor.play_once(profile.anim_joy, profile.joy_anim_speed)
	busy = dur + 0.05
	_grab_timer = dur
	found_maou.emit()


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
	# death clip (or a fall-over fallback), hold the pose, then fade out
	var tw := create_tween()
	if actor.has_anim(profile.anim_death):
		var dur := actor.play_once(profile.anim_death, 1.0)
		tw.tween_interval(dur + 1.5)
	else:
		tw.tween_property(actor, "rotation:x", -PI / 2.0, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_interval(1.2)
	tw.tween_method(actor.set_fade, 1.0, 0.0, 1.2)
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
