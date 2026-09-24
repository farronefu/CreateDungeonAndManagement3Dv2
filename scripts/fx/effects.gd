class_name Effects
extends Node3D
## One-shot visual effects: dig debris, dust, nutrient motes, damage numbers, sparkles.

var _debris_mesh: BoxMesh
var _debris_mat: StandardMaterial3D
var _dot_mesh: SphereMesh
var _mote_mat: StandardMaterial3D
var _puff_mat: StandardMaterial3D


func _ready() -> void:
	_debris_mesh = BoxMesh.new()
	_debris_mesh.size = Vector3.ONE * 0.09
	_debris_mat = StandardMaterial3D.new()
	_debris_mat.vertex_color_use_as_albedo = true
	_debris_mat.roughness = 0.9
	_debris_mesh.material = _debris_mat
	_dot_mesh = SphereMesh.new()
	_dot_mesh.radius = 0.05
	_dot_mesh.height = 0.1
	_dot_mesh.radial_segments = 8
	_dot_mesh.rings = 4
	_mote_mat = StandardMaterial3D.new()
	_mote_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mote_mat.vertex_color_use_as_albedo = true
	_mote_mat.albedo_color = Color(1, 1, 1)
	_mote_mat.emission_enabled = true
	_mote_mat.emission = Color(0.6, 1.0, 0.3)
	_mote_mat.emission_energy_multiplier = 2.0
	_puff_mat = StandardMaterial3D.new()
	_puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_puff_mat.vertex_color_use_as_albedo = true
	_puff_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED


func _particles(pos: Vector3, amount: int, mesh: Mesh, colors: Gradient, speed: Vector2, lifetime: float, gravity: float, spread: float = 60.0, scale_range: Vector2 = Vector2(0.6, 1.3)) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = amount
	p.lifetime = lifetime
	p.mesh = mesh
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.gravity = Vector3(0, -gravity, 0)
	p.scale_amount_min = scale_range.x
	p.scale_amount_max = scale_range.y
	p.color_initial_ramp = colors
	p.angular_velocity_min = -360
	p.angular_velocity_max = 360
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.3, 0.3, 0.3)
	p.position = pos
	add_child(p)
	p.emitting = true
	get_tree().create_timer(lifetime + 0.5).timeout.connect(p.queue_free)
	return p


func debris(c: Vector2i, mossy: float) -> void:
	var g := Gradient.new()
	g.set_color(0, Color(0.42, 0.28, 0.16))
	g.set_color(1, Color(0.3, 0.45, 0.16).lerp(Color(0.55, 0.38, 0.22), 1.0 - mossy))
	var pos := DungeonGrid.cell_center(c, Balance.BLOCK_H * 0.5)
	_particles(pos, 26, _debris_mesh, g, Vector2(1.5, 3.4), 0.9, 9.0, 70.0)
	dust(pos, Color(0.7, 0.58, 0.44, 0.7))


func dust(pos: Vector3, color: Color, size: float = 1.0) -> void:
	for i in 6:
		var mi := MeshInstance3D.new()
		var q := SphereMesh.new()
		q.radius = 0.18 * size
		q.height = 0.36 * size
		q.radial_segments = 8
		q.rings = 4
		mi.mesh = q
		var mat := _puff_mat.duplicate() as StandardMaterial3D
		mat.albedo_color = color
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := i * TAU / 6.0
		mi.position = pos + Vector3(cos(a), 0, sin(a)) * 0.2
		add_child(mi)
		var tw := mi.create_tween().set_parallel(true)
		tw.tween_property(mi, "position", pos + Vector3(cos(a) * 0.6, 0.35 + randf() * 0.3, sin(a) * 0.6), 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(mi, "scale", Vector3.ONE * 1.8, 0.7)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.7)
		tw.chain().tween_callback(mi.queue_free)


## Glowing nutrient motes flying between a soil block and a monster.
func motes(from: Vector3, to: Vector3, color: Color = Color(0.6, 1.0, 0.35)) -> void:
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = _dot_mesh
		var mat := _mote_mat.duplicate() as StandardMaterial3D
		mat.albedo_color = color
		mat.emission = color
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = from
		mi.scale = Vector3.ONE * (0.6 + i * 0.2)
		add_child(mi)
		var mid := (from + to) * 0.5 + Vector3(randf_range(-0.2, 0.2), 0.45 + i * 0.1, randf_range(-0.2, 0.2))
		var tw := mi.create_tween()
		tw.tween_interval(i * 0.08)
		tw.tween_method(func(t: float) -> void:
			var a := from.lerp(mid, t)
			var b := mid.lerp(to, t)
			mi.position = a.lerp(b, t), 0.0, 1.0, 0.55).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(mi.queue_free)


func number(pos: Vector3, text: String, color: Color, big: bool = false) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 64 if big else 44
	l.pixel_size = 0.005
	l.outline_size = 12
	l.modulate = color
	l.outline_modulate = Color(0.05, 0.03, 0.02)
	l.position = pos + Vector3(randf_range(-0.1, 0.1), 0, 0)
	l.font = UiTheme.font(true)
	add_child(l)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", pos.y + 0.7, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.4).set_delay(0.55)
	tw.chain().tween_callback(l.queue_free)


func sparkle(pos: Vector3, color: Color, amount: int = 18) -> void:
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, color.lightened(0.5))
	var p := _particles(pos, amount, _dot_mesh, g, Vector2(1.0, 2.4), 0.9, 2.0, 180.0, Vector2(0.3, 0.8))
	var mat := _mote_mat.duplicate() as StandardMaterial3D
	mat.emission = color
	p.material_override = mat


func ring(pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.3
	tm.outer_radius = 0.36
	tm.rings = 24
	tm.ring_segments = 6
	mi.mesh = tm
	var mat := _mote_mat.duplicate() as StandardMaterial3D
	mat.albedo_color = color
	mat.emission = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.position = pos + Vector3(0, 0.05, 0)
	add_child(mi)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(2.2, 1, 2.2), 0.6).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.6)
	tw.chain().tween_callback(mi.queue_free)
