class_name GameState
extends Node

signal changed(reason: String)
signal notice(message: String, kind: String)

const SAVE_VERSION := "1.2.0"
const SAFE_RESERVE := 12

var config := ConfigDB.new()
var data: Dictionary = {}
var _uid_counter := 0
var _game_time_accumulator := 0.0
var _autosave_accumulator := 0.0


func initialize() -> bool:
	if not config.load_config():
		return false
	var loaded := SaveSystem.load_save()
	if _validate_save(loaded):
		data = loaded
		_migrate_and_repair()
	else:
		data = _new_game_data()
	_reseed_uid_counter()
	_reschedule_compute()
	return true


func _new_game_data() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"config_version": config.data.get("config_version", "unknown"),
		"energy": 0,
		"total_energy": 0,
		"compute_capacity": 0,
		"fragments": 0,
		"cycle": 1,
		"run_energy": 0,
		"run_score": 0,
		"echo": 0,
		"echo_remainder": 0.0,
		"lifetime_echo": 0,
		"cycle_memory_core_solved": false,
		"terminal_level": 1,
		"unlocked_ai": [],
		"purchased_tech": [],
		"tech_levels": {},
		"permanent_nodes": ["maintenance"],
		"inventory": [],
		"loot": {},
		"claimed_series": [],
		"series_pity": {},
		"memories": [],
		"unique_completed": [],
		"completed_node_types": [],
		"channels": [_make_channel(0, true, {"kind": "permanent", "id": "maintenance"}, config.data.get("tutorial", {}).get("fixed_secret", "001"))],
		"tutorial_step": "awakening",
		"tutorial_completed": false,
		"random_counter": 1,
		"settings": {"auto_dismantle": true, "reduced_motion": false, "safe_reserve": SAFE_RESERVE, "bulk_tech_purchase": false},
		"statistics": {
			"play_time": 0.0, "guesses": 0, "solved": 0, "manual_solved": 0,
			"ai_solved": {}, "failed": 0, "abandoned": 0, "nodes_bought": 0,
			"nodes_sold": 0, "energy_lost": 0, "loot_total": 0, "duplicates_dismantled": 0,
			"direct_success": 0, "current_streak": 0, "best_streak": 0, "node_stats": {}
		}
	}


func _make_channel(index: int, unlocked: bool, node_ref: Dictionary = {}, fixed_secret := "") -> Dictionary:
	return {
		"id": "channel_%02d" % (index + 1), "unlocked": unlocked,
		"node_ref": node_ref.duplicate(true), "secret": fixed_secret, "started": false,
		"state": "READY" if not node_ref.is_empty() else "EMPTY", "previous_state": "",
		"history": [], "ai_id": "", "ai_phase_started_ms": 0, "ai_due_ms": 0, "resolution_due_ms": 0,
		"auto_restock": false,
		"pending_reward": {}, "settlement_token": "", "settled_tokens": [], "last_operator": "manual",
		"priority": index
	}


func _validate_save(candidate: Dictionary) -> bool:
	if candidate.is_empty():
		return false
	if not candidate.has("save_version") or not candidate.has("channels"):
		return false
	return candidate.get("channels", []) is Array


func _migrate_and_repair() -> void:
	var defaults := _new_game_data()
	for key in defaults:
		if not data.has(key):
			data[key] = defaults[key]
	data["save_version"] = SAVE_VERSION
	data["config_version"] = config.data.get("config_version", "unknown")
	if not "maintenance" in data.permanent_nodes:
		data.permanent_nodes.append("maintenance")
	if data.channels.is_empty():
		data.channels.append(_make_channel(0, true))
	for index in range(data.channels.size()):
		_repair_channel(data.channels[index], index)
	var required_channels: int = maxi(1, int(data.get("terminal_level", 1)))
	while data.channels.size() < mini(required_channels, config.max_terminal_level()):
		data.channels.append(_make_channel(data.channels.size(), false))
	_normalize_channel_priorities()
	if not data.settings is Dictionary:
		data.settings = defaults.settings
	for key in defaults.settings:
		if not data.settings.has(key):
			data.settings[key] = defaults.settings[key]
	if not data.statistics is Dictionary:
		data.statistics = defaults.statistics
	for key in defaults.statistics:
		if not data.statistics.has(key):
			data.statistics[key] = defaults.statistics[key]
	if not data.series_pity is Dictionary:
		data.series_pity = {}
	if not data.tech_levels is Dictionary:
		data.tech_levels = {}
	for tech_id in data.get("purchased_tech", []):
		if config.tech.has(tech_id) and int(data.tech_levels.get(tech_id, 0)) <= 0:
			data.tech_levels[tech_id] = 1
	if "memory_core" in data.unique_completed and not bool(data.get("cycle_memory_core_solved", false)):
		data.cycle_memory_core_solved = true
	if bool(data.get("tutorial_completed", false)) and not "automation_guide" in data.memories:
		data.memories.append("automation_guide")
		if int(data.get("compute_capacity", 0)) == 0 and data.get("tutorial_step", "completed") == "completed":
			data.tutorial_step = "automation_hint"
	if bool(data.get("tutorial_completed", false)) and not "feedback_guide" in data.memories:
		data.memories.append("feedback_guide")
	if not data.get("loot", {}).is_empty() and not "collection_guide" in data.memories:
		data.memories.append("collection_guide")
	if int(data.get("compute_capacity", 0)) > 0 and not "compute_guide" in data.memories:
		data.memories.append("compute_guide")


func _repair_channel(channel: Dictionary, index: int) -> void:
	var clean := _make_channel(index, bool(channel.get("unlocked", index == 0)))
	for key in clean:
		if not channel.has(key):
			channel[key] = clean[key]
	var node_ref: Dictionary = channel.get("node_ref", {})
	if not node_ref.is_empty() and get_node_from_ref(node_ref).is_empty():
		channel.node_ref = {}
		channel.secret = ""
		channel.started = false
		channel.history = []
		channel.state = "EMPTY"
	if channel.state in ["RESOLVING_GUESS", "AI_HANDSHAKE", "AI_THINKING", "AI_PENDING"]:
		channel.state = "WAITING_FOR_INPUT" if channel.ai_id == "" else "AI_PENDING"
		channel.ai_phase_started_ms = 0
		channel.ai_due_ms = 0


func _reseed_uid_counter() -> void:
	_uid_counter = int(Time.get_unix_time_from_system()) % 1000000
	for instance: Dictionary in data.get("inventory", []):
		var pieces: PackedStringArray = str(instance.get("uid", "0")).split("-")
		if pieces.size() > 1:
			_uid_counter = maxi(_uid_counter, int(pieces[-1]))


func save_now() -> void:
	SaveSystem.save(data)


func export_save() -> String:
	return SaveSystem.export_code(data)


func import_save(code: String) -> bool:
	var imported := SaveSystem.import_code(code)
	if not _validate_save(imported):
		notice.emit("导入失败：存档内容无效。", "error")
		return false
	data = imported
	_migrate_and_repair()
	_reseed_uid_counter()
	_reschedule_compute()
	save_now()
	changed.emit("imported")
	notice.emit("存档已导入并通过校验。", "success")
	return true


func reset_game() -> void:
	SaveSystem.erase()
	data = _new_game_data()
	_reseed_uid_counter()
	changed.emit("reset")
	save_now()


func tick(delta: float) -> void:
	_game_time_accumulator += delta
	_autosave_accumulator += delta
	if _game_time_accumulator >= 1.0:
		data.statistics.play_time = float(data.statistics.get("play_time", 0.0)) + _game_time_accumulator
		_game_time_accumulator = 0.0
	if _autosave_accumulator >= 12.0:
		_autosave_accumulator = 0.0
		save_now()
	_process_ai()


func start_tutorial() -> void:
	if data.tutorial_step != "awakening":
		return
	data.tutorial_step = "first_guess"
	changed.emit("tutorial")
	save_now()


