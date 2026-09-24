class_name Ecosystem
extends RefCounted
## Monster ecosystem simulation (logic only; visuals subscribe to the signals).
##
## Food chain modelled after 勇者のくせになまいきだ:
##  - 養分 is conserved: it moves between soil blocks and monsters and returns to the soil when they die.
##  - モコチュリ wanders straight until it hits a wall, trading nutrient with neighbouring soil
##    (1 → absorb, 2+ → release). With nutrient ≥ 2 and HP ≤ 2 it roots into a ツボミ, which
##    gathers nutrient from a 5×5 area and blooms into a モコバナ at 8. The flower scatters up
##    to 5 new moss when its life ends (this is how moss breeds).
##  - ザクザクムシ larvae hunt moss when hungry, pupate at HP 60, hatch into adults after 20 s,
##    and adults with enough HP and nutrient give birth to new larvae.

signal spawned(m: Monster, cause: String)
signal died(m: Monster, cause: String)
signal evolved(m: Monster)
signal nutrient_flow(block: Vector2i, m: Monster, into_monster: bool)
signal hero_hit(m: Monster, damage: int)
signal ate(predator: Monster, prey: Monster)

var grid: DungeonGrid
var monsters: Array[Monster] = []
var hero: Node  # expects: cell, is_targetable(), take_damage(int, Monster)
var rng := RandomNumberGenerator.new()
var moss_level := 0
var bug_level := 0
var _next_id := 1
var _pending_spawns: Array = []


func _init(g: DungeonGrid, seed_value: int = 0) -> void:
	grid = g
	rng.seed = seed_value if seed_value != 0 else Time.get_ticks_usec()


# ------------------------------------------------------------------ queries
func count(kind: int, stage: int = -1) -> int:
	var n := 0
	for m in monsters:
		if m.alive and m.kind == kind and (stage < 0 or m.stage == stage):
			n += 1
	return n


func total_nutrient() -> int:
	var s := 0
	for m in monsters:
		if m.alive:
			s += m.nutrient
	return s


func monsters_near(c: Vector2i, radius: int) -> Array[Monster]:
	var out: Array[Monster] = []
	for m in monsters:
		if m.alive and absi(m.cell.x - c.x) + absi(m.cell.y - c.y) <= radius:
			out.append(m)
	return out


func _moss_mult() -> float:
	return 1.0 + 0.25 * moss_level


func _bug_mult() -> float:
	return 1.0 + 0.25 * bug_level


# ------------------------------------------------------------------ spawning
func spawn(kind: int, stage: int, c: Vector2i, n: int, cause: String = "birth") -> Monster:
	var m := Monster.new()
	m.id = _next_id
	_next_id += 1
	m.kind = kind
	m.cell = c
	m.from_cell = c
	m.nutrient = n
	m.dir = grid.DIRS[rng.randi() % 4]
	m.jitter = Vector2(rng.randf_range(-0.16, 0.16), rng.randf_range(-0.16, 0.16))
	_set_stage(m, stage, true)
	monsters.append(m)
	spawned.emit(m, cause)
	return m


## Called when the player digs a block. Returns the monster born from its nutrient (or null).
func spawn_from_dig(c: Vector2i, n: int) -> Monster:
	if n >= Balance.BUG_SPAWN_MIN:
		if count(Monster.Kind.BUG) >= Balance.MAX_BUGS:
			return _refund(c, n)
		return spawn(Monster.Kind.BUG, Monster.LARVA, c, n, "dig")
	if n >= Balance.MOSS_SPAWN_MIN:
		if count(Monster.Kind.MOSS) >= Balance.MAX_MOSS:
			return _refund(c, n)
		return spawn(Monster.Kind.MOSS, Monster.MOSS, c, n, "dig")
	return null


func _refund(c: Vector2i, n: int) -> Monster:
	_scatter_nutrient(c, n)
	return null


