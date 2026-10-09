extends SceneTree
## ヴァレン (stage 2) and the weakened ゆうた (stage 1), measured in the game's own simulation:
##   godot --headless -s res://scripts/debug/valen_test.gd -- --autostart --seed=3 --stage=1
## - one ザクザクムシ larva never beats ヴァレン, two usually do (fresh larvae and well-fed ones, 24 fights
##   each: he must win every fight against one and at most 2 in 5 against two; a larva does 1-3 damage
##   through his armour, so the line between "one" and "two" cannot be sharper than that)
## - with three or more monsters in the four cells around him he uses the special attack: it hits
##   them all at once and costs a third of his MP; he never heals
## - stage 1 ゆうた has no MP and does not heal; stage 3 sends both, ゆうた healing again
const ACTIVE := 3   # Hero.State.ACTIVE (the Hero class cannot be named here: it uses autoloads)
var failures := 0
var checks := 0
var game
var hero
var eco
var grid


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAILED: ", label)


func _init() -> void:
	call_deferred("run")


## A floor cell with all four neighbours open (the middle of the starter room).
func _arena() -> Vector2i:
	for y in grid.h:
		for x in grid.w:
			var c := Vector2i(x, y)
			if grid.is_floor(c) and grid.floor_neighbors(c).size() == 4 and c != grid.entrance:
				return c
	return grid.entrance


func _reset(h, c: Vector2i) -> void:
	for m in eco.monsters:
		m.alive = false
	eco.monsters.clear()
	h.state = ACTIVE
	h.cell = c
	h.from_cell = c
	h.move_t = 1.0
	h.hp = h.max_hp
	h.mp = h.max_mp
	h.busy = 0.0
	h.attack_cd = 0.0
	h._hit_timer = -1.0
	h._special_timer = -1.0
	h.known = PackedByteArray()
	h.visited.fill(1)   # nothing left to explore: he stays and fights
	h.carrying = false
	h.knows_maou = false
	game.maou.placed = false   # (he would wander off, find the 魔王 and walk out with him)


## Fights until the hero or every monster is dead. Returns the hero's HP left (0 = he lost).
func _fight(h, t_max: float = 180.0) -> float:
	var t := 0.0
	while t < t_max and h.state == ACTIVE and not eco.monsters.is_empty():
		eco.tick(0.05)
		h.tick(0.05)
		t += 0.05
	return maxf(0.0, h.hp) if h.state == ACTIVE else 0.0


func _larvae(c: Vector2i, n: int, hp: float) -> void:
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for i in n:
		var m: Monster = eco.spawn(Monster.Kind.BUG, Monster.LARVA, c + dirs[i], 0, "load")
		m.hp = hp


func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	hero = game.hero
	eco = game.eco
	grid = game.grid
	var p = hero.profile
	check(game.heroes.size() == 1 and p.display_name == "ヴァレン", "stage 2 sends ヴァレン alone")
	check(float(game.stage["build_time"]) == 60.0, "stage 2 arrival time")
	check(not hero.can_heal and hero.max_mp == p.max_mp and p.special_cost * 3 == p.max_mp, "no healing; MP for three special attacks")
	for clip in [p.anim_idle, p.anim_walk, p.anim_attack, p.anim_death, p.anim_joy, p.anim_look, p.anim_special]:
		check(hero.actor.has_anim(clip), "clip " + clip)
	var c: Vector2i = _arena()

	# --- one larva loses, two win (fresh: 36 HP, well fed: just under pupating) ---
	var report := {}
	for hp in [float(Balance.LARVA_HP), float(Balance.LARVA_PUPATE - 1)]:
		for n in [1, 2]:
			var wins := 0
			var left := 0.0
			var trials := 24
			for k in trials:
				eco.rng.seed = 100 + k
				hero.rng.seed = 200 + k
				_reset(hero, c)
				_larvae(c, n, hp)
				var r: float = _fight(hero)
				if r > 0.0:
					wins += 1
					left += r
			report["%d larva hp %d" % [n, int(hp)]] = "hero wins %d/%d, HP left %.0f/%d" % [wins, trials, left / maxf(1.0, wins), int(hero.max_hp)]
			if n == 1:
				check(wins == trials, "one larva (HP %d) does not beat him (%d of %d)" % [int(hp), wins, trials])
			else:
				check(wins <= trials * 2 / 5, "two larvae (HP %d) usually beat him (%d of %d)" % [int(hp), trials - wins, trials])
	print("DUELS ", report)

	# --- the special attack ---
	_reset(hero, c)
	var ms: Array[Monster] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)]:
		var m: Monster = eco.spawn(Monster.Kind.BUG, Monster.LARVA, c + d, 0, "load")
		m.hp = 60.0
		m.max_hp = 200.0
		m.atk = 0.0   # they only stand there
		ms.append(m)
	hero._decide()
	check(hero.specials == 1 and hero.mp == hero.max_mp - p.special_cost and hero.actor.current == p.anim_special, "three around him: special attack, MP spent")
	var t := 0.0
	while t < 1.2:
		hero.tick(0.05)
		t += 0.05
	var hit := 0
	for m in ms:
		if m.hp < 60.0:
			hit += 1
	check(hit == 3, "the sweep hits all three at once (%d)" % hit)
	_reset(hero, c)
	for d in [Vector2i(1, 0), Vector2i(-1, 0)]:
		eco.spawn(Monster.Kind.BUG, Monster.LARVA, c + d, 0, "load").atk = 0.0
	var before: int = hero.specials
	hero._decide()
	check(hero.specials == before and hero.actor.current == p.anim_attack, "only two around him: ordinary attack")
	_reset(hero, c)
	hero.hp = 5.0
	hero._decide()
	check(hero.hp == 5.0, "he never heals")

	# --- the stage table ---
	var s1: Dictionary = StageDefs.get_stage(0)
	var s3: Dictionary = StageDefs.get_stage(2)
	check(float(s1["build_time"]) == 45.0 and s1["heroes"].size() == 1 and s1["heroes"][0]["heal"] == false, "stage 1: ゆうた alone after 45 s, no healing")
	check(s3["heroes"].size() == 2 and s3["heroes"][0]["heal"] == true, "stage 3: both, ゆうた heals")
	print("VALENTEST ", "PASS" if failures == 0 else "FAIL", " checks=%d failures=%d" % [checks, failures])
	quit(failures)