func terminal_spec() -> Dictionary:
	return config.terminal(int(data.terminal_level))


func region_name() -> String:
	return terminal_spec().get("region", "未知区域")


func node_definition(node_id: String) -> Dictionary:
	return config.nodes.get(node_id, {})


func ai_definition(ai_id: String) -> Dictionary:
	return config.ai.get(ai_id, {})


func inventory_instance(uid: String) -> Dictionary:
	for instance: Dictionary in data.inventory:
		if instance.get("uid", "") == uid:
			return instance
	return {}


func get_node_from_ref(node_ref: Dictionary) -> Dictionary:
	if node_ref.is_empty():
		return {}
	if node_ref.get("kind", "") == "permanent":
		return node_definition(node_ref.get("id", ""))
	var instance := inventory_instance(node_ref.get("uid", ""))
	return node_definition(instance.get("def_id", "")) if not instance.is_empty() else {}


func channel_node(channel_index: int) -> Dictionary:
	if channel_index < 0 or channel_index >= data.channels.size():
		return {}
	return get_node_from_ref(data.channels[channel_index].node_ref)


func is_compatible(node: Dictionary) -> bool:
	if node.is_empty():
		return false
	return int(node.get("terminal_level", 1)) <= int(data.terminal_level)


func used_compute() -> int:
	var used := 0
	for channel: Dictionary in data.channels:
		if channel.get("state", "") in ["AI_HANDSHAKE", "AI_THINKING"]:
			used += int(ai_definition(channel.get("ai_id", "")).get("compute_cost", 0))
	return used


func available_compute() -> int:
	return maxi(0, int(data.compute_capacity) - used_compute())


func channel_priority_rank(channel_index: int) -> int:
	var ordered := _unlocked_channels_by_priority()
	var position := ordered.find(channel_index)
	return position + 1 if position >= 0 else 0


func move_channel_priority(channel_index: int, direction: int) -> bool:
	if channel_index < 0 or channel_index >= data.channels.size() or not bool(data.channels[channel_index].unlocked):
		return false
	var ordered := _unlocked_channels_by_priority()
	var position := ordered.find(channel_index)
	if position < 0:
		return false
	var target := clampi(position + signi(direction), 0, ordered.size() - 1)
	if target == position:
		return false
	var other_index: int = ordered[target]
	var old_priority: int = int(data.channels[channel_index].priority)
	data.channels[channel_index].priority = int(data.channels[other_index].priority)
	data.channels[other_index].priority = old_priority
	_commit("channel:%d:priority" % channel_index)
	return true


func _unlocked_channels_by_priority() -> Array[int]:
	var ordered: Array[int] = []
	for index in range(data.channels.size()):
		if bool(data.channels[index].get("unlocked", false)):
			ordered.append(index)
	ordered.sort_custom(func(a: int, b: int) -> bool:
		var a_priority := int(data.channels[a].get("priority", a))
		var b_priority := int(data.channels[b].get("priority", b))
		return a_priority < b_priority if a_priority != b_priority else a < b
	)
	return ordered


func _normalize_channel_priorities() -> void:
	var order: Array[int] = []
	for index in range(data.channels.size()):
		order.append(index)
	order.sort_custom(func(a: int, b: int) -> bool:
		var a_priority := int(data.channels[a].get("priority", a))
		var b_priority := int(data.channels[b].get("priority", b))
		return a_priority < b_priority if a_priority != b_priority else a < b
	)
	for priority in range(order.size()):
		data.channels[order[priority]].priority = priority


func next_compute_cost() -> int:
	var economy: Dictionary = config.data.get("economy", {})
	var amount: int = int(economy.get("compute_purchase_amount", 2))
	var purchases := int(data.compute_capacity) / amount
	var base_cost := float(economy.get("compute_base_cost", 36))
	if purchases <= 0:
		return int(base_cost)
	var multiplier := float(economy.get("compute_cost_multiplier", 1.75))
	return maxi(5, int(round(base_cost * pow(multiplier, purchases) / 5.0)) * 5)


func purchase_compute() -> void:
	var first_purchase := int(data.compute_capacity) == 0
	var cost := next_compute_cost()
	if int(data.energy) < cost:
		notice.emit("协议能量不足。", "error")
		return
	data.energy -= cost
	data.compute_capacity += int(config.data.economy.get("compute_purchase_amount", 2))
	if not "probe" in data.unlocked_ai:
		data.unlocked_ai.append("probe")
		notice.emit("序列探针已上线。它适合无限尝试协议。", "success")
	else:
		notice.emit("总算力已扩展。", "success")
	if first_purchase:
		_unlock_memory("compute_guide")
	_reschedule_compute()
	_commit("compute")


func purchase_terminal_upgrade() -> void:
	var next_level := int(data.terminal_level) + 1
	if next_level > config.max_terminal_level():
		notice.emit("终端已达到当前版本上限。", "info")
		return
	var upgrade := config.terminal(next_level)
	if int(data.energy) < int(upgrade.energy_cost) or int(data.fragments) < int(upgrade.fragment_cost):
		notice.emit("升级资源不足。", "error")
		return
	data.energy -= int(upgrade.energy_cost)
	data.fragments -= int(upgrade.fragment_cost)
	data.terminal_level = next_level
	while data.channels.size() < int(upgrade.max_channels):
		data.channels.append(_make_channel(data.channels.size(), false))
	if next_level == 2:
		_unlock_memory("terminal_2")
	elif next_level == 3:
		_unlock_memory("terminal_3")
	notice.emit("终端升级完成：%s。" % upgrade.name, "success")
	_commit("terminal")


func purchase_channel() -> void:
	var index := -1
	for i in range(data.channels.size()):
		if not bool(data.channels[i].unlocked):
			index = i
			break
	if index < 0:
		notice.emit("当前终端没有可用的通道接口。", "info")
		return
	if index >= int(terminal_spec().max_channels):
		notice.emit("请先升级终端以开放更多接口。", "error")
		return
	var costs: Array = config.data.economy.get("channel_costs", [])
	var cost := int(costs[index]) if index < costs.size() else 999999
	if int(data.energy) < cost:
		notice.emit("协议能量不足。", "error")
		return
	data.energy -= cost
	data.channels[index].unlocked = true
	notice.emit("解译通道 %02d 已建立。" % (index + 1), "success")
	_commit("channel")


func _commit(reason: String) -> void:
	_reschedule_compute()
	save_now()
	changed.emit(reason)


func buy_node(node_id: String) -> void:
	var node := node_definition(node_id)
	if node.is_empty() or node.get("ownership", "") == "permanent":
		return
	if node.get("ownership", "") == "unique":
		if node_id in data.unique_completed or _owns_node_type(node_id):
			notice.emit("该唯一节点无法再次取得。", "error")
			return
	var cost := int(node.get("cost", 0))
	if has_tech("risk_breaker") and int(data.energy) - cost < int(data.settings.get("safe_reserve", SAFE_RESERVE)):
		notice.emit("风险熔断：采购会侵入安全储备。", "warning")
		return
	if int(data.energy) < cost:
		notice.emit("协议能量不足。", "error")
		return
	data.energy -= cost
	_uid_counter += 1
	data.inventory.append({
		"uid": "node-%d" % _uid_counter, "def_id": node_id,
		"remaining_uses": int(node.get("max_uses", 1)), "acquired_cost": cost,
		"acquired_timestamp": int(Time.get_unix_time_from_system()), "locked_channel": -1
	})
	data.statistics.nodes_bought = int(data.statistics.nodes_bought) + 1
	notice.emit("已取得节点：%s。" % node.name, "success")
	_commit("inventory")


func _owns_node_type(node_id: String) -> bool:
	for instance: Dictionary in data.inventory:
		if instance.get("def_id", "") == node_id:
			return true
	return false


