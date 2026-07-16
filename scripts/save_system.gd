class_name SaveSystem
extends RefCounted

const SAVE_PATH := "user://nullwake_save.json"
const TEMP_PATH := "user://nullwake_save.tmp"


static func save(data: Dictionary) -> bool:
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(TEMP_PATH), ProjectSettings.globalize_path(SAVE_PATH)) == OK


static func load_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}


static func erase() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


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
