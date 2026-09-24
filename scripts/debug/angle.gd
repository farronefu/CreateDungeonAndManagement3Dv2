extends Node
## --angle=yaw_deg,pitch_deg : orbits the game camera for scripted screenshots.

func _process(_delta: float) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--angle="):
			var p := a.get_slice("=", 1).split(",")
			get_parent().cam.set_angle(deg_to_rad(float(p[0])), deg_to_rad(float(p[1])))