func has_free_grant(node_id: String) -> bool:
	for instance: Dictionary in data.inventory:
		if instance.get("def_id", "") == node_id and bool(instance.get("free_grant", int(instance.get("acquired_cost", 0)) == 0)):
			return true
	return false


func is_channel_free_grant(channel_index: int) -> bool:
	if channel_index < 0 or channel_index >= data.channels.size():
		return false
	var node_ref: Dictionary = data.channels[channel_index].get("node_ref", {})
	if node_ref.get("kind", "") != "inventory":
		return false
	var instance := inventory_instance(node_ref.get("uid", ""))
	return not instance.is_empty() and bool(instance.get("free_grant", int(instance.get("acquired_cost", 0)) == 0))


func sell_node(uid: String) -> void:
	var instance := inventory_instance(uid)
	if instance.is_empty() or int(instance.get("locked_channel", -1)) >= 0:
		notice.emit("已接入或已启动的节点不能出售。", "error")
		return
	var node := node_definition(instance.def_id)
	if bool(instance.get("free_grant", int(instance.get("acquired_cost", 0)) == 0)):
		notice.emit("免费取得的教学节点不能出售。", "error")
		return
	if bool(node.get("protected", false)):
		notice.emit("受保护节点不能出售。", "error")
		return
	var value := int(floor(int(instance.acquired_cost) * float(config.data.economy.get("resale_ratio", 0.5))))
	data.energy += value
	data.inventory.erase(instance)
	data.statistics.nodes_sold = int(data.statistics.nodes_sold) + 1
	notice.emit("节点已回收，返还 %d 协议能量。" % value, "info")
	_commit("inventory")


func load_permanent(node_id: String, channel_index: int) -> void:
	if not node_id in data.permanent_nodes:
		return
	_load_ref({"kind": "permanent", "id": node_id}, channel_index)


func load_inventory(uid: String, channel_index: int) -> void:
	var instance := inventory_instance(uid)
	if instance.is_empty() or int(instance.get("locked_channel", -1)) >= 0:
		notice.emit("该节点当前不可接入。", "error")
		return
	_load_ref({"kind": "inventory", "uid": uid}, channel_index)


func _load_ref(node_ref: Dictionary, channel_index: int) -> void:
	if channel_index < 0 or channel_index >= data.channels.size():
		return
	var channel: Dictionary = data.channels[channel_index]
	if not bool(channel.unlocked) or not channel.node_ref.is_empty():
		notice.emit("请选择一条已解锁且空闲的解译通道。", "error")
		return
	var node := get_node_from_ref(node_ref)
	if not is_compatible(node):
		notice.emit("当前终端与该协议不兼容。", "error")
		return
	channel.node_ref = node_ref.duplicate(true)
	channel.secret = _next_secret(node)
	channel.started = false
	channel.state = "READY"
	channel.history = []
	channel.pending_reward = {}
	channel.ai_id = ""
	if node_ref.get("kind", "") == "inventory":
		inventory_instance(node_ref.uid).locked_channel = channel_index
	notice.emit("%s 已接入通道 %02d。" % [node.name, channel_index + 1], "success")
	_commit("loaded")


func unload_node(channel_index: int) -> void:
	if channel_index < 0 or channel_index >= data.channels.size():
		return
	var channel: Dictionary = data.channels[channel_index]
	if channel.node_ref.is_empty():
		return
	if bool(channel.started):
		notice.emit("节点已锁定；请使用“放弃节点”并承担损失。", "error")
		return
	_unlock_instance(channel.node_ref)
	_clear_channel(channel)
	notice.emit("节点已无损移回库存。", "info")
	_commit("unloaded")


func abandon_node(channel_index: int) -> void:
	if channel_index < 0 or channel_index >= data.channels.size():
		return
	var channel: Dictionary = data.channels[channel_index]
	if channel.node_ref.is_empty():
		return
	if not bool(channel.started):
		unload_node(channel_index)
		return
	channel.state = "ABANDONED"
	channel.last_operator = "manual"
	channel.pending_reward = {"success": false, "abandoned": true, "energy": 0, "settled": false}
	channel.settlement_token = _new_settlement_token(channel_index)
	data.statistics.abandoned = int(data.statistics.abandoned) + 1
	data.statistics.current_streak = 0
	claim_resolution(channel_index)


func _unlock_instance(node_ref: Dictionary) -> void:
	if node_ref.get("kind", "") != "inventory":
		return
	var instance := inventory_instance(node_ref.get("uid", ""))
	if not instance.is_empty():
		instance.locked_channel = -1


func _clear_channel(channel: Dictionary) -> void:
	channel.node_ref = {}
	channel.secret = ""
	channel.started = false
	channel.state = "EMPTY"
	channel.previous_state = ""
	channel.history = []
	channel.ai_id = ""
	channel.ai_phase_started_ms = 0
	channel.ai_due_ms = 0
	channel.resolution_due_ms = 0
	channel.pending_reward = {}
	channel.settlement_token = ""


func _next_secret(node: Dictionary) -> String:
	var counter := int(data.random_counter)
	data.random_counter = counter + 1
	var base_seed := int(config.data.get("seed", 1))
	return PuzzleEngine.generate_secret(node, base_seed + counter * 104729)


func _new_settlement_token(channel_index: int) -> String:
	_uid_counter += 1
	return "%d-%d-%d" % [channel_index, int(Time.get_ticks_msec()), _uid_counter]


func submit_guess(channel_index: int, guess: String, operator := "manual") -> bool:
	if channel_index < 0 or channel_index >= data.channels.size():
		return false
	var channel: Dictionary = data.channels[channel_index]
	var node := channel_node(channel_index)
	if node.is_empty() or channel.state in ["SOLVED", "FAILED", "ABANDONED", "REWARD", "PAUSED"]:
		return false
	guess = guess.strip_edges()
	var error := PuzzleEngine.validate_guess(guess, node)
	if error != "":
		notice.emit(error, "error")
		return false
	if not bool(data.tutorial_completed):
		var tutorial: Dictionary = config.data.get("tutorial", {})
		var first_guess: String = tutorial.get("first_guess", "100")
		var solution_guess: String = tutorial.get("solution_guess", "001")
		if data.tutorial_step == "first_guess" and guess != first_guess:
			notice.emit("教学连接尚未校准。请先输入 %s。" % first_guess, "warning")
			return false
		if data.tutorial_step == "solve_hint" and guess != solution_guess:
			notice.emit("根据反馈重新排列数字：尝试 %s。" % solution_guess, "warning")
			return false
	if not bool(channel.started):
		channel.started = true
	channel.state = "RESOLVING_GUESS"
	channel.last_operator = operator
	var result := PuzzleEngine.visible_feedback(channel.secret, guess, node.get("feedback", "full"))
	channel.history.append({"guess": guess, "feedback": result, "operator": operator})
	data.statistics.guesses = int(data.statistics.guesses) + 1
	if not bool(data.tutorial_completed) and data.tutorial_step == "first_guess":
		data.tutorial_step = "solve_hint"
	var success := guess == str(channel.secret)
	if success:
		if not bool(data.tutorial_completed) and data.tutorial_step == "solve_hint":
			data.tutorial_step = "claim_reward"
		_prepare_success(channel_index)
	else:
		var limit := int(node.get("attempt_limit", 0))
		if limit > 0 and channel.history.size() >= limit:
			_prepare_failure(channel_index)
		else:
			channel.state = "WAITING_FOR_INPUT" if channel.ai_id == "" else "AI_PENDING"
	_reschedule_compute()
	save_now()
	changed.emit("channel:%d:guess" % channel_index)
	return true


