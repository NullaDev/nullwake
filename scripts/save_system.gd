class_name SaveSystem
extends RefCounted

const SAVE_PATH := "user://nullwake_save.json"
const TEMP_PATH := "user://nullwake_save.tmp"

static var _active_save_path := SAVE_PATH
static var _active_temp_path := TEMP_PATH


static func use_storage_paths(save_path: String, temp_path: String) -> void:
	_active_save_path = save_path
	_active_temp_path = temp_path


static func restore_default_storage_paths() -> void:
	_active_save_path = SAVE_PATH
	_active_temp_path = TEMP_PATH


static func save(data: Dictionary) -> bool:
	var file := FileAccess.open(_active_temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	if FileAccess.file_exists(_active_save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_active_save_path))
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(_active_temp_path), ProjectSettings.globalize_path(_active_save_path)) == OK


static func load_save() -> Dictionary:
	if not FileAccess.file_exists(_active_save_path):
		return {}
	var file := FileAccess.open(_active_save_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}


static func erase() -> void:
	if FileAccess.file_exists(_active_save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_active_save_path))


static func export_code(data: Dictionary) -> String:
	return Marshalls.raw_to_base64(JSON.stringify(data).to_utf8_buffer())


static func import_code(code: String) -> Dictionary:
	var raw := Marshalls.base64_to_raw(code.strip_edges())
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if parsed is Dictionary:
		return parsed
	return {}