func _set_stage(m: Monster, stage: int, fresh: bool) -> void:
	m.stage = stage
	m.stage_t = 0.0
	m.age = 0.0 if fresh else m.age
	m.timer = 0.0
	m.busy = 0.0
	m.base_anim = "idle"
	var mm := _moss_mult()
	var bm := _bug_mult()
	if m.kind == Monster.Kind.MOSS:
		match stage:
			Monster.MOSS:
				m.max_hp = Balance.MOSS_HP_MAX * mm
				m.hp = Balance.MOSS_HP * mm
				m.atk = Balance.MOSS_ATK * mm
			Monster.BUD:
				m.max_hp = Balance.BUD_HP * mm
				m.hp = m.max_hp
				m.atk = Balance.BUD_ATK * mm
			Monster.FLOWER:
				m.max_hp = Balance.FLOWER_HP * mm
				m.hp = m.max_hp
				m.atk = Balance.FLOWER_ATK * mm
	else:
		match stage:
			Monster.LARVA:
				m.max_hp = Balance.LARVA_HP_MAX * bm
				m.hp = Balance.LARVA_HP * bm
				m.atk = Balance.LARVA_ATK * bm
			Monster.PUPA:
				m.max_hp = maxf(m.hp, Balance.LARVA_PUPATE * bm)
				m.atk = 0
			Monster.ADULT:
				m.max_hp = Balance.ADULT_HP_MAX * bm
				m.hp = maxf(m.hp, Balance.LARVA_PUPATE * bm)
				m.atk = Balance.ADULT_ATK * bm


func _evolve(m: Monster, stage: int) -> void:
	var hp := m.hp
	_set_stage(m, stage, false)
	if m.kind == Monster.Kind.BUG:
		m.hp = minf(maxf(hp, m.hp), m.max_hp)
	m.move_t = 1.0
	m.from_cell = m.cell
	evolved.emit(m)


# ------------------------------------------------------------------ death & nutrient
func kill(m: Monster, cause: String) -> void:
	if not m.alive:
		return
	m.alive = false
	if cause != "eaten":
		_scatter_nutrient(m.cell, m.nutrient)
	m.nutrient = 0
	died.emit(m, cause)


## Returns nutrient to the soil around `c` (conservation law).
func _scatter_nutrient(c: Vector2i, n: int) -> void:
	var left := n
	for radius in range(1, 6):
		if left <= 0:
			return
		var ring: Array[Vector2i] = []
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) + absi(dy) == radius and grid.is_block(c + Vector2i(dx, dy)):
					ring.append(c + Vector2i(dx, dy))
		ring.shuffle()
		var progress := true
		while left > 0 and progress:
			progress = false
			for b in ring:
				if left <= 0:
					break
				if grid.add_nutrient(b, 1) > 0:
					left -= 1
					progress = true


# ------------------------------------------------------------------ main update
func tick(delta: float) -> void:
	for m in monsters.duplicate():
		if not m.alive:
			continue
		m.age += delta
		m.stage_t += delta
		m.cooldown = maxf(0.0, m.cooldown - delta)
		if m.hit_timer >= 0.0:
			m.hit_timer -= delta
			if m.hit_timer < 0.0:
				_land_hit(m)
		if m.kind == Monster.Kind.MOSS:
			match m.stage:
				Monster.MOSS:
					_tick_moss(m, delta)
				Monster.BUD:
					_tick_bud(m, delta)
				Monster.FLOWER:
					_tick_flower(m, delta)
		else:
			match m.stage:
				Monster.LARVA:
					_tick_larva(m, delta)
				Monster.PUPA:
					_tick_pupa(m, delta)
				Monster.ADULT:
					_tick_adult(m, delta)
	for s in _pending_spawns:
		spawn(s[0], s[1], s[2], s[3], s[4])
	_pending_spawns.clear()
	monsters = monsters.filter(func(m: Monster) -> bool: return m.alive)


## Shared: handle busy lock + movement. Returns true if the monster is free to decide.
func _advance(m: Monster, delta: float) -> bool:
	if m.busy > 0.0:
		m.busy -= delta
		return false
	if m.is_moving():
		m.move_t = minf(1.0, m.move_t + delta / m.move_dur)
		if m.move_t >= 1.0:
			_on_arrive(m)
		return false
	return true