func _prepare_success(channel_index: int) -> void:
	var channel: Dictionary = data.channels[channel_index]
	var node: Dictionary = channel_node(channel_index)
	var guesses: int = channel.history.size()
	var base_reward: int = int(node.get("reward", 0))
	var average: float = float(node.get("benchmark", {}).get("average", guesses))
	var efficiency_bonus: int = 0
	if guesses <= average:
		efficiency_bonus = int(ceil(base_reward * 0.15 * (average - guesses + 1.0) / maxf(average, 1.0)))
	if channel.last_operator == "manual" and efficiency_bonus > 0:
		efficiency_bonus = int(round(efficiency_bonus * (1.0 + _collection_effect_sum("manual_efficiency_bonus", node))))
	var reward_value := float(base_reward + efficiency_bonus)
	if channel.last_operator == "manual":
		var efficiency_rate := float(efficiency_bonus) / maxf(float(base_reward), 1.0)
		var active_cap := float(config.data.get("balance", {}).get("manual_active_bonus_cap", 0.75))
		var active_bonus := minf(active_cap, efficiency_rate + _effect_sum("manual_reward_bonus", node))
		reward_value = float(base_reward) * (1.0 + active_bonus)
	reward_value *= 1.0 + _collection_effect_sum("energy_bonus", node)
	reward_value *= 1.0 + _tech_effect_sum("energy_bonus", node)
	reward_value *= prestige_multiplier()
	var final_reward := maxi(1, int(round(reward_value)))
	channel.state = "SOLVED"
	channel.pending_reward = {"success": true, "energy": final_reward, "bonus": final_reward - base_reward, "settled": false}
	channel.settlement_token = _new_settlement_token(channel_index)
	channel.resolution_due_ms = Time.get_ticks_msec() + 700


func _prepare_failure(channel_index: int) -> void:
	var channel: Dictionary = data.channels[channel_index]
	channel.state = "FAILED"
	channel.pending_reward = {"success": false, "abandoned": false, "energy": 0, "settled": false}
	channel.settlement_token = _new_settlement_token(channel_index)
	channel.resolution_due_ms = Time.get_ticks_msec() + 700


func claim_resolution(channel_index: int) -> void:
	if channel_index < 0 or channel_index >= data.channels.size():
		return
	var channel: Dictionary = data.channels[channel_index]
	if channel.pending_reward.is_empty() or bool(channel.pending_reward.get("settled", false)):
		return
	var token: String = channel.get("settlement_token", "")
	if token == "" or token in channel.get("settled_tokens", []):
		return
	channel.pending_reward.settled = true
	channel.settled_tokens.append(token)
	if channel.settled_tokens.size() > 12:
		channel.settled_tokens.pop_front()
	var node := channel_node(channel_index)
	var success: bool = bool(channel.pending_reward.get("success", false))
	var abandoned: bool = bool(channel.pending_reward.get("abandoned", false))
	var preserves_free_grant := abandoned and is_channel_free_grant(channel_index)
	var restock_ai_id: String = channel.get("ai_id", "")
	var should_restock := success and bool(channel.get("auto_restock", false)) and channel_has_auto_restock(channel_index)
	if success:
		var reward := int(channel.pending_reward.get("energy", 0))
		data.energy += reward
		data.total_energy += reward
		data.run_energy = int(data.get("run_energy", 0)) + reward
		data.run_score = int(data.get("run_score", 0)) + reward + int(node.get("prestige_score", 0))
		data.statistics.solved = int(data.statistics.solved) + 1
		data.statistics.current_streak = int(data.statistics.current_streak) + 1
		data.statistics.best_streak = maxi(int(data.statistics.best_streak), int(data.statistics.current_streak))
		if channel.last_operator == "manual":
			data.statistics.manual_solved = int(data.statistics.manual_solved) + 1
		else:
			data.statistics.ai_solved[channel.last_operator] = int(data.statistics.ai_solved.get(channel.last_operator, 0)) + 1
		_record_node_result(node.id, true)
		if channel.history.size() == 1:
			data.statistics.direct_success = int(data.statistics.direct_success) + 1
		_roll_loot(node)
		if not node.id in data.completed_node_types:
			data.completed_node_types.append(node.id)
		if node.get("ownership", "") == "consumable":
			_unlock_memory("first_consumable")
		if node.id == "memory_core":
			data.cycle_memory_core_solved = true
			_unlock_memory("core_truth")
			notice.emit("记忆核心已解译。设施航线正在闭合。", "success")
		else:
			notice.emit("破解完成：+%d 协议能量。" % reward, "success")
	else:
		data.statistics.current_streak = 0
		if not abandoned:
			data.statistics.failed = int(data.statistics.failed) + 1
		_record_node_result(node.id, false)
		var attempt_cost := _current_attempt_cost(channel.node_ref, node)
		var refund_rate := clampf(_effect_sum("failure_refund", node), 0.0, 0.60)
		if refund_rate > 0.0 and node.get("ownership", "") != "permanent" and not bool(node.get("protected", false)):
			var refund := int(floor(attempt_cost * refund_rate))
			data.energy += refund
			if refund > 0:
				notice.emit("启动保险返还 %d 协议能量。" % refund, "info")
		if not bool(node.get("protected", false)):
			data.statistics.energy_lost = int(data.statistics.energy_lost) + attempt_cost
		if preserves_free_grant:
			notice.emit("连接已切断，教学赠送节点已退回库存。", "warning")
		elif abandoned:
			notice.emit("连接已切断，已启动节点被销毁。", "warning")
		else:
			notice.emit("尝试次数耗尽，节点损毁。", "error")
	_consume_or_reset(channel_index, success)
	if should_restock:
		_auto_restock_channel(channel_index, node, restock_ai_id)
	if bool(data.tutorial_completed) and success and data.get("tutorial_step", "") == "automation_hint":
		data.tutorial_step = "completed"
	if not bool(data.tutorial_completed) and success:
		_complete_tutorial()
	_commit("channel:%d:settled" % channel_index)


func _record_node_result(node_id: String, success: bool) -> void:
	if not data.statistics.node_stats.has(node_id):
		data.statistics.node_stats[node_id] = {"solved": 0, "failed": 0, "guesses": 0}
	var record: Dictionary = data.statistics.node_stats[node_id]
	if success:
		record.solved = int(record.solved) + 1
	else:
		record.failed = int(record.failed) + 1


func _current_acquired_cost(node_ref: Dictionary) -> int:
	if node_ref.get("kind", "") != "inventory":
		return 0
	var instance := inventory_instance(node_ref.get("uid", ""))
	return int(instance.get("acquired_cost", 0))


func _current_attempt_cost(node_ref: Dictionary, node: Dictionary) -> int:
	var cost := _current_acquired_cost(node_ref)
	if node.get("usage", "single") == "limited":
		return int(ceil(float(cost) / maxf(float(node.get("max_uses", 1)), 1.0)))
	return cost


func _consume_or_reset(channel_index: int, success: bool) -> void:
	var channel: Dictionary = data.channels[channel_index]
	var node_ref: Dictionary = channel.node_ref.duplicate(true)
	var node := get_node_from_ref(node_ref)
	if not success and bool(channel.pending_reward.get("abandoned", false)) and is_channel_free_grant(channel_index):
		_unlock_instance(node_ref)
		_clear_channel(channel)
		return
	if node.get("ownership", "") == "permanent":
		_reset_loaded_channel(channel, node)
		return
	if bool(node.get("protected", false)) and not success:
		_reset_loaded_channel(channel, node)
		return
	var instance := inventory_instance(node_ref.get("uid", ""))
	if instance.is_empty():
		_clear_channel(channel)
		return
	instance.remaining_uses = int(instance.remaining_uses) - 1
	if int(instance.remaining_uses) > 0:
		_reset_loaded_channel(channel, node)
	else:
		if node.get("ownership", "") == "unique" and success and not node.id in data.unique_completed:
			data.unique_completed.append(node.id)
		data.inventory.erase(instance)
		_clear_channel(channel)


func _reset_loaded_channel(channel: Dictionary, node: Dictionary) -> void:
	channel.secret = _next_secret(node)
	channel.started = false
	channel.state = "READY"
	channel.history = []
	channel.pending_reward = {}
	channel.settlement_token = ""
	channel.ai_phase_started_ms = 0
	channel.ai_due_ms = 0
	channel.resolution_due_ms = 0


