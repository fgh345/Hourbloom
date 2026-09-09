extends SceneTree

const SCAN_ROOTS: PackedStringArray = ["res://Scenes", "res://Assets"]
const RESOURCE_EXTENSIONS: PackedStringArray = ["tscn", "tres"]
const EXT_RESOURCE_PATTERN := \
	'^\\[ext_resource\\b[^]\\n]*\\buid="(uid://[^"]+)"[^]\\n]*\\bpath="([^"]+)"[^]\\n]*\\]$'


func _init() -> void:
	var should_fix := "--fix" in OS.get_cmdline_user_args()
	var pattern := RegEx.new()
	var compile_error := pattern.compile(EXT_RESOURCE_PATTERN)
	if compile_error != OK:
		push_error("Could not compile resource UID validation pattern")
		quit(2)
		return

	var resource_files: PackedStringArray = []
	for root in SCAN_ROOTS:
		_collect_resource_files(root, resource_files)
	resource_files.sort()

	var mismatch_count := 0
	var unresolved_count := 0
	var fixed_file_count := 0
	for resource_path in resource_files:
		var result := _validate_resource_file(resource_path, pattern, should_fix)
		mismatch_count += result.mismatches
		unresolved_count += result.unresolved
		if result.changed:
			fixed_file_count += 1

	if unresolved_count > 0:
		push_error("Resource UID validation found %d unresolved paths" % unresolved_count)
		quit(1)
	elif mismatch_count > 0 and not should_fix:
		push_error("Resource UID validation found %d stale references; rerun with -- --fix" % mismatch_count)
		quit(1)
	else:
		print("Resource UID validation passed: %d files scanned, %d stale references fixed in %d files" % [
			resource_files.size(), mismatch_count, fixed_file_count
		])
		quit()


func _collect_resource_files(directory_path: String, output: PackedStringArray) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		push_error("Could not scan resource directory: %s" % directory_path)
		return

	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var entry_path := directory_path.path_join(entry)
		if directory.current_is_dir():
			_collect_resource_files(entry_path, output)
		elif entry.get_extension() in RESOURCE_EXTENSIONS:
			output.append(entry_path)
		entry = directory.get_next()
	directory.list_dir_end()


func _validate_resource_file(resource_path: String, pattern: RegEx, should_fix: bool) -> Dictionary:
	var source := FileAccess.get_file_as_string(resource_path)
	if source.is_empty() and FileAccess.get_open_error() != OK:
		push_error("Could not read resource file: %s" % resource_path)
		return {"mismatches": 0, "unresolved": 1, "changed": false}

	var updated_source := source
	var mismatch_count := 0
	var unresolved_count := 0
	for line in source.split("\n"):
		var match := pattern.search(line)
		if match == null:
			continue
		var stored_uid := match.get_string(1)
		var dependency_path := match.get_string(2)
		var resource_uid := ResourceLoader.get_resource_uid(dependency_path)
		if resource_uid == ResourceUID.INVALID_ID:
			push_error("%s references an unresolved resource: %s" % [resource_path, dependency_path])
			unresolved_count += 1
			continue
		var current_uid := ResourceUID.id_to_text(resource_uid)
		if stored_uid == current_uid:
			continue

		mismatch_count += 1
		print("%s: %s -> %s (%s)" % [resource_path, stored_uid, current_uid, dependency_path])
		if should_fix:
			updated_source = updated_source.replace(
				'uid="%s" path="%s"' % [stored_uid, dependency_path],
				'uid="%s" path="%s"' % [current_uid, dependency_path]
			)

	var changed := should_fix and updated_source != source
	if changed:
		var file := FileAccess.open(resource_path, FileAccess.WRITE)
		if file == null:
			push_error("Could not update resource file: %s" % resource_path)
			return {"mismatches": mismatch_count, "unresolved": unresolved_count + 1, "changed": false}
		file.store_string(updated_source)

	return {"mismatches": mismatch_count, "unresolved": unresolved_count, "changed": changed}
