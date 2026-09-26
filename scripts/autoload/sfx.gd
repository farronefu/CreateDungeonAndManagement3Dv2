extends Node
## Procedurally synthesised sound effects and background music (no audio assets needed).
## Replace any entry in `_streams` with a loaded AudioStream to use real recordings.

const RATE := 22050

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _bgm: AudioStreamPlayer
var _bgm_name := ""
var _last_play := {}
var muted := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.volume_db = -6.0
		add_child(p)
		_players.append(p)
	_bgm = AudioStreamPlayer.new()
	_bgm.volume_db = -15.0
	add_child(_bgm)
	_build_sfx()


func play(sound: String, _pos: Vector3 = Vector3.ZERO) -> void:
	if muted or not _streams.has(sound):
		return
	# avoid machine-gun stacking of the same sound
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(sound, -1000)) < 45:
		return
	_last_play[sound] = now
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sound]
	p.pitch_scale = randf_range(0.94, 1.06)
	p.play()


func play_bgm(bgm: String) -> void:
	if bgm == _bgm_name:
		return
	_bgm_name = bgm
	if bgm == "":
		_bgm.stop()
		return
	var key := "bgm_" + bgm
	if not _streams.has(key):
		_streams[key] = _make_bgm(bgm)
	_bgm.stream = _streams[key]
	_bgm.play()


# ------------------------------------------------------------------ synthesis helpers
func _wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * RATE))
	return b


func _osc(kind: int, phase: float) -> float:
	match kind:
		0:
			return sin(phase * TAU)
		1:
			return 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
		2:
			return 1.0 - 4.0 * absf(fmod(phase, 1.0) - 0.5)
		_:
			return randf() * 2.0 - 1.0


## Adds a tone with a linear frequency sweep and exponential decay.
func _tone(b: PackedFloat32Array, start: float, dur: float, f0: float, f1: float, kind: int, vol: float, decay: float = 4.0, attack: float = 0.004) -> void:
	var s0 := int(start * RATE)
	var n := int(dur * RATE)
	var phase := 0.0
	for i in n:
		if s0 + i >= b.size():
			break
		var t := float(i) / RATE
		var f := lerpf(f0, f1, t / dur)
		phase += f / RATE
		var env := minf(1.0, t / attack) * exp(-t * decay)
		b[s0 + i] += _osc(kind, phase) * vol * env


func _noise(b: PackedFloat32Array, start: float, dur: float, vol: float, decay: float, smooth: float = 0.0) -> void:
	var s0 := int(start * RATE)
	var n := int(dur * RATE)
	var prev := 0.0
	for i in n:
		if s0 + i >= b.size():
			break
		var t := float(i) / RATE
		var v := randf() * 2.0 - 1.0
		prev = lerpf(v, prev, smooth)
		b[s0 + i] += prev * vol * exp(-t * decay)


