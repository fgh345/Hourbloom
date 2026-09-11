@tool
extends Node3D
class_name KenneyMaterialCalibration

## Applies project-friendly material response to a Kenney prefab without
## replacing the asset's separate albedo/color regions.
##
## Kenney's source GLBs declare a metallic response that is too strong for
## Hourbloom's outdoor farm lighting. The override is kept on the prefab
## instance, so the original GLB files remain untouched.

@export_range(0.0, 1.0, 0.05) var metallic: float = 0.0
@export_range(0.0, 1.0, 0.05) var roughness: float = 0.82
@export var apply_on_ready: bool = true

var _applied := false

func _ready() -> void:
	if apply_on_ready:
		call_deferred("apply_calibration")

func apply_calibration() -> void:
	if _applied:
		return

	var changed := 0
	for node in _collect_meshes(self):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue

		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var material := mesh_instance.get_active_material(surface_index)
			if not material is BaseMaterial3D:
				continue

			var calibrated := material.duplicate() as BaseMaterial3D
			calibrated.metallic = metallic
			calibrated.roughness = roughness
			mesh_instance.set_surface_override_material(surface_index, calibrated)
			changed += 1

	_applied = true
	if Engine.is_editor_hint() and changed == 0:
		push_warning("KenneyMaterialCalibration: no BaseMaterial3D surfaces found on %s." % name)

func _collect_meshes(node: Node) -> Array[Node]:
	var meshes: Array[Node] = []
	if node is MeshInstance3D:
		meshes.append(node)

	for child in node.get_children():
		meshes.append_array(_collect_meshes(child))
	return meshes