func _complete_tutorial() -> void:
	data.tutorial_completed = true
	data.tutorial_step = "automation_hint"
	_uid_counter += 1
	data.inventory.append({
		"uid": "node-%d" % _uid_counter, "def_id": "data_packet", "remaining_uses": 1,
		"acquired_cost": 0, "acquired_timestamp": int(Time.get_unix_time_from_system()), "locked_channel": -1,
		"free_grant": true
	})
	_award_loot(config.data.get("tutorial", {}).get("first_collection", ""))
	_unlock_memory("awakening")
	_unlock_memory("automation_guide")
	_unlock_memory("feedback_guide")
	notice.emit("生命维持已恢复。获赠一枚常规数据封装。", "success")


func set_channel_auto_restock(channel_index: int, enabled: bool) -> void:
	if channel_index < 0 or channel_index >= data.channels.size() or not has_tech("auto_restock"):
		return
	if enabled and not channel_has_auto_restock(channel_index):
		notice.emit("当前自动重购等级尚未覆盖该节点层级。", "warning")
		return
	data.channels[channel_index].auto_restock = enabled
	_commit("channel:%d:automation" % channel_index)


func _auto_restock_channel(channel_index: int, node: Dictionary, ai_id: String) -> void:
	if channel_index < 0 or channel_index >= data.channels.size() or node.is_empty():
		return
	if node.get("ownership", "") in ["permanent", "unique"]:
		return
	var channel: Dictionary = data.channels[channel_index]
	if not channel.node_ref.is_empty():
		return
	var instance: Dictionary = {}
	for candidate: Dictionary in data.inventory:
		if candidate.get("def_id", "") == node.id and int(candidate.get("locked_channel", -1)) < 0:
			instance = candidate
			break
	if instance.is_empty():
		var cost := int(node.get("cost", 0))
		var reserve := maxi(0, int(data.settings.get("safe_reserve", SAFE_RESERVE)))
		if int(data.energy) - cost < reserve:
			notice.emit("自动重购已暂停：购买 %s 会侵入 %d E 安全储备。" % [node.name, reserve], "warning")
			return
		data.energy -= cost
		_uid_counter += 1
		instance = {
			"uid": "node-%d" % _uid_counter, "def_id": node.id,
			"remaining_uses": int(node.get("max_uses", 1)), "acquired_cost": cost,
			"acquired_timestamp": int(Time.get_unix_time_from_system()), "locked_channel": -1
		}
		data.inventory.append(instance)
		data.statistics.nodes_bought = int(data.statistics.nodes_bought) + 1
	channel.node_ref = {"kind": "inventory", "uid": instance.uid}
	instance.locked_channel = channel_index
	channel.secret = _next_secret(node)
	channel.started = false
	channel.state = "READY"
	channel.history = []
	channel.pending_reward = {}
	channel.settlement_token = ""
	channel.resolution_due_ms = 0
	if ai_id != "" and ai_id in data.unlocked_ai:
		channel.ai_id = ai_id
		channel.state = "AI_PENDING"
	notice.emit("自动重购已接入：%s。" % node.name, "info")


func assign_ai(channel_index: int, ai_id: String) -> void:
	if channel_index < 0 or channel_index >= data.channels.size():
		return
	var channel: Dictionary = data.channels[channel_index]
	var node := channel_node(channel_index)
	if node.is_empty() or channel.state in ["SOLVED", "FAILED", "ABANDONED"]:
		return
	if ai_id == "":
		channel.ai_id = ""
		if channel.state in ["AI_HANDSHAKE", "AI_THINKING", "AI_PENDING"]:
			channel.state = "WAITING_FOR_INPUT" if channel.started else "READY"
		channel.ai_phase_started_ms = 0
		channel.ai_due_ms = 0
		notice.emit("已切换为手动控制，算力立即释放。", "info")
		_commit("ai")
		return
	if not ai_id in data.unlocked_ai:
		notice.emit("该 AI 尚未解锁。", "error")
		return
	var ai_def := ai_definition(ai_id)
	if int(ai_def.get("terminal_level", 1)) > int(data.terminal_level):
		notice.emit("终端无法接入该 AI。", "error")
		return
	if int(node.get("attempt_limit", 0)) > 0 and not bool(ai_def.get("supports_limits", false)):
		notice.emit("序列探针不会分析反馈，不能接入限步协议。", "error")
		return
	channel.ai_id = ai_id
	channel.state = "AI_PENDING"
	channel.ai_phase_started_ms = 0
	channel.ai_due_ms = 0
	_reschedule_compute()
	if channel.state == "AI_PENDING":
		notice.emit("算力不足，通道已进入等待队列。", "warning")
	else:
		notice.emit("%s 已接管通道。" % ai_def.name, "success")
	_commit("ai")


func toggle_pause(channel_index: int) -> void:
	if channel_index < 0 or channel_index >= data.channels.size():
		return
	var channel: Dictionary = data.channels[channel_index]
	if channel.state == "PAUSED":
		channel.state = channel.previous_state if channel.previous_state != "" else "WAITING_FOR_INPUT"
		channel.previous_state = ""
	else:
		if channel.state in ["EMPTY", "SOLVED", "FAILED", "ABANDONED"]:
			return
		channel.previous_state = channel.state
		channel.state = "PAUSED"
	_reschedule_compute()
	_commit("pause")


func _reschedule_compute() -> void:
	var remaining := int(data.get("compute_capacity", 0))
	var active: Array[Dictionary] = []
	var waiting: Array[Dictionary] = []
	for channel: Dictionary in data.get("channels", []):
		if channel.get("ai_id", "") == "" or channel.node_ref.is_empty() or channel.state in ["PAUSED", "SOLVED", "FAILED", "ABANDONED", "EMPTY"]:
			continue
		if channel.state in ["AI_HANDSHAKE", "AI_THINKING"]:
			active.append(channel)
		else:
			waiting.append(channel)
	active.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.priority) < int(b.priority))
	waiting.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.priority) < int(b.priority))
	var order: Array[Dictionary] = []
	order.append_array(active)
	order.append_array(waiting)
	for channel: Dictionary in order:
		var cost := int(ai_definition(channel.ai_id).get("compute_cost", 0))
		if cost <= remaining:
			remaining -= cost
			if channel.state not in ["AI_HANDSHAKE", "AI_THINKING"]:
				var node := get_node_from_ref(channel.node_ref)
				var now := Time.get_ticks_msec()
				channel.ai_phase_started_ms = now
				if channel.history.is_empty() and not bool(channel.started):
					channel.state = "AI_HANDSHAKE"
					channel.ai_due_ms = now + int(_ai_handshake_time(channel.ai_id, node) * 1000.0)
				else:
					channel.state = "AI_THINKING"
					channel.ai_due_ms = now + int(_ai_decision_time(channel.ai_id, node) * 1000.0)
		else:
			channel.state = "AI_PENDING"
			channel.ai_phase_started_ms = 0
			channel.ai_due_ms = 0


func _ai_decision_time(ai_id: String, node: Dictionary = {}) -> float:
	var definition := ai_definition(ai_id)
	var decision_base := float(definition.get("decision_time", definition.get("think_time", 1.5)))
	var minimum_ratio := float(config.data.get("balance", {}).get("minimum_automation_cycle_ratio", 0.20))
	var decision_factor := _speed_factor("ai_speed", node, ai_id) * _speed_factor("cycle_speed", node, ai_id)
	return maxf(decision_base * minimum_ratio, decision_base * decision_factor)


func _ai_handshake_time(ai_id: String, node: Dictionary = {}) -> float:
	var handshake_base := float(node.get("handshake_time", 0.0))
	var minimum_ratio := float(config.data.get("balance", {}).get("minimum_automation_cycle_ratio", 0.20))
	var handshake_factor := _speed_factor("handshake_speed", node, ai_id) * _speed_factor("cycle_speed", node, ai_id)
	return maxf(handshake_base * minimum_ratio, handshake_base * handshake_factor)