func _start_move(m: Monster, to: Vector2i, dur: float) -> void:
	m.from_cell = m.cell
	m.dir = to - m.cell
	m.cell = to
	m.move_t = 0.0
	m.move_dur = dur


func _on_arrive(m: Monster) -> void:
	if m.kind == Monster.Kind.MOSS and m.stage == Monster.MOSS:
		_moss_arrive(m)


func _hero_cell() -> Variant:
	if hero != null and hero.is_targetable():
		return hero.cell
	return null


func _try_attack_hero(m: Monster, front_only: bool) -> bool:
	var hc = _hero_cell()
	if hc == null or m.cooldown > 0.0 or m.atk <= 0.0:
		return false
	var d: Vector2i = hc - m.cell
	var adjacent := absi(d.x) + absi(d.y) <= 1
	if not adjacent:
		return false
	if front_only and d != Vector2i.ZERO and d != m.dir:
		return false
	if d != Vector2i.ZERO:
		m.dir = d
	m.anim_request = "attack"
	m.busy = Balance.MOSS_ATTACK_BUSY if m.kind == Monster.Kind.MOSS else Balance.BUG_ATTACK_BUSY
	if m.kind == Monster.Kind.MOSS:
		m.cooldown = Balance.MOSS_ATTACK_CD if m.stage == Monster.MOSS else Balance.TREE_ATTACK_CD
	else:
		m.cooldown = Balance.BUG_ATTACK_CD
	m.hit_dmg = int(round(m.atk * rng.randf_range(0.85, 1.15)))
	m.hit_timer = m.busy * Balance.ATTACK_HIT_FRACTION
	return true


## The blow connects mid-animation, if the hero is still next to the attacker.
func _land_hit(m: Monster) -> void:
	var hc = _hero_cell()
	if hc == null or not m.alive:
		return
	var d: Vector2i = hc - m.cell
	if absi(d.x) + absi(d.y) > 1:
		return
	hero_hit.emit(m, m.hit_dmg)
	hero.take_damage(m.hit_dmg, m)


func _random_step(m: Monster, straight_bias: float) -> Vector2i:
	var ahead := m.cell + m.dir
	if grid.is_floor(ahead) and rng.randf() < straight_bias:
		return ahead
	var opts := grid.floor_neighbors(m.cell)
	var back := m.cell - m.dir
	if opts.size() > 1:
		opts.erase(back)
	if opts.is_empty():
		return m.cell
	return opts[rng.randi() % opts.size()]


# ------------------------------------------------------------------ モコチュリ
func _tick_moss(m: Monster, delta: float) -> void:
	if not _advance(m, delta):
		return
	if _try_attack_hero(m, true):
		return
	# goes straight until it hits a wall, then turns
	var next := m.cell + m.dir
	if not grid.is_floor(next):
		next = _random_step(m, 0.0)
		if next == m.cell:
			m.busy = 1.0
			m.hp -= 0.5
			_moss_check_life(m)
			return
	_start_move(m, next, Balance.MOSS_STEP_TIME)


func _moss_arrive(m: Monster) -> void:
	m.hp -= 1 + (1 if rng.randf() < 0.35 else 0)
	m.toggle = not m.toggle
	if m.toggle:
		var blocks := grid.block_neighbors(m.cell)
		blocks.shuffle()
		if m.nutrient <= 1:
			for b in blocks:
				if grid.get_nutrient(b) > 0:
					grid.add_nutrient(b, -1)
					m.nutrient += 1
					m.hp = minf(m.max_hp, m.hp + Balance.MOSS_ABSORB_HEAL)
					m.anim_request = "absorb"
					m.busy = Balance.MOSS_ABSORB_BUSY
					nutrient_flow.emit(b, m, true)
					break
		else:
			for b in blocks:
				if grid.add_nutrient(b, 1) > 0:
					m.nutrient -= 1
					m.anim_request = "absorb"
					m.busy = Balance.MOSS_ABSORB_BUSY
					nutrient_flow.emit(b, m, false)
					break
	_moss_check_life(m)


