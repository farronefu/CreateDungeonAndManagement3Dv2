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
	_check(_heard("grass_evolve") and not _heard("upgrade"), "grass evolution is separate from purchases")
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
	_check(game.eco._try_attack_hero(bug, false) and _heard("bee_attack"), "adult attack starts its own cue")
	_reset()
	game.layer._on_ate(bug, moss)
	_check(not _heard("eat") and not _heard("bee_attack"), "feeding does not play the reused attack recording")
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
	for stage in [Monster.LARVA, Monster.PUPA, Monster.ADULT]:
		var victim: Monster = game.eco.spawn(Monster.Kind.BUG, stage, c, 10, "load")
		_reset()
		game.eco.kill(victim, "killed")
		_check(_heard("pillbug_die") == (stage != Monster.ADULT), "death stage %d" % stage)
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
	game._show_result()
	get_tree().root.get_node("GameState").evolution_points = 10000
	_reset()
	game.screens._buy("dig")
	_check(_heard("upgrade") and not _heard("grass_evolve"), "purchase cue")
	for key in ["hero_hit", "pillbug_die", "pillbug_evolve", "grass_evolve", "miss", "upgrade", "bee_attack"]:
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
	get_tree().quit(0 if failures == 0 else 1)
