class_name Effects
extends Node3D
## One-shot visual effects built from soft billboard sprites (radial glows, puffs, stars, rings)
## that fade and shrink, instead of raw primitives: dig debris, dust, nutrient motes,
## damage numbers, sparkles and pulse rings.

static var _tex_glow: Texture2D
static var _tex_puff: Texture2D
static var _tex_ring: Texture2D
static var _tex_star: Texture2D

var _debris_mesh: BoxMesh
var _mat_glow: StandardMaterial3D
var _mat_puff: StandardMaterial3D
var _mat_star: StandardMaterial3D
var _mat_ring: StandardMaterial3D


func _ready() -> void:
	_make_textures()
	_debris_mesh = BoxMesh.new()
	_debris_mesh.size = Vector3.ONE * 0.07
	var dm := StandardMaterial3D.new()
	dm.vertex_color_use_as_albedo = true
	dm.vertex_color_is_srgb = true
	dm.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	dm.roughness = 1.0
	_debris_mesh.material = dm
	_mat_glow = _sprite_mat(_tex_glow, true)
	_mat_star = _sprite_mat(_tex_star, true)
	_mat_puff = _sprite_mat(_tex_puff, false)
	_mat_ring = StandardMaterial3D.new()
	_mat_ring.albedo_texture = _tex_ring
	_mat_ring.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_ring.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_ring.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat_ring.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_ring.vertex_color_use_as_albedo = true


