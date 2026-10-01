extends SceneTree
## Where does the nutrient go?  godot --headless -s res://scripts/debug/ecology_probe.gd -- [seconds]
## For three seeds, digs like
## sim_test and reports (mean over seeds) population, bugs ever spawned, soil >= 10 cells,
## and how the conserved nutrient is split between soil and the monsters' bodies.

class FakeHero:
	extends Node
	var cell := Vector2i(-99, -99)
	func is_targetable() -> bool:
		return false
	func take_damage(_d: int, _m) -> void:
		pass


func _init() -> void:
	var seconds := float(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 450.0
	for _once in 1:
		var acc := {}
		for seed_value in [11, 22, 33]:
			var r := _run(seed_value, seconds)
			for k in r:
				acc[k] = (acc[k] as Array) + [r[k]] if acc.has(k) else [r[k]]
		print("--- take %d / give %d ---" % [Balance.MOSS_TAKE, Balance.MOSS_GIVE])
		for k in acc:
			var a: Array = acc[k]
			var sum := 0.0
			for v in a:
				sum += float(v)
			print("  %-34s %s   mean %.1f" % [k, a, sum / a.size()])
	quit()


func _run(seed_value: int, seconds: float) -> Dictionary:
	var grid := DungeonGrid.new()
	grid.generate(seed_value)
	var eco := Ecosystem.new(grid, seed_value)
	eco.hero = FakeHero.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := {}
	var bugs_spawned := [0]
	var moss_spawned := [0]
	eco.spawned.connect(func(m: Monster, _c: String) -> void:
		if m.kind == Monster.Kind.BUG:
			bugs_spawned[0] += 1
		else:
			moss_spawned[0] += 1)
	var dug := 0
	var t := 0.0
	var dt := 0.1
	var peak_moss := 0
	var marks := [150.0, 300.0, 450.0]
	while t < seconds:
		if t < 150.0 and dug < 90 and fmod(t, 150.0 / 90.0) < dt:
			var cands: Array[Vector2i] = []
			for y in grid.h:
				for x in grid.w:
					if grid.can_dig(Vector2i(x, y)):
						cands.append(Vector2i(x, y))
			if not cands.is_empty():
				cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return grid.get_nutrient(a) > grid.get_nutrient(b))
				var pick: Vector2i = cands[rng.randi() % mini(6, cands.size())]
				eco.spawn_from_dig(pick, grid.dig(pick))
				dug += 1
		eco.tick(dt)
		t += dt
		peak_moss = maxi(peak_moss, eco.count(0, 0))
		if not marks.is_empty() and t >= marks[0]:
			var tag := "t%03d" % int(marks[0])
			marks.pop_front()
			var rich := 0
			var rich_nut := 0
			var soil_nut := 0
			for i in grid.nutrient.size():
				if grid.types[i] == DungeonGrid.BLOCK:
					soil_nut += grid.nutrient[i]
					if grid.nutrient[i] >= 10:
						rich += 1
						rich_nut += grid.nutrient[i]
			var body := {0: 0, 1: 0, 2: 0, 3: 0}
			for m in eco.monsters:
				if m.alive:
					var key: int = m.stage if m.kind == Monster.Kind.MOSS else 3
					body[key] += m.nutrient
			var top := 0
			for i in grid.nutrient.size():
				if grid.types[i] == DungeonGrid.BLOCK:
					top = maxi(top, grid.nutrient[i])
			out[tag + " max soil nutrient"] = top
			out[tag + " soil>=10 cells"] = rich
			out[tag + " nutrient: soil total"] = soil_nut
			out[tag + " nutrient: in moss/bud/flower/bug"] = "%d/%d/%d/%d" % [body[0], body[1], body[2], body[3]]
			out[tag + " moss/bud/flower alive"] = "%d/%d/%d" % [eco.count(0, 0), eco.count(0, 1), eco.count(0, 2)]
	out["moss spawned (all)"] = moss_spawned[0]
	out["bugs spawned (all)"] = bugs_spawned[0]
	out["peak moss"] = peak_moss
	return out
