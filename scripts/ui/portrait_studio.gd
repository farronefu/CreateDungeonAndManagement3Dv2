class_name PortraitStudio
extends SubViewport
## Renders a 3D model into a texture for the UI (hero portrait, cut-ins, icons).

var actor: ModelActor
var cam: Camera3D


func setup(packed: PackedScene, px: Vector2i, height: float, cam_pos: Vector3, look_at_pos: Vector3, fov_deg: float = 30.0, fix_colors: bool = false, loops: Array = []) -> void:
	size = px
	transparent_bg = true
	own_world_3d = true
	msaa_3d = Viewport.MSAA_4X
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.72, 0.8)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.6
	key.light_color = Color(1.0, 0.93, 0.82)
	key.rotation_degrees = Vector3(-35, 30, 0)
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.9
	rim.light_color = Color(0.6, 0.75, 1.0)
	rim.rotation_degrees = Vector3(-20, 200, 0)
	add_child(rim)
	actor = ModelActor.new()
	add_child(actor)
	actor.setup(packed, height, 0.0, fix_colors, loops)
	cam = Camera3D.new()
	cam.fov = fov_deg
	add_child(cam)
	cam.position = cam_pos
	cam.look_at(look_at_pos, Vector3.UP)


func freeze_after(frames: int = 3) -> void:
	for i in frames:
		await RenderingServer.frame_post_draw
	render_target_update_mode = SubViewport.UPDATE_DISABLED