func ai_handshake_progress(channel_index: int) -> float:
	if channel_index < 0 or channel_index >= data.channels.size():
		return 0.0
	var channel: Dictionary = data.channels[channel_index]
	if channel.get("state", "") != "AI_HANDSHAKE":
		return 0.0
	var started := int(channel.get("ai_phase_started_ms", 0))
	var due := int(channel.get("ai_due_ms", 0))
	if started <= 0 or due <= started:
		return 0.0
	return clampf(float(Time.get_ticks_msec() - started) / float(due - started), 0.0, 1.0)


func ai_handshake_remaining(channel_index: int) -> float:
	if channel_index < 0 or channel_index >= data.channels.size():
		return 0.0
	var channel: Dictionary = data.channels[channel_index]
	if channel.get("state", "") != "AI_HANDSHAKE":
		return 0.0
	return maxf(0.0, float(int(channel.get("ai_due_ms", 0)) - Time.get_ticks_msec()) / 1000.0)


func estimated_automation_cycle(node: Dictionary, ai_id: String) -> float:
	if node.is_empty() or ai_id == "":
		return 0.0
	var decision_time := _ai_decision_time(ai_id, node)
	var handshake_time := _ai_handshake_time(ai_id, node)
	var averages: Dictionary = node.get("benchmark", {}).get("average_guesses", {})
	var average_guesses := float(averages.get(ai_id, node.get("benchmark", {}).get("average", 1.0)))
	return handshake_time + average_guesses * decision_time + 0.7


func _process_ai() -> void:
	var now := Time.get_ticks_msec()
	for index in range(data.channels.size()):
		var channel: Dictionary = data.channels[index]
		if channel.state == "AI_HANDSHAKE" and int(channel.ai_due_ms) > 0 and now >= int(channel.ai_due_ms):
			channel.state = "AI_THINKING"
			channel.ai_phase_started_ms = now
			channel.ai_due_ms = now + int(_ai_decision_time(channel.ai_id, channel_node(index)) * 1000.0)
			changed.emit("channel:%d:handshake" % index)
			return
		if channel.state == "AI_THINKING" and int(channel.ai_due_ms) > 0 and now >= int(channel.ai_due_ms):
			var node := channel_node(index)
			var ai_def := ai_definition(channel.ai_id)
			var guess := AISolver.choose_guess(ai_def.get("strategy", "brute_force"), node, channel.history)
			if guess == "":
				_prepare_failure(index)
				changed.emit("channel:%d:ai_guess" % index)
			else:
				submit_guess(index, guess, channel.ai_id)
			return
		if channel.state in ["SOLVED", "FAILED"] and int(channel.resolution_due_ms) > 0 and now >= int(channel.resolution_due_ms):
			if channel_has_auto_settlement(index):
				claim_resolution(index)
				return


func has_tech(tech_id: String) -> bool:
	return tech_level(tech_id) > 0


func tech_level(tech_id: String) -> int:
	if data.get("tech_levels", {}) is Dictionary and data.tech_levels.has(tech_id):
		return maxi(0, int(data.tech_levels.get(tech_id, 0)))
	return 1 if tech_id in data.get("purchased_tech", []) else 0


func tech_max_level(tech_id: String) -> int:
	var definition: Dictionary = config.tech.get(tech_id, {})
	if bool(definition.get("infinite", false)):
		return -1
	return maxi(1, int(definition.get("max_level", 1)))


func tech_level_cap(tech_id: String) -> int:
	var maximum := tech_max_level(tech_id)
	if maximum < 0:
		return maximum
	var definition: Dictionary = config.tech.get(tech_id, {})
	if bool(definition.get("level_cap_by_channels", false)):
		maximum = mini(maximum, unlocked_channel_count())
	if bool(definition.get("level_cap_by_terminal", false)):
		maximum = mini(maximum, int(data.get("terminal_level", 1)))
	return maximum


func is_tech_maxed(tech_id: String) -> bool:
	var maximum := tech_max_level(tech_id)
	return maximum > 0 and tech_level(tech_id) >= maximum


func channel_has_auto_settlement(channel_index: int) -> bool:
	var rank := channel_priority_rank(channel_index)
	return rank > 0 and rank <= tech_level("auto_settle")


func channel_has_auto_restock(channel_index: int) -> bool:
	return node_has_auto_restock(channel_node(channel_index))


func node_has_auto_restock(node: Dictionary) -> bool:
	return not node.is_empty() and int(node.get("terminal_level", 1)) <= tech_level("auto_restock")


func next_tech_cost(tech_id: String, level_override := -1) -> Dictionary:
	var definition: Dictionary = config.tech.get(tech_id, {})
	if definition.is_empty():
		return {"energy": 0, "fragments": 0}
	var level := tech_level(tech_id) if level_override < 0 else maxi(0, level_override)
	if tech_max_level(tech_id) == 1:
		return {"energy": int(definition.get("energy_cost", 0)), "fragments": int(definition.get("fragment_cost", 0))}
	var rounding := maxi(1, int(definition.get("cost_rounding", 1)))
	var growth := maxf(1.0, float(definition.get("cost_growth", 1.0)))
	var exponential_energy := float(definition.get("energy_cost", 0)) * pow(growth, level)
	var raw_energy := exponential_energy
	var tier_cost_ratio := float(definition.get("tier_cost_ratio", 0.0))
	var channel_cost_ratio := float(definition.get("channel_cost_ratio", 0.0))
	var channel_costs: Array = config.data.get("economy", {}).get("channel_costs", [])
	if level > 0 and tier_cost_ratio > 0.0:
		var tier_spec: Dictionary = config.terminal(level + 1)
		raw_energy = maxf(exponential_energy, float(tier_spec.get("energy_cost", 0)) * tier_cost_ratio)
	elif level > 0 and channel_cost_ratio > 0.0 and level < channel_costs.size():
		raw_energy = float(channel_costs[level]) * channel_cost_ratio
	var energy := int(round(raw_energy / float(rounding))) * rounding
	if raw_energy > 0.0:
		energy = maxi(rounding, energy)
	var fragment_growth := maxf(1.0, float(definition.get("fragment_cost_growth", 1.0)))
	var fragments := int(ceil(float(definition.get("fragment_cost", 0)) * pow(fragment_growth, level)))
	return {"energy": energy, "fragments": fragments}


func tech_purchase_preview(tech_id: String, purchase_all: bool) -> Dictionary:
	var level := tech_level(tech_id)
	var limit := tech_level_cap(tech_id)
	var energy := 0
	var fragments := 0
	var levels := 0
	while limit < 0 or level < limit:
		var cost := next_tech_cost(tech_id, level)
		if energy + int(cost.energy) > int(data.energy) or fragments + int(cost.fragments) > int(data.fragments):
			break
		energy += int(cost.energy)
		fragments += int(cost.fragments)
		level += 1
		levels += 1
		if not purchase_all:
			break
	return {"levels": levels, "energy": energy, "fragments": fragments}