static func _make_textures() -> void:
	if _tex_glow:
		return
	_tex_glow = _radial([[0.0, Color(1, 1, 1, 1)], [0.25, Color(1, 1, 1, 0.8)], [1.0, Color(1, 1, 1, 0)]])
	_tex_puff = _radial([[0.0, Color(1, 1, 1, 0.55)], [0.55, Color(1, 1, 1, 0.3)], [1.0, Color(1, 1, 1, 0)]])
	_tex_ring = _radial([[0.0, Color(1, 1, 1, 0)], [0.72, Color(1, 1, 1, 0)], [0.84, Color(1, 1, 1, 1)], [0.92, Color(1, 1, 1, 0.35)], [1.0, Color(1, 1, 1, 0)]])
	# four-point star
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var p := Vector2(x - 31.5, y - 31.5) / 31.5
			var core := exp(-p.length_squared() * 18.0)
			var rays := exp(-absf(p.x) * 26.0) * (1.0 - absf(p.y)) + exp(-absf(p.y) * 26.0) * (1.0 - absf(p.x))
			var a := clampf(core + rays * 0.9, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	_tex_star = ImageTexture.create_from_image(img)


static func _radial(stops: Array) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(stops.map(func(s: Array) -> float: return s[0]))
	g.colors = PackedColorArray(stops.map(func(s: Array) -> Color: return s[1]))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _sprite_mat(tex: Texture2D, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.no_depth_test = false
	return m


func _quad(size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	return q


## Burst of billboard sprites with colour / size fading over their life.
func _burst(pos: Vector3, amount: int, mat: Material, size: float, colors: Gradient, speed: Vector2, lifetime: float, gravity: float, spread: float, box: float, scale_curve: Curve) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = amount
	p.lifetime = lifetime
	p.mesh = _quad(size)
	p.material_override = mat
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.gravity = Vector3(0, -gravity, 0)
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.color_ramp = colors
	p.scale_amount_curve = scale_curve
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = box
	p.position = pos
	add_child(p)
	p.emitting = true
	get_tree().create_timer(lifetime + 0.5).timeout.connect(p.queue_free)
	return p


func _fade(c0: Color, c1: Color) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	g.colors = PackedColorArray([c0, c0, Color(c1.r, c1.g, c1.b, 0.0)])
	return g


func _curve(points: Array) -> Curve:
	var c := Curve.new()
	for pt in points:
		c.add_point(Vector2(pt[0], pt[1]))
	return c


func debris(c: Vector2i, mossy: float) -> void:
	var pos := DungeonGrid.cell_center(c, Balance.BLOCK_H * 0.55)
	# clods of earth
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 22
	p.lifetime = 0.8
	p.mesh = _debris_mesh
	p.direction = Vector3.UP
	p.spread = 65.0
	p.initial_velocity_min = 1.6
	p.initial_velocity_max = 3.2
	p.gravity = Vector3(0, -11, 0)
	p.angular_velocity_min = -400
	p.angular_velocity_max = 400
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.scale_amount_curve = _curve([[0.0, 1.0], [0.75, 1.0], [1.0, 0.0]])
	var g := Gradient.new()
	g.set_color(0, Color(0.36, 0.25, 0.16))
	g.set_color(1, Color(0.3, 0.38, 0.18).lerp(Color(0.45, 0.33, 0.22), 1.0 - mossy))
	p.color_initial_ramp = g
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.3, 0.3, 0.3)
	p.position = pos
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.3).timeout.connect(p.queue_free)
	dust(pos, Color(0.72, 0.6, 0.46, 0.7))


func dust(pos: Vector3, color: Color, size: float = 1.0) -> void:
	_burst(pos, 10, _mat_puff, 0.55 * size, _fade(color, color.lightened(0.2)), Vector2(0.4, 1.0), 0.9, -0.4, 180.0, 0.25 * size, _curve([[0.0, 0.5], [1.0, 1.6]]))


## Glowing nutrient motes flying between a soil block and a monster.
func motes(from: Vector3, to: Vector3, color: Color = Color(0.6, 1.0, 0.35)) -> void:
	for i in 3:
		var s := Sprite3D.new()
		s.texture = _tex_glow
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.pixel_size = 0.0045
		s.modulate = Color(color.r, color.g, color.b, 0.95)
		s.shaded = false
		s.transparent = true
		s.no_depth_test = false
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.position = from
		s.scale = Vector3.ONE * (0.8 - i * 0.18)
		add_child(s)
		var mid := (from + to) * 0.5 + Vector3(randf_range(-0.2, 0.2), 0.4 + i * 0.08, randf_range(-0.2, 0.2))
		var tw := s.create_tween()
		tw.tween_interval(i * 0.07)
		tw.tween_method(func(t: float) -> void:
			var a := from.lerp(mid, t)
			var b := mid.lerp(to, t)
			s.position = a.lerp(b, t)
			s.modulate.a = 0.95 * (1.0 - t * t), 0.0, 1.0, 0.6).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(s.queue_free)


func number(pos: Vector3, text: String, color: Color, big: bool = false) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font = UiTheme.serif(900)
	l.font_size = 64 if big else 48
	l.pixel_size = 0.005
	l.outline_size = 12
	l.modulate = color
	l.outline_modulate = Color(0.1, 0.04, 0.02, 0.9)
	l.position = pos + Vector3(randf_range(-0.12, 0.12), 0, 0)
	l.scale = Vector3.ONE * 0.4
	add_child(l)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", pos.y + 0.6, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.6)
	tw.chain().tween_callback(l.queue_free)


func sparkle(pos: Vector3, color: Color, amount: int = 14) -> void:
	_burst(pos, amount, _mat_star, 0.22, _fade(color.lightened(0.3), color), Vector2(0.8, 1.8), 0.8, 1.2, 180.0, 0.15, _curve([[0.0, 0.2], [0.2, 1.0], [1.0, 0.0]]))
	_burst(pos, 1, _mat_glow, 0.9, _fade(Color(color, 0.7), color), Vector2.ZERO, 0.45, 0.0, 0.0, 0.0, _curve([[0.0, 0.6], [1.0, 1.4]]))


func ring(pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 1.2)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	var mat := _mat_ring.duplicate() as StandardMaterial3D
	mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos + Vector3(0, 0.04, 0)
	mi.scale = Vector3.ONE * 0.4
	add_child(mi)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 1.6, 0.55).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.55).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)
