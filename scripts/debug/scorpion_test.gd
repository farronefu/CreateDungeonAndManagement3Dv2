extends SceneTree
## Headless check of the scorpion's life cycle:
##   godot --headless -s res://scripts/debug/scorpion_test.gd
## cracked soil -> scorpion, three meals -> egg block, the egg block's nutrient is sealed,
## it hatches when dug and by itself, and nutrient is conserved throughout.

class FakeHero:
	extends Node
	var cell := Vector2i(-99, -99)
	func is_targetable() -> bool:
		return false
	func take_damage(_d: int, _m) -> void:
		pass


var failures := 0


func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAILED: ", label)


func _init() -> void:
	var grid := DungeonGrid.new(14, 9)
	for y in grid.h:
		for x in grid.w:
			var border := x == 0 or y == 0 or x == grid.w - 1 or y == grid.h - 1
			grid.types[grid.idx(Vector2i(x, y))] = DungeonGrid.BEDROCK if border else DungeonGrid.BLOCK
	for x in range(2, 12):
		grid.types[grid.idx(Vector2i(x, 4))] = DungeonGrid.FLOOR
	grid.set_nutrient(Vector2i(6, 3), Balance.SCORPION_SPAWN_MIN)
	grid.set_nutrient(Vector2i(8, 3), Balance.SCORPION_SPAWN_MIN - 1)
	var eco := Ecosystem.new(grid, 5)
	eco.hero = FakeHero.new()
	var total := func() -> int: return grid.total_nutrient() + eco.total_nutrient()
	var start: int = total.call()

	# --- what comes out of the soil ---
	var s := eco.spawn_from_dig(Vector2i(6, 3), grid.dig(Vector2i(6, 3)))
	check(s != null and s.kind == Monster.Kind.SCORPION, "cracked soil (13+) hatches a scorpion")
	var b := eco.spawn_from_dig(Vector2i(8, 3), grid.dig(Vector2i(8, 3)))
	check(b != null and b.kind == Monster.Kind.BUG, "dry soil (10-12) still hatches the pill bug")
	check(s.max_hp == Balance.SCORPION_HP_MAX and s.atk == Balance.SCORPION_ATK, "scorpion stats")

	# --- three meals, then an egg ---
	var laid := []
	eco.egg_laid.connect(func(c: Vector2i, _m: Monster) -> void: laid.append(c))
	var eaten := [0]
	var overlapped := [0]
	eco.ate.connect(func(pred: Monster, prey: Monster) -> void:
		if pred == s:
			eaten[0] += 1
			if pred.cell == prey.cell:
				overlapped[0] += 1)
	var t := 0.0
	while t < 400.0 and laid.is_empty():
		if eco.count(Monster.Kind.BUG) == 0:
			# pill bugs starve without moss: keep one in reach (no nutrient, so the totals stay put)
			eco.spawn(Monster.Kind.BUG, [Monster.LARVA, Monster.PUPA, Monster.ADULT][eaten[0] % 3], Vector2i(3, 4), 0, "load")
		eco.tick(0.1)
		t += 0.1
	check(eaten[0] == Balance.SCORPION_LAY_MEALS, "lays after exactly %d meals (ate %d)" % [Balance.SCORPION_LAY_MEALS, eaten[0]])
	check(overlapped[0] == 0, "it eats from the next cell, never on top of its prey")
	check(laid.size() == 1, "one egg block laid within 400 s (t=%.0f)" % t)
	if laid.is_empty():
		print("SCORPIONTEST FAIL failures=", failures + 1)
		quit(1)
		return
	var egg: Vector2i = laid[0]
	var inside := grid.get_nutrient(egg)
	check(grid.is_egg(egg) and not grid.is_block(egg) and not grid.is_floor(egg), "the stung block is an egg block (still a wall)")
	check(inside >= 1 and inside <= Balance.SCORPION_EGG_NUTRIENT + Balance.MAX_NUTRIENT, "nutrient sealed in the egg: %d" % inside)
	check(s.meals == 0 and s.lay_cooldown > 0.0, "the mother starts over")
	check(total.call() == start, "nutrient conserved after laying (%d vs %d)" % [total.call(), start])

	# --- the egg block's nutrient is sealed ---
	check(grid.add_nutrient(egg, 3) == 0 and grid.add_nutrient(egg, -3) == 0, "nothing can be added to or taken from an egg block")
	check(not grid.block_neighbors(egg + Vector2i(0, 1)).has(egg), "moss does not see it as soil")
	eco._scatter_nutrient(egg + Vector2i(0, 1), 6)
	check(grid.get_nutrient(egg) == inside, "scattered nutrient does not enter it")
	check(grid.can_dig(egg), "the player can dig it")
	var again := DungeonGrid.from_dict(grid.to_dict())
	check(again.is_egg(egg) and again.eggs.has(egg) and again.get_nutrient(egg) == inside, "egg blocks survive save / load")
	# the 6 scattered above came from nowhere: account for them
	start += 6

	# --- hatching by itself ---
	var before := eco.count(Monster.Kind.SCORPION)
	grid.eggs[egg] = 0.25
	for i in 6:
		eco.tick(0.1)
	check(grid.is_floor(egg) and not grid.eggs.has(egg), "an egg left alone breaks open")
	check(eco.count(Monster.Kind.SCORPION) == before + 1, "and one young scorpion steps out")
	var young: Monster = null
	for m in eco.monsters:
		if m.kind == Monster.Kind.SCORPION and (young == null or m.id > young.id):
			young = m
	check(young != null and young.nutrient == inside, "carrying everything that was sealed in")
	check(total.call() == start, "nutrient conserved after hatching (%d vs %d)" % [total.call(), start])

	# --- hatching when dug ---
	var wall := Vector2i(10, 3)
	grid.set_nutrient(wall, 2)
	start += 2
	check(grid.make_egg(wall, 0, Balance.SCORPION_EGG_TIME), "make_egg on a soil block")
	var dug := eco.spawn_from_dig(wall, grid.dig(wall))
	check(dug != null and dug.kind == Monster.Kind.SCORPION and dug.nutrient == 2, "digging an egg block hatches it, however little is inside")
	check(total.call() == start, "nutrient conserved after digging (%d vs %d)" % [total.call(), start])
	print("SCORPIONTEST %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures else 0)