func purchase_tech(tech_id: String) -> void:
	var definition: Dictionary = config.tech.get(tech_id, {})
	if definition.is_empty() or is_tech_maxed(tech_id):
		return
	if int(data.terminal_level) < int(definition.get("terminal_level", 1)):
		notice.emit("终端等级不足。", "error")
		return
	for requirement in definition.get("requires", []):
		if not has_tech(requirement):
			notice.emit("前置科技尚未完成。", "error")
			return
	var starting_level := tech_level(tech_id)
	var maximum := tech_max_level(tech_id)
	var current_cap := tech_level_cap(tech_id)
	if current_cap > 0 and starting_level >= current_cap:
		if bool(definition.get("level_cap_by_terminal", false)):
			notice.emit("请先升级终端以覆盖更高层级节点。", "info")
		else:
			notice.emit("请先建立更多解译通道。", "info")
		return
	var buy_max := bool(data.settings.get("bulk_tech_purchase", false)) and maximum != 1
	var preview := tech_purchase_preview(tech_id, buy_max)
	var purchased_levels := int(preview.levels)
	if purchased_levels <= 0:
		notice.emit("研究资源不足。", "error")
		return
	data.energy -= int(preview.energy)
	data.fragments -= int(preview.fragments)
	var level := starting_level + purchased_levels
	data.tech_levels[tech_id] = level
	if maximum == 1 and not tech_id in data.purchased_tech:
		data.purchased_tech.append(tech_id)
	if starting_level == 0:
		var unlocked_ai: String = definition.get("unlocks_ai", "")
		if unlocked_ai != "" and not unlocked_ai in data.unlocked_ai:
			data.unlocked_ai.append(unlocked_ai)
	if maximum == 1:
		notice.emit("研究完成：%s。" % definition.name, "success")
	elif purchased_levels > 1:
		notice.emit("%s 本次提升 %d 级，当前 Lv.%d。" % [definition.name, purchased_levels, level], "success")
	else:
		notice.emit("%s 提升至 Lv.%d。" % [definition.name, level], "success")
	_commit("tech")


func set_bulk_tech_purchase(enabled: bool) -> void:
	data.settings.bulk_tech_purchase = enabled
	_commit("settings")


func _effect_matches(effect: Dictionary, node: Dictionary, ai_id: String) -> bool:
	if int(data.get("cycle", 1)) < int(effect.get("min_cycle", 1)):
		return false
	var ai_ids: Array = effect.get("ai_ids", [])
	if not ai_ids.is_empty() and not ai_id in ai_ids:
		return false
	var node_ids: Array = effect.get("node_ids", [])
	if not node_ids.is_empty() and not node.get("id", "") in node_ids:
		return false
	var required_tags: Array = effect.get("node_tags", [])
	if not required_tags.is_empty():
		var node_tags: Array = node.get("tags", [])
		var matched := false
		for tag in required_tags:
			if tag in node_tags:
				matched = true
				break
		if not matched:
			return false
	if int(effect.get("requires_active_channels", 0)) > _active_automation_count():
		return false
	return true


func _active_automation_count() -> int:
	var count := 0
	for channel: Dictionary in data.get("channels", []):
		if channel.get("ai_id", "") != "" and not channel.get("state", "") in ["EMPTY", "PAUSED", "SOLVED", "FAILED", "ABANDONED"]:
			count += 1
	return count


func _collection_effect_values(effect_type: String, node: Dictionary = {}, ai_id := "") -> Array[float]:
	var values: Array[float] = []
	for loot_id in config.loot:
		if int(data.get("loot", {}).get(loot_id, 0)) <= 0:
			continue
		var item: Dictionary = config.loot[loot_id]
		var series_id: String = item.get("series", "")
		var series_multiplier := 1.0
		if series_id in data.get("claimed_series", []):
			series_multiplier = float(config.series.get(series_id, {}).get("completed_effect_multiplier", 2.0))
		for effect: Dictionary in item.get("effects", []):
			if effect.get("type", "") == effect_type and _effect_matches(effect, node, ai_id):
				values.append(float(effect.get("value", 0.0)) * series_multiplier)
	return values


func _tech_effect_values(effect_type: String, node: Dictionary = {}, ai_id := "") -> Array[float]:
	var values: Array[float] = []
	for tech_id in config.tech:
		var level := tech_level(tech_id)
		if level <= 0:
			continue
		var definition: Dictionary = config.tech.get(tech_id, {})
		for effect: Dictionary in definition.get("effects", []):
			if effect.get("type", "") == effect_type and _effect_matches(effect, node, ai_id):
				values.append(float(effect.get("value", 0.0)) * float(level))
	return values


func _effect_values(effect_type: String, node: Dictionary = {}, ai_id := "") -> Array[float]:
	var values := _collection_effect_values(effect_type, node, ai_id)
	values.append_array(_tech_effect_values(effect_type, node, ai_id))
	return values


func _collection_effect_sum(effect_type: String, node: Dictionary = {}, ai_id := "") -> float:
	var total := 0.0
	for value: float in _collection_effect_values(effect_type, node, ai_id):
		total += value
	return total


func _tech_effect_sum(effect_type: String, node: Dictionary = {}, ai_id := "") -> float:
	var total := 0.0
	for value: float in _tech_effect_values(effect_type, node, ai_id):
		total += value
	return total


func _effect_sum(effect_type: String, node: Dictionary = {}, ai_id := "") -> float:
	var total := 0.0
	for value: float in _effect_values(effect_type, node, ai_id):
		total += value
	return total


func _speed_factor(effect_type: String, node: Dictionary = {}, ai_id := "") -> float:
	var factor := 1.0
	for value: float in _effect_values(effect_type, node, ai_id):
		factor *= 1.0 - clampf(value, 0.0, 0.90)
	return factor


func prestige_multiplier() -> float:
	var prestige: Dictionary = config.data.get("prestige", {})
	var lifetime := float(data.get("lifetime_echo", 0))
	return 1.0 + float(prestige.get("multiplier_coefficient", 0.20)) * pow(lifetime, float(prestige.get("multiplier_exponent", 0.85)))


func preview_prestige_echo() -> int:
	var prestige: Dictionary = config.data.get("prestige", {})
	var score := float(data.get("run_score", 0))
	var divisor := maxf(float(prestige.get("score_divisor", 800.0)), 1.0)
	var base_echo := floori(sqrt(score / divisor))
	var bonus := 1.0 + _collection_effect_sum("prestige_bonus")
	return maxi(0, floori(float(base_echo) * bonus + float(data.get("echo_remainder", 0.0))))


func can_prestige() -> bool:
	var prestige: Dictionary = config.data.get("prestige", {})
	return int(data.get("terminal_level", 1)) >= int(prestige.get("unlock_terminal_level", 4)) \
		and bool(data.get("cycle_memory_core_solved", false)) \
		and int(data.get("run_score", 0)) >= prestige_target_score() \
		and preview_prestige_echo() > 0


func prestige_target_score() -> int:
	var prestige: Dictionary = config.data.get("prestige", {})
	var targets: Array = prestige.get("run_score_targets", [int(prestige.get("unlock_run_score", 24000))])
	if targets.is_empty():
		return int(prestige.get("unlock_run_score", 24000))
	var cycle_index := maxi(0, int(data.get("cycle", 1)) - 1)
	if cycle_index < targets.size():
		return int(targets[cycle_index])
	var multiplier := float(prestige.get("later_score_multiplier", 1.8))
	return int(round(float(targets[-1]) * pow(multiplier, cycle_index - targets.size() + 1) / 1000.0)) * 1000


func prestige() -> bool:
	if not can_prestige():
		notice.emit("零界回溯条件尚未满足。", "warning")
		return false
	var echo_gain := preview_prestige_echo()
	var prestige_config: Dictionary = config.data.get("prestige", {})
	var divisor := maxf(float(prestige_config.get("score_divisor", 800.0)), 1.0)
	var base_echo := floori(sqrt(float(data.get("run_score", 0)) / divisor))
	var raw_echo := float(base_echo) * (1.0 + _collection_effect_sum("prestige_bonus")) + float(data.get("echo_remainder", 0.0))
	var old_data := data
	data = _new_game_data()
	data.cycle = int(old_data.get("cycle", 1)) + 1
	data.echo = int(old_data.get("echo", 0)) + echo_gain
	data.echo_remainder = raw_echo - float(echo_gain)
	data.lifetime_echo = int(old_data.get("lifetime_echo", 0)) + echo_gain
	data.loot = old_data.get("loot", {}).duplicate(true)
	data.claimed_series = old_data.get("claimed_series", []).duplicate(true)
	data.series_pity = old_data.get("series_pity", {}).duplicate(true)
	data.memories = old_data.get("memories", []).duplicate(true)
	data.completed_node_types = old_data.get("completed_node_types", []).duplicate(true)
	data.settings = old_data.get("settings", {}).duplicate(true)
	data.statistics = old_data.get("statistics", {}).duplicate(true)
	data.total_energy = int(old_data.get("total_energy", 0))
	data.random_counter = int(old_data.get("random_counter", 1))
	data.tutorial_completed = true
	data.tutorial_step = "completed"
	data.channels[0].secret = _next_secret(node_definition("maintenance"))
	_reseed_uid_counter()
	_reschedule_compute()
	notice.emit("零界回溯完成：获得 %d 零界回声，永久能量倍率提升至 ×%.2f。" % [echo_gain, prestige_multiplier()], "success")
	_commit("prestige")
	return true


