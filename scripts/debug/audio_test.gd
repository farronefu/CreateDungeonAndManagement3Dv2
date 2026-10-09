extends Node
## Integration checks for sound routing, without requiring the pending recordings.

var failures := 0
var sfx: Node
var game: Node


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("AUDIOTEST: " + label)


func _reset() -> void:
	sfx._last_play.clear()


func _heard(key: String) -> bool:
	return sfx._last_play.has(key)


func _run() -> void:
	sfx = get_tree().root.get_node("Sfx")
	game = get_parent()
	for i in 20:
		await get_tree().process_frame
	if not game._debug.has("audio_fallback"):
		for key in Sfx.FIXED_PITCH:
			_check(sfx._streams[key].resource_path == "res://assets/audio/se/" + key + ".wav", "installed recording: " + key)
	game.set_process(false)
	game.speed = 0.0
	var c: Vector2i = game.grid.entrance
	var moss: Monster = game.eco.spawn(Monster.Kind.MOSS, Monster.MOSS, c, 4, "birth")
	_reset()
	game.layer._process(0.0)
	_check(_heard("spawn_moss"), "moss birth")
	_reset()
	game.eco._evolve(moss, Monster.BUD)
	_check(_heard("grass_evolve") and not _heard("ui_confirm"), "grass evolution is separate from purchases")
	var bug: Monster = game.eco.spawn(Monster.Kind.BUG, Monster.LARVA, c, 10, "birth")
	_reset()
	game.layer._process(0.0)
	_check(_heard("spawn_bug"), "larva birth")
	_reset()
	game.eco._evolve(bug, Monster.PUPA)
	_check(not _heard("pillbug_evolve"), "curling is not adult emergence")
	_reset()
	game.eco._evolve(bug, Monster.ADULT)
	_check(_heard("pillbug_evolve") and not _heard("grass_evolve"), "adult emergence")
	game.hero.state = Hero.State.ACTIVE
	game.hero.cell = c
	bug.cooldown = 0.0
	_reset()
	_check(game.eco._try_attack_hero(bug, false) and not _heard("bee_attack"), "adult attack start is silent")
	game.hero.cell = c + Vector2i(3, 0)
	_reset()
	game.eco._land_hit(bug)
	_check(not _heard("bee_attack"), "adult miss is silent")
	game.hero.cell = c
	_reset()
	game.eco._land_hit(bug)
	_check(_heard("bee_attack") and not _heard("hero_hurt"), "adult contact without generic hero hurt")
	bug.hit_timer = -1.0
	_reset()
	_check(game.eco._try_eat(bug) and bug.eat_target != null and bug.eat_timer > 0.0, "feeding schedules a later contact")
	_check(not _heard("bee_attack"), "feeding start is silent")
	var prey: Monster = bug.eat_target
	var nutrient_before: int = game.grid.total_nutrient() + game.eco.total_nutrient()
	_reset()
	game.eco._land_eat(bug)
	_check(not prey.alive and _heard("bee_attack") and not _heard("eat"), "adult feeding contact uses adopted sound")
	_check(game.grid.total_nutrient() + game.eco.total_nutrient() == nutrient_before, "delayed feeding conserves nutrient")
	_reset()
	game.eco._land_eat(bug)
	_check(sfx._last_play.is_empty(), "feeding contact cannot repeat")
	var escaped_prey: Monster = game.eco.spawn(Monster.Kind.MOSS, Monster.MOSS, c + Vector2i(3, 0), 0, "load")
	bug.eat_target = escaped_prey
	_reset()
	game.eco._land_eat(bug)
	_check(escaped_prey.alive and sfx._last_play.is_empty(), "escaped feeding target is a silent miss")
	escaped_prey.alive = false
	bug.eat_target = escaped_prey
	_reset()
	game.eco._land_eat(bug)
	_check(sfx._last_play.is_empty(), "dead feeding target is silent")
	for stage in [Monster.MOSS, Monster.BUD, Monster.FLOWER]:
		var striker: Monster = game.eco.spawn(Monster.Kind.MOSS, stage, c, 0, "load")
		_reset()
		_check(game.eco._try_attack_hero(striker, false), "grass attack scheduled")
		_check(not _heard("moss_hit") and not _heard("tree_hit"), "grass attack start is silent")
		game.hero.cell = c + Vector2i(3, 0)
		game.eco._land_hit(striker)
		_check(not _heard("moss_hit") and not _heard("tree_hit"), "grass miss is silent")
		game.hero.cell = c
		_reset()
		game.eco._land_hit(striker)
		_check(_heard("moss_hit" if stage == Monster.MOSS else "tree_hit"), "grass contact stage %d" % stage)
		striker.hit_timer = -1.0
	game.hero.attack_cd = 0.0
	_reset()
	game.hero._attack(bug)
	_check(not _heard("hero_hit") and not _heard("hero_attack") and not _heard("swing"), "attack start is silent")
	_reset()
	var before_hit: float = bug.hp
	game.hero._apply_hit()
	_check(bug.hp < before_hit and _heard("hero_hit") and not _heard("hit"), "contact plays one hero hit cue with damage")
	_reset()
	game.hero._apply_hit()
	_check(not _heard("hero_hit"), "consumed hit cannot play twice")
	game.hero._pending_hit = bug
	bug.cell = c + Vector2i(3, 0)
	before_hit = bug.hp
	_reset()
	game.hero._apply_hit()
	_check(bug.hp == before_hit and not _heard("hero_hit"), "out-of-range swing is silent")
	bug.cell = c
	bug.alive = false
	game.hero._pending_hit = bug
	_reset()
	game.hero._apply_hit()
	_check(not _heard("hero_hit"), "dead target is silent")
	bug.alive = true
	bug.hp = bug.max_hp
	_reset()
	game._poke_monster(bug)
	_check(_heard("miss") and not _heard("hit"), "pickaxe against a monster")
	_reset()
	game._try_dig(Vector2i(-1, -1))
	_check(_heard("miss"), "digging unavailable")
	game.speed = 1.0
	_reset()
	game._try_dig(Vector2i(-1, -1))
	_check(_heard("miss"), "empty or invalid target")
	for species in [Monster.Kind.MOSS, Monster.Kind.BUG]:
		for stage in [0, 1, 2]:
			var victim: Monster = game.eco.spawn(species, stage, c, 10, "load")
			_reset()
			game.eco.kill(victim, "killed")
			var cue := ("moss_die" if stage == 0 else "tree_die") if species == Monster.Kind.MOSS else ("bee_die" if stage == 2 else "pillbug_die")
			_check(_heard(cue) and sfx._last_play.size() == 1, "single species death cue %d/%d" % [species, stage])
			_reset()
			game.eco.kill(victim, "killed")
			_check(sfx._last_play.is_empty(), "dead victim cannot play twice")
	var emerging: Monster = game.eco.spawn(Monster.Kind.BUG, Monster.ADULT, c, 10, "load")
	emerging.visual.play_evolution("bug_evolution")
	_reset()
	game.eco.kill(emerging, "killed")
	_check(_heard("pillbug_die"), "death during the curled emergence visual")
	_reset()
	game._step_speed(1)
	_check(not _heard("click"), "speed shortcut is not UI confirmation")
	_reset()
	game._focus_hero()
	_check(not _heard("click"), "camera shortcut is not UI confirmation")
	game._place_torch(c)
	_reset()
	game._break_torch(c)
	_check(_heard("torch_break") and not _heard("hit"), "torch wood break")
	Screens.upgrades_open = true   # the purchase sounds are still checked while the upgrades are closed to players
	game._show_result()
	get_tree().root.get_node("GameState").evolution_points = 10000
	game.screens._refresh_upgrades()
	_reset()
	var first: Button = game.screens._upgrade_rows["dig"][1]
	var second: Button = game.screens._upgrade_rows["moss"][1]
	sfx.reset_ui_selection()
	first.focus_entered.emit()
	first.mouse_entered.emit()
	_check(not _heard("ui_move"), "initial menu selection is silent")
	var next_before: int = sfx._next
	second.focus_entered.emit()
	second.mouse_entered.emit()
	_check(_heard("ui_move") and sfx._next == (next_before + 1) % sfx._players.size(), "focus and hover coalesce to one move")
	_reset()
	next_before = sfx._next
	first.pressed.emit()
	_check(_heard("ui_confirm") and not _heard("ui_move") and sfx._next == (next_before + 1) % sfx._players.size(), "single purchase confirmation")
	game.hud.ask("audio test", func(_answer: bool) -> void: pass)
	_reset()
	next_before = sfx._next
	game.hud.answer(true)
	_check(_heard("ui_confirm") and sfx._next == (next_before + 1) % sfx._players.size(), "one yes confirmation")
	_reset()
	game.hud.answer(false)
	_check(sfx._last_play.is_empty(), "closed dialog cannot confirm twice")
	_reset()
	game.maou.place(c)
	_check(_heard("ui_confirm") and not _heard("place"), "placement uses shared confirmation")
	for obsolete in ["hero_hurt", "monster_die", "hit", "place", "click", "upgrade", "evolve", "eat", "swing", "dig_fail"]:
		_check(not sfx._streams.has(obsolete), "obsolete definition removed: " + obsolete)
	for key in Sfx.FIXED_PITCH:
		_reset()
		sfx.play(key)
		_check(sfx._players[(sfx._next - 1 + sfx._players.size()) % sfx._players.size()].pitch_scale == 1.0, "authored pitch: " + key)
	# A result coroutine must not start music after the player has left that screen.
	sfx.play_bgm("")
	game._victory_audio_end = Time.get_ticks_msec() + 100
	game._play_result_music()
	game.phase = game.Phase.DEFEAT
	await get_tree().create_timer(0.15).timeout
	_check(sfx._bgm_name == "", "cancel delayed result music on defeat")
	# Verify each authored screen/phase track, loop and gain after the fade completes.
	for track in ["title", "build", "battle", "captured", "result_victory"]:
		sfx.play_bgm(track)
		await get_tree().create_timer(1.1).timeout
		_check(sfx._bgm.stream.resource_path == "res://assets/audio/bgm/" + track + ".ogg" and sfx._bgm.playing, "installed BGM: " + track)
		_check(sfx._bgm.stream.loop, "BGM loops: " + track)
		_check(is_equal_approx(sfx._bgm.volume_db, -21.0 if track == "result_victory" else -15.0), "BGM gain: " + track)
	sfx.play_bgm("")
	game.phase = game.Phase.RESULT
	game._victory_audio_end = Time.get_ticks_msec() + 200
	game._play_result_music()
	await get_tree().create_timer(0.1).timeout
	_check(sfx._bgm_name == "", "result music waits for victory cue")
	await get_tree().create_timer(0.15).timeout
	_check(sfx._bgm_name == "result_victory", "result music starts after victory cue")
	print("AUDIOTEST ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	var tree := get_tree()
	if sfx._bgm_tween:
		sfx._bgm_tween.kill()
	sfx._bgm.stop()
	sfx._bgm.stream = null
	for player in sfx._players:
		player.stop()
		player.stream = null
	await tree.create_timer(0.1).timeout
	sfx.reset_ui_selection()
	reparent(tree.root)  # Keep this test coroutine alive while its game scene is freed.
	game.queue_free()
	await tree.process_frame
	await tree.process_frame
	tree.quit(0 if failures == 0 else 1)
