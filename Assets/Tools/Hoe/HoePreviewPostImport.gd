@tool
extends EditorScenePostImport
## Preserve ForestGirl vertex colors and the preview's hold loop on import.
func _post_import(scene: Node) -> Object:
	_configure(scene)
	return scene

func _configure(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var colors = node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
			var material = node.get_active_material(surface)
			if colors != null and not colors.is_empty() and material is StandardMaterial3D:
				material.vertex_color_use_as_albedo = true
	if node is AnimationPlayer:
		for name in node.get_animation_list():
			node.get_animation(name).loop_mode = Animation.LOOP_LINEAR if name == "HoeIdle" else Animation.LOOP_NONE
	for child in node.get_children():
		_configure(child)
