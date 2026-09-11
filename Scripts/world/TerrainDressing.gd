@tool
extends Node3D
class_name TerrainDressing

## Keeps static environment props attached to the Terrain3D surface.
## The correction is calculated from each prop's actual mesh bounds, so assets
## with a slightly different origin do not sink or float at the same height.

@export var ground_offset: float = 0.02
@export var snap_on_ready: bool = true

var _snapped := false

func _ready() -> void:
	if snap_on_ready:
		call_deferred("_snap_all_to_terrain")

func _process(_delta: float) -> void:
	# In the editor and during startup, Terrain3D may register/load one frame
	# after this scene. Retry until the height data becomes available.
	if snap_on_ready and not _snapped:
		_snap_all_to_terrain()

func _snap_all_to_terrain() -> void:
	if _snapped and not Engine.is_editor_hint():
		return

	var terrain := _find_terrain()
	if terrain == null or not terrain.has_method("get_data"):
		return

	var terrain_data: Object = terrain.get_data()
	if terrain_data == null or not terrain_data.has_method("get_height"):
		return

	for child in get_children():
		_snap_node_tree(child, terrain_data)

	_snapped = true

func _snap_node_tree(node: Node, terrain_data: Object) -> void:
	if node is Node3D and _is_prop_root(node):
		_snap_prop(node as Node3D, terrain_data)
		return

	for child in node.get_children():
		_snap_node_tree(child, terrain_data)

func _is_prop_root(node: Node) -> bool:
	if node is MeshInstance3D:
		return true
	if not _contains_mesh(node):
		return false

	# Stop at the imported asset root (which normally owns one or more mesh
	# children), while continuing through the Trees/Bushes/Rocks/Grass folders.
	for child in node.get_children():
		if child is Node3D and not (child is MeshInstance3D) and _contains_mesh(child):
			return false
	return true

func _snap_prop(prop: Node3D, terrain_data: Object) -> void:
	var surface_y := float(terrain_data.get_height(Vector3(prop.global_position.x, 0.0, prop.global_position.z)))
	if is_nan(surface_y) or is_inf(surface_y):
		return

	var lowest_world_y := _get_lowest_world_y(prop)
	if is_inf(lowest_world_y):
		return

	prop.global_position.y += surface_y + ground_offset - lowest_world_y

func _contains_mesh(node: Node) -> bool:
	if node is MeshInstance3D:
		return true

	for child in node.get_children():
		if _contains_mesh(child):
			return true
	return false

func _get_lowest_world_y(node: Node3D) -> float:
	var lowest := INF
	var meshes: Array[Node] = []
	_collect_meshes(node, meshes)

	for mesh_node in meshes:
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue

		var aabb := mesh_instance.get_aabb()
		for x in [aabb.position.x, aabb.end.x]:
			for y in [aabb.position.y, aabb.end.y]:
				for z in [aabb.position.z, aabb.end.z]:
					var world_point := mesh_instance.global_transform * Vector3(x, y, z)
					lowest = minf(lowest, world_point.y)

	return lowest

func _collect_meshes(node: Node, meshes: Array[Node]) -> void:
	if node is MeshInstance3D:
		meshes.append(node)

	for child in node.get_children():
		_collect_meshes(child, meshes)

func _find_terrain() -> Node:
	var terrain := get_tree().get_first_node_in_group("terrain_node")
	if terrain != null:
		return terrain

	var scene_root := get_tree().current_scene
	if scene_root != null:
		terrain = scene_root.find_child("Terrain3D", true, false)
		if terrain != null:
			return terrain

	return get_tree().root.find_child("Terrain3D", true, false)
