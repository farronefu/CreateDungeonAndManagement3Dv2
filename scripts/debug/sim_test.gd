extends SceneTree
## Headless ecosystem soak test:
##   godot --headless -s res://scripts/debug/sim_test.gd -- [seconds] [digs]
## Digs like a player during the build phase and prints population / nutrient conservation.

class FakeHero:
	extends Node
	var cell := Vector2i(-99, -99)
	var hits := 0
	func is_targetable() -> bool:
		return false
	func take_damage(d: int, _m) -> void:
		hits += d


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seconds := float(args[0]) if args.size() > 0 else 400.0
	var digs := int(args[1]) if args.size() > 1 else 90
	for seed_value in [11, 22, 33]:
		_run(seed_value, seconds, digs)
	quit()


func _run(seed_value: int, seconds: float, digs: int) -> void:
	var grid := DungeonGrid.new()
	grid.generate(seed_value)
	var eco := Ecosystem.new(grid, seed_value)
	eco.hero = FakeHero.new()
	var start_total := grid.total_nutrient()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var dug := 0
	var t := 0.0
	var dt := 0.1
	var next_report := 0.0
	var births := {"moss": 0, "bug": 0}
	eco.spawned.connect(func(m: Monster, cause: String) -> void:
		if cause == "birth":
			births["moss" if m.kind == Monster.Kind.MOSS else "bug"] += 1)
	print("=== seed %d  nutrient %d ===" % [seed_value, start_total])
	while t < seconds:
		# dig during the first 150 s, spread over time, preferring nutrient-rich blocks
		if t < 150.0 and dug < digs and fmod(t, 150.0 / digs) < dt:
			var cands: Array[Vector2i] = []
			for y in grid.h:
				for x in grid.w:
					var c := Vector2i(x, y)
					if grid.can_dig(c):
						cands.append(c)
			if not cands.is_empty():
				cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return grid.get_nutrient(a) > grid.get_nutrient(b))
				var pick := cands[rng.randi() % mini(6, cands.size())]
				var n := grid.dig(pick)
				eco.spawn_from_dig(pick, n)
				dug += 1
		eco.tick(dt)
		t += dt
		if t >= next_report:
			next_report += 25.0
			var total := grid.total_nutrient() + eco.total_nutrient()
			print("t=%5.0f moss %2d bud %2d flower %2d | larva %2d pupa %2d adult %2d | dug %3d | nutrient %d%s" % [
				t, eco.count(0, 0), eco.count(0, 1), eco.count(0, 2), eco.count(1, 0), eco.count(1, 1), eco.count(1, 2), dug, total,
				"" if total == start_total else "  (!= %d)" % start_total])
	print("births: ", births)