func _moss_check_life(m: Monster) -> void:
	if m.nutrient >= 2 and m.hp <= 2:
		_evolve(m, Monster.BUD)
	elif m.hp <= 0:
		kill(m, "starve")


# ------------------------------------------------------------------ ツボミ / モコバナ
func _absorb_area(m: Monster, cap: int) -> void:
	if m.nutrient >= cap:
		return
	var best := Vector2i(-1, -1)
	var bn := 0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var c := m.cell + Vector2i(dx, dy)
			var n := grid.get_nutrient(c) if grid.is_block(c) else 0
			if n > bn:
				bn = n
				best = c
	if bn > 0:
		grid.add_nutrient(best, -1)
		m.nutrient += 1
		m.anim_request = "absorb"
		nutrient_flow.emit(best, m, true)


func _tick_bud(m: Monster, delta: float) -> void:
	if m.busy > 0.0:
		m.busy -= delta
		return
	if m.stage_t > Balance.BUD_ATTACK_DELAY and _try_attack_hero(m, false):
		return
	m.timer += delta
	if m.timer >= Balance.BUD_ABSORB_INTERVAL:
		m.timer = 0.0
		_absorb_area(m, Balance.BUD_TARGET)
		if m.nutrient >= Balance.BUD_TARGET:
			_evolve(m, Monster.FLOWER)


func _tick_flower(m: Monster, delta: float) -> void:
	if m.busy > 0.0:
		m.busy -= delta
		if m.busy <= 0.0 and m.timer < 0.0:
			_flower_bloom(m)
		return
	if _try_attack_hero(m, false):
		return
	m.timer += delta
	if fmod(m.age, Balance.BUD_ABSORB_INTERVAL) < delta:
		_absorb_area(m, Balance.FLOWER_MAX_NUTRIENT)
	if m.age >= Balance.FLOWER_LIFE:
		m.anim_request = "spawn_child"
		m.busy = 0.9
		m.timer = -1.0  # marks "bloom when busy ends"


func _flower_bloom(m: Monster) -> void:
	var children := mini(Balance.FLOWER_CHILDREN + moss_level, maxi(1, m.nutrient))
	var cells: Array[Vector2i] = [m.cell]
	cells.append_array(grid.floor_neighbors(m.cell))
	var room := Balance.MAX_MOSS - count(Monster.Kind.MOSS) + 1
	children = mini(children, room)
	var pool := m.nutrient
	for i in children:
		var share := pool / (children - i)
		pool -= share
		_pending_spawns.append([Monster.Kind.MOSS, Monster.MOSS, cells[i % cells.size()], share, "birth"])
	m.nutrient = pool
	kill(m, "bloom")


# ------------------------------------------------------------------ ザクザクムシ
func _metabolism(m: Monster, delta: float, rate: float) -> void:
	m.meta_timer += delta * rate
	while m.meta_timer >= Balance.BUG_METABOLISM:
		m.meta_timer -= Balance.BUG_METABOLISM
		m.hp -= 1


func _find_prey(m: Monster) -> Monster:
	var best: Monster = null
	var bd := 999
	for o in monsters:
		if not o.alive or not o.is_prey():
			continue
		var d := absi(o.cell.x - m.cell.x) + absi(o.cell.y - m.cell.y)
		if d < bd and d <= Balance.BUG_SIGHT:
			bd = d
			best = o
	return best


func _try_eat(m: Monster) -> bool:
	var prey := _find_prey(m)
	if prey == null:
		return false
	var d := prey.cell - m.cell
	if absi(d.x) + absi(d.y) <= 1 and not prey.is_moving():
		if d != Vector2i.ZERO:
			m.dir = d
		m.anim_request = "eat"
		m.busy = 1.0
		m.hp = minf(m.max_hp, m.hp + Balance.EAT_HEAL + prey.nutrient * 2)
		m.nutrient += prey.nutrient
		ate.emit(m, prey)
		kill(prey, "eaten")
		return true
	var path := grid.find_path(m.cell, prey.cell)
	if path.is_empty():
		return false
	_start_move(m, path[0], _bug_step(m))
	return true