func next_prestige_echo_score() -> int:
	var prestige: Dictionary = config.data.get("prestige", {})
	var divisor := maxf(float(prestige.get("score_divisor", 800.0)), 1.0)
	var bonus := 1.0 + _collection_effect_sum("prestige_bonus")
	var remainder := float(data.get("echo_remainder", 0.0))
	var displayed := preview_prestige_echo()
	var base_echo := maxi(0, floori(sqrt(float(data.get("run_score", 0)) / divisor)))
	while floori(float(base_echo) * bonus + remainder) <= displayed:
		base_echo += 1
	return ceili(float(base_echo * base_echo) * divisor)


func _random_roll() -> float:
	var counter := int(data.random_counter)
	data.random_counter = counter + 1
	var rng := RandomNumberGenerator.new()
	rng.seed = int(config.data.get("seed", 1)) + counter * 13007
	return rng.randf()


func _roll_loot(node: Dictionary) -> void:
	var table_id: String = node.get("loot_table", "")
	var entries: Array = config.data.get("loot_tables", {}).get(table_id, [])
	var eligible_by_series: Dictionary = {}
	var found_by_series: Dictionary = {}
	var loot_bonus := _collection_effect_sum("loot_bonus", node)
	for entry: Dictionary in entries:
		if int(data.get("cycle", 1)) < int(entry.get("min_cycle", 1)):
			continue
		var loot_id: String = entry.get("id", "")
		var item: Dictionary = config.loot.get(loot_id, {})
		if item.is_empty():
			continue
		var series_id: String = item.get("series", "")
		if not eligible_by_series.has(series_id):
			eligible_by_series[series_id] = []
		eligible_by_series[series_id].append(loot_id)
		found_by_series[series_id] = bool(found_by_series.get(series_id, false))
		var series_def: Dictionary = config.series.get(series_id, {})
		var pity := int(data.series_pity.get(series_id, 0))
		var hard_pity := int(series_def.get("hard_pity", 0))
		var chance := float(entry.get("chance", 0.0)) * (1.0 + loot_bonus)
		if hard_pity > 0 and pity >= hard_pity / 2 and int(data.loot.get(loot_id, 0)) <= 0:
			chance *= pow(1.15, pity - hard_pity / 2 + 1)
		if _random_roll() <= minf(chance, 1.0) and _award_loot(loot_id):
			found_by_series[series_id] = true
	for series_id: String in eligible_by_series:
		if bool(found_by_series.get(series_id, false)):
			data.series_pity[series_id] = 0
			continue
		var next_pity := int(data.series_pity.get(series_id, 0)) + 1
		data.series_pity[series_id] = next_pity
		var hard_pity := int(config.series.get(series_id, {}).get("hard_pity", 0))
		if hard_pity <= 0 or next_pity < hard_pity:
			continue
		for loot_id: String in eligible_by_series[series_id]:
			if int(data.loot.get(loot_id, 0)) <= 0 and _award_loot(loot_id):
				data.series_pity[series_id] = 0


func _award_loot(loot_id: String) -> bool:
	var item: Dictionary = config.loot.get(loot_id, {})
	if item.is_empty():
		return false
	var current := int(data.loot.get(loot_id, 0))
	var is_unique := bool(item.get("unique", false))
	if current > 0 and is_unique:
		return false
	var is_new := current == 0
	data.statistics.loot_total = int(data.statistics.loot_total) + 1
	var should_dismantle := current > 0
	if should_dismantle:
		var fragments := int(item.get("fragment_value", 0))
		data.fragments += fragments
		data.statistics.duplicates_dismantled = int(data.statistics.duplicates_dismantled) + 1
		notice.emit("重复品 %s 已分解：+%d 计算碎片。" % [item.name, fragments], "info")
	else:
		data.loot[loot_id] = current + 1
		if current == 0:
			notice.emit("发现新战利品：%s [%s]。" % [item.name, item.rarity], "success")
			_unlock_memory("collection_guide")
	_check_series(item.get("series", ""))
	return is_new


func dismantle_duplicate(loot_id: String) -> void:
	var count := int(data.loot.get(loot_id, 0))
	var item: Dictionary = config.loot.get(loot_id, {})
	if count <= 1 or item.is_empty() or bool(item.get("unique", false)):
		return
	data.loot[loot_id] = count - 1
	var fragments := int(item.get("fragment_value", 0))
	data.fragments += fragments
	data.statistics.duplicates_dismantled = int(data.statistics.duplicates_dismantled) + 1
	notice.emit("已分解一件重复品：+%d 计算碎片。" % fragments, "info")
	_commit("loot")


func _check_series(series_id: String) -> void:
	if series_id == "" or series_id in data.claimed_series:
		return
	var required: Array[String] = []
	for item_id in config.loot:
		if config.loot[item_id].get("series", "") == series_id:
			required.append(item_id)
	for item_id in required:
		if int(data.loot.get(item_id, 0)) <= 0:
			return
	var series_def: Dictionary = config.series.get(series_id, {})
	data.claimed_series.append(series_id)
	var reward := int(series_def.get("reward_fragments", 0))
	data.fragments += reward
	_unlock_memory(series_def.get("memory", ""))
	notice.emit("收藏系列完成：%s，+%d 计算碎片。" % [series_def.get("name", series_id), reward], "success")


func _unlock_memory(memory_id: String) -> void:
	if memory_id == "" or memory_id in data.memories or not config.memories.has(memory_id):
		return
	data.memories.append(memory_id)


func set_setting(key: String, value: Variant) -> void:
	if not data.settings.has(key):
		return
	data.settings[key] = value
	_commit("settings")


func collected_unique_count() -> int:
	var count := 0
	for loot_id in data.loot:
		if int(data.loot[loot_id]) > 0:
			count += 1
	return count


func is_series_visible(series_def: Dictionary) -> bool:
	return int(data.get("cycle", 1)) >= int(series_def.get("min_cycle", 1))


func visible_series_count() -> int:
	var count := 0
	for series_def: Dictionary in config.data.get("series", []):
		if is_series_visible(series_def):
			count += 1
	return count


func visible_loot_count() -> int:
	var count := 0
	for item: Dictionary in config.data.get("loot", []):
		if is_series_visible(config.series.get(item.get("series", ""), {})):
			count += 1
	return count


func visible_collected_count() -> int:
	var count := 0
	for loot_id in data.loot:
		var item: Dictionary = config.loot.get(loot_id, {})
		if int(data.loot[loot_id]) > 0 and is_series_visible(config.series.get(item.get("series", ""), {})):
			count += 1
	return count


func total_inventory_count() -> int:
	return data.inventory.size()


func unlocked_channel_count() -> int:
	var count := 0
	for channel: Dictionary in data.channels:
		if bool(channel.unlocked):
			count += 1
	return count


func current_success_rate(node: Dictionary, ai_id: String) -> int:
	if int(node.get("attempt_limit", 0)) <= 0:
		return 100
	if ai_id == "probe":
		return 0
	var rates: Dictionary = node.get("benchmark", {}).get("success_rates", {})
	return int(rates.get("manual" if ai_id == "" else ai_id, 0))
