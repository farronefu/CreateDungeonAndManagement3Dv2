extends Node
## Prints every visible ModelActor with its viewport, for debugging leaks between worlds.

func _ready() -> void:
	await get_tree().create_timer(0.5).timeout
	for n in get_tree().root.find_children("*", "ModelActor", true, false):
		var a := n as ModelActor
		print("actor under %s  vis=%s  gpos=%s  vp=%s own_world=%s" % [a.get_parent().name, a.is_visible_in_tree(), a.global_position, a.get_viewport().name, a.get_viewport().own_world_3d])