func _build_sfx() -> void:
	var b: PackedFloat32Array
	b = _buf(0.3)
	_noise(b, 0, 0.3, 0.7, 14.0, 0.7)
	_tone(b, 0, 0.25, 140, 55, 0, 0.8, 12.0)
	_streams["dig"] = _wav(b)
	b = _buf(0.14)
	_tone(b, 0, 0.14, 110, 90, 1, 0.25, 10.0)
	_streams["dig_fail"] = _wav(b)
	b = _buf(0.25)
	_tone(b, 0, 0.22, 380, 900, 0, 0.5, 10.0)
	_tone(b, 0.05, 0.18, 600, 1200, 0, 0.3, 14.0)
	_streams["spawn_moss"] = _wav(b)
	b = _buf(0.3)
	for k in 5:
		_tone(b, k * 0.05, 0.04, 900 + k * 60, 700, 1, 0.18, 30.0)
	_tone(b, 0, 0.2, 200, 160, 2, 0.4, 8.0)
	_streams["spawn_bug"] = _wav(b)
	b = _buf(0.45)
	for k in 3:
		_tone(b, k * 0.08, 0.3, [523.0, 659.0, 784.0][k], [523.0, 659.0, 784.0][k], 2, 0.35, 6.0)
	_streams["evolve"] = _wav(b)
	b = _buf(0.15)
	_noise(b, 0, 0.1, 0.8, 40.0, 0.2)
	_tone(b, 0, 0.12, 240, 90, 0, 0.7, 20.0)
	_streams["hit"] = _wav(b)
	b = _buf(0.2)
	_tone(b, 0, 0.18, 330, 150, 1, 0.3, 10.0)
	_noise(b, 0, 0.08, 0.4, 30.0, 0.3)
	_streams["hero_hurt"] = _wav(b)
	b = _buf(0.35)
	_tone(b, 0, 0.35, 500, 120, 2, 0.45, 7.0)
	_streams["monster_die"] = _wav(b)
	b = _buf(0.3)
	_noise(b, 0, 0.1, 0.6, 30.0, 0.5)
	_noise(b, 0.13, 0.1, 0.6, 30.0, 0.5)
	_streams["eat"] = _wav(b)
	b = _buf(0.2)
	_noise(b, 0, 0.2, 0.5, 10.0, 0.85)
	_streams["swing"] = _wav(b)
	b = _buf(0.6)
	for k in 6:
		_tone(b, k * 0.06, 0.3, 700 + k * 150, 800 + k * 160, 0, 0.18, 8.0)
	_streams["heal"] = _wav(b)
	b = _buf(0.3)
	_tone(b, 0, 0.12, 392, 392, 1, 0.2, 10.0)
	_tone(b, 0.12, 0.15, 294, 294, 1, 0.2, 10.0)
	_streams["grab"] = _wav(b)
	b = _buf(0.7)
	_tone(b, 0, 0.5, 90, 45, 0, 0.9, 6.0)
	_tone(b, 0.05, 0.6, 880, 880, 2, 0.2, 5.0)
	_streams["place"] = _wav(b)
	b = _buf(0.7)
	_noise(b, 0, 0.5, 0.5, 5.0, 0.9)
	_tone(b, 0.12, 0.5, 110, 70, 1, 0.3, 6.0)
	_streams["cutin"] = _wav(b)
	b = _buf(1.0)
	_tone(b, 0, 0.75, 210, 150, 1, 0.1, 2.0)
	_tone(b, 0.04, 0.7, 330, 250, 2, 0.08, 2.5)
	_noise(b, 0.72, 0.25, 0.5, 16.0, 0.8)
	_tone(b, 0.72, 0.28, 72, 45, 0, 0.6, 11.0)
	_streams["door"] = _wav(b)
	b = _buf(0.05)
	_tone(b, 0, 0.05, 1200, 900, 2, 0.3, 60.0)
	_streams["click"] = _wav(b)
	b = _buf(1.8)
	var fan := [523.0, 659.0, 784.0, 1047.0]
	for k in 4:
		_tone(b, k * 0.14, 0.5 if k < 3 else 1.2, fan[k], fan[k], 1, 0.16, 3.0)
		_tone(b, k * 0.14, 0.5 if k < 3 else 1.2, fan[k] * 0.5, fan[k] * 0.5, 2, 0.25, 3.0)
	_streams["victory"] = _wav(b)
	b = _buf(1.8)
	var dn := [392.0, 370.0, 349.0, 262.0]
	for k in 4:
		_tone(b, k * 0.3, 0.6 if k < 3 else 1.1, dn[k], dn[k], 2, 0.3, 2.5)
	_streams["defeat"] = _wav(b)


# ------------------------------------------------------------------ music
func _make_bgm(kind: String) -> AudioStreamWAV:
	var bpm := 92.0 if kind == "build" else 132.0
	var beat := 60.0 / bpm
	var bars := 8
	var total := beat * 4.0 * bars
	var b := _buf(total)
	# A minor pentatonic-ish progression
	var roots := [220.0, 174.6, 196.0, 164.8] if kind == "build" else [220.0, 233.1, 196.0, 207.7]
	var scale := [0, 3, 5, 7, 10, 12, 15]
	var rng := RandomNumberGenerator.new()
	rng.seed = 42 if kind == "build" else 77
	for bar in bars:
		var root: float = roots[bar % roots.size()]
		var t0 := bar * beat * 4.0
		# bass
		for q in 4:
			var bf := root * 0.5 if kind == "build" else root * 0.5 * (1.0 if q % 2 == 0 else 1.5)
			_tone(b, t0 + q * beat, beat * 0.9, bf, bf, 2, 0.32, 2.5 if kind == "build" else 5.0)
		# pad / arpeggio
		var steps := 8 if kind == "build" else 16
		for s in steps:
			var st := t0 + s * beat * 4.0 / steps
			var chord := [0, 3, 7, 12]
			var f := root * pow(2.0, chord[s % 4] / 12.0)
			_tone(b, st, beat * 0.5, f, f, 0 if kind == "build" else 1, 0.06 if kind == "build" else 0.035, 6.0)
		# melody
		var notes := 4 if kind == "build" else 8
		for n in notes:
			if rng.randf() < 0.25:
				continue
			var deg: int = scale[rng.randi() % scale.size()]
			var f2 := root * 2.0 * pow(2.0, deg / 12.0)
			_tone(b, t0 + n * beat * 4.0 / notes, beat * (1.6 if kind == "build" else 0.45), f2, f2, 2, 0.12, 2.0 if kind == "build" else 5.0, 0.02)
		# percussion
		if kind != "build":
			for q in 8:
				_noise(b, t0 + q * beat * 0.5, 0.05, 0.12 if q % 2 == 1 else 0.05, 60.0, 0.1)
			for q in 4:
				if q % 2 == 0:
					_tone(b, t0 + q * beat, 0.15, 120, 45, 0, 0.5, 18.0)
		else:
			_noise(b, t0, 0.3, 0.03, 8.0, 0.95)
	# soft limiter
	for i in b.size():
		b[i] = tanh(b[i] * 1.2) * 0.8
	return _wav(b, true)
