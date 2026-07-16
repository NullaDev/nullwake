class_name ConfigDB
extends RefCounted

const CONFIG_PATH := "res://config/game_data.json"

var data: Dictionary = {}
var nodes: Dictionary = {}
var ai: Dictionary = {}
var loot: Dictionary = {}
var series: Dictionary = {}
var tech: Dictionary = {}
var memories: Dictionary = {}


func load_config() -> bool:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("Missing game configuration: %s" % CONFIG_PATH)
		return false
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Invalid game configuration JSON")
		return false
	data = parsed
	nodes = _index_by_id(data.get("nodes", []))
	ai = _index_by_id(data.get("ai_definitions", []))
	loot = _index_by_id(data.get("loot", []))
	series = _index_by_id(data.get("series", []))
	tech = _index_by_id(data.get("tech", []))
	memories = _index_by_id(data.get("memories", []))
	return true


func _index_by_id(items: Array) -> Dictionary:
	var result := {}
	for item: Dictionary in items:
		result[item.get("id", "")] = item
	return result


func terminal(level: int) -> Dictionary:
	var levels: Array = data.get("terminal_levels", [])
	if levels.is_empty():
		return {}
	return levels[clampi(level - 1, 0, levels.size() - 1)]


func max_terminal_level() -> int:
	return data.get("terminal_levels", []).size()