func _bug_step(m: Monster) -> float:
	var t := Balance.LARVA_STEP_TIME if m.stage == Monster.LARVA else Balance.ADULT_STEP_TIME
	return t / (1.0 + 0.1 * bug_level)


func _tick_larva(m: Monster, delta: float) -> void:
	_metabolism(m, delta, 1.0)
	if m.hp <= 0:
		kill(m, "starve")
		return
	if not _advance(m, delta):
		return
	if m.hp >= Balance.LARVA_PUPATE * _bug_mult():
		_evolve(m, Monster.PUPA)
		return
	if _try_attack_hero(m, false):
		return
	if m.hp <= Balance.LARVA_HUNGRY * _bug_mult() and _try_eat(m):
		return
	var next := _random_step(m, 0.55)
	if next == m.cell:
		m.busy = 0.8
		return
	_start_move(m, next, _bug_step(m))


func _tick_pupa(m: Monster, delta: float) -> void:
	if m.busy > 0.0:
		m.busy -= delta
		if m.busy <= 0.0 and m.timer < 0.0:
			_evolve(m, Monster.ADULT)
			m.anim_request = "spawn"
		return
	m.timer += delta * (1.0 + 0.15 * bug_level)
	if m.timer >= Balance.PUPA_TIME:
		m.anim_request = "hatch"
		m.busy = 1.3
		m.timer = -1.0


func _tick_adult(m: Monster, delta: float) -> void:
	_metabolism(m, delta, 3.0 if m.age > Balance.ADULT_LIFE else 0.8)
	m.lay_cooldown = maxf(0.0, m.lay_cooldown - delta)
	if m.hp <= 0:
		kill(m, "old" if m.age > Balance.ADULT_LIFE else "starve")
		return
	if m.busy > 0.0:
		m.busy -= delta
		if m.busy <= 0.0 and m.timer < 0.0:
			m.timer = 0.0
			_lay(m)
		return
	if not _advance(m, delta):
		return
	if _try_attack_hero(m, false):
		return
	# chase the hero when close
	var hc = _hero_cell()
	if hc != null:
		var d: Vector2i = hc - m.cell
		if absi(d.x) + absi(d.y) <= Balance.ADULT_AGGRO_RANGE:
			var path := grid.find_path(m.cell, hc)
			if not path.is_empty():
				_start_move(m, path[0], _bug_step(m))
				return
	if m.nutrient >= Balance.ADULT_LAY_NUTRIENT and m.hp >= Balance.ADULT_LAY_HP and m.lay_cooldown <= 0.0 and count(Monster.Kind.BUG) < Balance.MAX_BUGS:
		m.anim_request = "lay_egg"
		m.busy = 1.5
		m.timer = -1.0
		m.lay_cooldown = Balance.ADULT_LAY_COOLDOWN
		return
	if m.hp <= Balance.ADULT_HUNGRY * _bug_mult() and _try_eat(m):
		return
	var next := _random_step(m, 0.6)
	if next == m.cell:
		m.busy = 0.6
		return
	_start_move(m, next, _bug_step(m))


func _lay(m: Monster) -> void:
	m.nutrient -= Balance.ADULT_LAY_NUTRIENT
	m.hp -= Balance.ADULT_LAY_COST_HP
	var c := m.cell
	var n := grid.floor_neighbors(m.cell)
	if not n.is_empty():
		c = n[rng.randi() % n.size()]
	_pending_spawns.append([Monster.Kind.BUG, Monster.LARVA, c, Balance.ADULT_LAY_NUTRIENT, "birth"])


# ------------------------------------------------------------------ persistence
func to_array() -> Array:
	var out := []
	for m in monsters:
		if m.alive:
			out.append(m.to_dict())
	return out


func load_array(arr: Array) -> void:
	for d in arr:
		var m := Monster.from_dict(d)
		m.id = _next_id
		_next_id += 1
		m.jitter = Vector2(rng.randf_range(-0.16, 0.16), rng.randf_range(-0.16, 0.16))
		monsters.append(m)
		spawned.emit(m, "load")
