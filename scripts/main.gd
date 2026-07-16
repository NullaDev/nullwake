extends Control

const C_BG := Color("05090e")
const C_PANEL := Color("0a141b")
const C_PANEL_2 := Color("0d1d25")
const C_CYAN := Color("62f4e8")
const C_CYAN_DIM := Color("2d8d8a")
const C_TEXT := Color("d1e8e7")
const C_MUTED := Color("71908f")
const C_GREEN := Color("75f0a0")
const C_AMBER := Color("ffc766")
const C_RED := Color("ff7081")
const C_VIOLET := Color("b69cff")
const UI_FONT: FontFile = preload("res://SourceHanSansSC-Regular-2.otf")

var game: GameState
var current_page := "decrypt"
var selected_channel := 0
var shell: VBoxContainer
var top_bar: PanelContainer
var content_host: MarginContainer
var nav_bar: PanelContainer
var toast_panel: PanelContainer
var toast_label: Label
var toast_timer: Timer
var export_box: TextEdit
var guess_input: LineEdit
var decrypt_sidebar_box: VBoxContainer
var guess_drafts: Dictionary = {}
var _last_ai_refresh := 0


func _ready() -> void:
	set_process(true)
	theme = _make_theme()
	var backdrop := TerminalBackdrop.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	game = GameState.new()
	add_child(game)
	game.changed.connect(_on_game_changed)
	game.notice.connect(_show_notice)
	if not game.initialize():
		_show_fatal_error()
		return
	_build_shell()
	_rebuild_all()
	if game.data.tutorial_step == "awakening":
		_show_awakening()


func _process(delta: float) -> void:
	if game == null or game.data.is_empty():
		return
	game.tick(delta)
	var now := Time.get_ticks_msec()
	if current_page == "decrypt" and now - _last_ai_refresh > 500:
		_last_ai_refresh = now
		_update_top_values()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and game != null:
		game.save_now()


func _build_shell() -> void:
	shell = VBoxContainer.new()
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.add_theme_constant_override("separation", 12)
	add_child(shell)

	var outer_top := MarginContainer.new()
	outer_top.add_theme_constant_override("margin_left", 20)
	outer_top.add_theme_constant_override("margin_right", 20)
	outer_top.add_theme_constant_override("margin_top", 16)
	shell.add_child(outer_top)
	top_bar = _panel(C_PANEL, C_CYAN_DIM, 1)
	top_bar.custom_minimum_size.y = 66
	outer_top.add_child(top_bar)

	content_host = MarginContainer.new()
	content_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_host.add_theme_constant_override("margin_left", 20)
	content_host.add_theme_constant_override("margin_right", 20)
	shell.add_child(content_host)

	var outer_bottom := MarginContainer.new()
	outer_bottom.add_theme_constant_override("margin_left", 20)
	outer_bottom.add_theme_constant_override("margin_right", 20)
	outer_bottom.add_theme_constant_override("margin_bottom", 16)
	shell.add_child(outer_bottom)
	nav_bar = _panel(C_PANEL, C_CYAN_DIM, 1)
	nav_bar.custom_minimum_size.y = 58
	outer_bottom.add_child(nav_bar)

	toast_panel = _panel(Color("102329"), C_CYAN, 1)
	toast_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_panel.position = Vector2(-210, 86)
	toast_panel.size = Vector2(420, 50)
	toast_panel.z_index = 20
	toast_panel.visible = false
	add_child(toast_panel)
	toast_label = _label("", 15, C_TEXT)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_panel.add_child(toast_label)
	toast_timer = Timer.new()
	toast_timer.one_shot = true
	toast_timer.timeout.connect(func() -> void: toast_panel.visible = false)
	add_child(toast_timer)


func _make_theme() -> Theme:
	var result := Theme.new()
	result.default_font = UI_FONT
	result.default_font_size = 16
	result.set_color("font_color", "Label", C_TEXT)
	result.set_color("font_color", "Button", C_TEXT)
	result.set_color("font_hover_color", "Button", C_CYAN)
	result.set_color("font_pressed_color", "Button", C_BG)
	result.set_color("font_color", "LineEdit", C_CYAN)
	result.set_color("caret_color", "LineEdit", C_CYAN)
	result.set_color("font_placeholder_color", "LineEdit", C_MUTED)
	result.set_color("font_color", "RichTextLabel", C_TEXT)
	result.set_color("font_color", "CheckButton", C_TEXT)
	result.set_color("font_color", "OptionButton", C_TEXT)
	result.set_stylebox("normal", "Button", _style(Color("10242b"), C_CYAN_DIM, 1, 6))
	result.set_stylebox("hover", "Button", _style(Color("15343b"), C_CYAN, 1, 6))
	result.set_stylebox("pressed", "Button", _style(C_CYAN, C_CYAN, 1, 6))
	result.set_stylebox("disabled", "Button", _style(Color("0a1116"), Color("293a3e"), 1, 6))
	result.set_color("font_disabled_color", "Button", Color("40575a"))
	result.set_stylebox("normal", "LineEdit", _style(Color("071116"), C_CYAN_DIM, 1, 5))
	result.set_stylebox("focus", "LineEdit", _style(Color("071116"), C_CYAN, 2, 5))
	result.set_stylebox("normal", "TextEdit", _style(Color("071116"), C_CYAN_DIM, 1, 5))
	result.set_stylebox("focus", "TextEdit", _style(Color("071116"), C_CYAN, 2, 5))
	result.set_stylebox("normal", "OptionButton", _style(Color("10242b"), C_CYAN_DIM, 1, 5))
	return result


func _style(background: Color, border: Color, width := 1, radius := 4) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box


func _panel(background := C_PANEL, border := C_CYAN_DIM, width := 1) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(background, border, width, 7))
	return panel


func _label(text: String, size := 16, color := C_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


func _button(text: String, callback: Callable, disabled := false) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = disabled
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(callback)
	return button


func _section_title(kicker: String, title: String, description := "") -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(_label(kicker.to_upper(), 12, C_CYAN))
	box.add_child(_label(title, 27, C_TEXT))
	if description != "":
		var desc := _label(description, 14, C_MUTED)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(desc)
	return box


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _rebuild_all() -> void:
	_build_top_bar()
	_build_navigation()
	_build_current_page()


func _update_top_values() -> void:
	_build_top_bar()


func _build_top_bar() -> void:
	_clear(top_bar)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	top_bar.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	margin.add_child(row)
	var brand := VBoxContainer.new()
	brand.custom_minimum_size.x = 210
	brand.add_theme_constant_override("separation", -2)
	brand.add_child(_label("NULLWAKE", 22, C_CYAN))
	brand.add_child(_label("零界苏醒 · %s" % game.region_name(), 12, C_MUTED))
	row.add_child(brand)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_status_block("协议能量", str(int(game.data.energy)), C_GREEN))
	if int(game.data.compute_capacity) > 0 or not game.data.unlocked_ai.is_empty():
		row.add_child(_status_block("算力", "%d / %d" % [game.used_compute(), int(game.data.compute_capacity)], C_CYAN))
	if int(game.data.fragments) > 0 or int(game.data.terminal_level) >= 2:
		row.add_child(_status_block("计算碎片", str(int(game.data.fragments)), C_VIOLET))
	row.add_child(_status_block("节点库存", str(game.total_inventory_count()), C_AMBER))
	row.add_child(_status_block("终端", "T-%d" % int(game.data.terminal_level), C_TEXT))


func _status_block(title: String, value: String, color: Color) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 88
	box.add_theme_constant_override("separation", -2)
	var top := _label(title, 11, C_MUTED)
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(top)
	var bottom := _label(value, 18, color)
	bottom.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(bottom)
	return box


func _build_navigation() -> void:
	_clear(nav_bar)
	# The tutorial is a focused interaction. Showing a lone “01 解译” tab here
	# makes it look like the submit control, so navigation stays hidden until
	# the first protocol has been settled.
	nav_bar.visible = bool(game.data.tutorial_completed)
	if not bool(game.data.tutorial_completed):
		return
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	nav_bar.add_child(row)
	var pages := [
		["decrypt", "解译", "01"], ["nodes", "节点", "02"], ["inventory", "库存", "03"],
		["terminal", "终端", "04"], ["tech", "科技", "05"], ["collection", "收藏", "06"],
		["memory", "记忆", "07"], ["stats", "统计", "08"], ["settings", "设置", "09"]
	]
	for page: Array in pages:
		var button := _button("%s  %s" % [page[2], page[1]], func() -> void: _navigate(page[0]))
		button.custom_minimum_size = Vector2(118, 40)
		if current_page == page[0]:
			button.add_theme_stylebox_override("normal", _style(Color("17363b"), C_CYAN, 1, 6))
			button.add_theme_color_override("font_color", C_CYAN)
		row.add_child(button)


func _navigate(page: String) -> void:
	current_page = page
	_build_navigation()
	_build_current_page()


func _build_current_page() -> void:
	_clear(content_host)
	match current_page:
		"decrypt": _build_decrypt_page()
		"nodes": _build_nodes_page()
		"inventory": _build_inventory_page()
		"terminal": _build_terminal_page()
		"tech": _build_tech_page()
		"collection": _build_collection_page()
		"memory": _build_memory_page()
		"stats": _build_stats_page()
		"settings": _build_settings_page()


func _on_game_changed(reason: String) -> void:
	selected_channel = clampi(selected_channel, 0, game.data.channels.size() - 1)
	var changed_channel := _channel_from_reason(reason)
	if current_page == "decrypt" and changed_channel >= 0 and changed_channel != selected_channel:
		_build_top_bar()
		_refresh_decrypt_sidebar()
		return
	_rebuild_all()


func _channel_from_reason(reason: String) -> int:
	var parts := reason.split(":")
	if parts.size() >= 3 and parts[0] == "channel":
		return int(parts[1])
	return -1


func _show_notice(message: String, kind: String) -> void:
	if toast_panel == null:
		return
	toast_label.text = message
	var color := C_CYAN
	match kind:
		"success": color = C_GREEN
		"warning": color = C_AMBER
		"error": color = C_RED
	toast_panel.add_theme_stylebox_override("panel", _style(Color("102329"), color, 1, 6))
	toast_panel.visible = true
	toast_timer.start(3.4)


func _show_fatal_error() -> void:
	var label := _label("CONFIGURATION FAILURE\n无法读取游戏配置。", 24, C_RED)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(label)


func _build_decrypt_page() -> void:
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	content_host.add_child(layout)
	var sidebar := _panel(C_PANEL, Color("244b50"), 1)
	sidebar.custom_minimum_size.x = 250
	layout.add_child(sidebar)
	var side_margin := MarginContainer.new()
	side_margin.add_theme_constant_override("margin_left", 12)
	side_margin.add_theme_constant_override("margin_right", 12)
	side_margin.add_theme_constant_override("margin_top", 14)
	side_margin.add_theme_constant_override("margin_bottom", 14)
	sidebar.add_child(side_margin)
	decrypt_sidebar_box = VBoxContainer.new()
	decrypt_sidebar_box.add_theme_constant_override("separation", 8)
	side_margin.add_child(decrypt_sidebar_box)
	_refresh_decrypt_sidebar()

	var detail := _panel(Color("071117"), Color("244b50"), 1)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(detail)
	var detail_margin := MarginContainer.new()
	detail_margin.add_theme_constant_override("margin_left", 22)
	detail_margin.add_theme_constant_override("margin_right", 22)
	detail_margin.add_theme_constant_override("margin_top", 18)
	detail_margin.add_theme_constant_override("margin_bottom", 18)
	detail.add_child(detail_margin)
	if selected_channel >= game.data.channels.size():
		return
	var channel: Dictionary = game.data.channels[selected_channel]
	if not bool(channel.unlocked):
		_build_locked_channel(detail_margin, selected_channel)
	elif channel.node_ref.is_empty():
		_build_empty_channel(detail_margin, selected_channel)
	else:
		_build_loaded_channel(detail_margin, selected_channel)


func _refresh_decrypt_sidebar() -> void:
	if not is_instance_valid(decrypt_sidebar_box):
		return
	_clear(decrypt_sidebar_box)
	decrypt_sidebar_box.add_child(_label("DECRYPTION CHANNELS", 12, C_CYAN))
	decrypt_sidebar_box.add_child(_label("解译通道", 23, C_TEXT))
	var divider := HSeparator.new()
	divider.add_theme_color_override("separator", Color("244b50"))
	decrypt_sidebar_box.add_child(divider)
	for index in range(game.data.channels.size()):
		var channel: Dictionary = game.data.channels[index]
		var node := game.channel_node(index)
		var node_name: String = "接口未解锁" if not bool(channel.unlocked) else ("空闲" if node.is_empty() else node.name)
		var status_color := C_MUTED
		if bool(channel.unlocked):
			status_color = _state_color(channel.state)
		var button := _button("%02d  %s\n     %s" % [index + 1, node_name, _state_name(channel.state)], func() -> void:
			selected_channel = index
			_build_current_page()
		)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 62
		button.add_theme_color_override("font_color", status_color if selected_channel == index else C_TEXT)
		if selected_channel == index:
			button.add_theme_stylebox_override("normal", _style(Color("122d33"), status_color, 1, 5))
		decrypt_sidebar_box.add_child(button)
	var help := _label("每条通道拥有独立密码、历史和 AI。算力不足时按通道编号排队。", 12, C_MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.size_flags_vertical = Control.SIZE_EXPAND_FILL
	help.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	decrypt_sidebar_box.add_child(help)


func _build_locked_channel(parent: Control, index: int) -> void:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(box)
	box.add_child(_label("CHANNEL %02d // INTERFACE LOCKED" % (index + 1), 14, C_AMBER))
	var title := _label("通道接口尚未建立", 28, C_TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var spec := game.terminal_spec()
	var costs: Array = game.config.data.economy.channel_costs
	var cost := int(costs[index]) if index < costs.size() else 0
	var info := _label("当前终端允许 %d 条连接。建立该通道需要 %d 协议能量。" % [int(spec.max_channels), cost], 15, C_MUTED)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(info)
	var button := _button("建立解译通道 · %d E" % cost, game.purchase_channel, index >= int(spec.max_channels))
	button.custom_minimum_size = Vector2(260, 48)
	box.add_child(button)


func _build_empty_channel(parent: Control, index: int) -> void:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	parent.add_child(box)
	box.add_child(_label("CHANNEL %02d // EMPTY" % (index + 1), 14, C_CYAN))
	var glyph := _label("[      NO CARRIER      ]", 25, C_CYAN_DIM)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(glyph)
	var text := _label("该通道没有接入协议节点。可接入永久维护协议，或从库存选择未启动节点。", 16, C_MUTED)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 10)
	actions.add_child(_button("接入基础维护协议", func() -> void: game.load_permanent("maintenance", index)))
	actions.add_child(_button("打开节点库存", func() -> void: _navigate("inventory")))
	box.add_child(actions)


func _build_loaded_channel(parent: Control, index: int) -> void:
	var channel: Dictionary = game.data.channels[index]
	var node := game.channel_node(index)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 11)
	parent.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_child(_label("CHANNEL %02d  //  %s" % [index + 1, node.code], 12, C_CYAN))
	title_box.add_child(_label(node.name, 25, C_TEXT))
	header.add_child(title_box)
	var status_text := "!LOCKED" if bool(channel.started) and node.ownership != "permanent" else _state_name(channel.state)
	var status := _label(status_text, 18, _state_color(channel.state))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(status)

	if not bool(game.data.tutorial_completed) and game.data.tutorial_step != "claim_reward":
		box.add_child(_tutorial_callout())

	var metrics := GridContainer.new()
	metrics.columns = 5
	metrics.add_theme_constant_override("h_separation", 18)
	metrics.add_theme_constant_override("v_separation", 2)
	box.add_child(metrics)
	metrics.add_child(_metric("规则", "%d 位 / %d 进制" % [int(node.length), int(node.radix)]))
	metrics.add_child(_metric("节点", _ownership_name(node)))
	var attempts := "∞"
	if int(node.attempt_limit) > 0:
		attempts = "%d / %d" % [channel.history.size(), int(node.attempt_limit)]
	metrics.add_child(_metric("尝试", attempts))
	metrics.add_child(_metric("预计奖励", "%d E" % int(node.reward)))
	var ai_name := "手动"
	if channel.ai_id != "":
		ai_name = game.ai_definition(channel.ai_id).name
	metrics.add_child(_metric("控制", ai_name))

	var log_panel := _panel(Color("03080b"), Color("1d3c40"), 1)
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(log_panel)
	var log := RichTextLabel.new()
	log.bbcode_enabled = true
	log.scroll_active = true
	log.scroll_following = true
	log.custom_minimum_size.y = 185
	log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log.add_theme_font_size_override("normal_font_size", 16)
	log.text = _history_text(channel, node)
	log_panel.add_child(log)

	if channel.state in ["SOLVED", "FAILED", "ABANDONED"]:
		var result_row := HBoxContainer.new()
		result_row.alignment = BoxContainer.ALIGNMENT_CENTER
		var result_text := "* 协议验证成功" if channel.state == "SOLVED" else "X 节点连接失败"
		result_row.add_child(_label(result_text, 18, C_GREEN if channel.state == "SOLVED" else C_RED))
		result_row.add_child(_button("结算并继续", func() -> void: game.claim_resolution(index)))
		box.add_child(result_row)
	elif channel.state == "PAUSED":
		var paused := _label("|| 通道已暂停。密码、历史与剩余尝试均已保留。", 16, C_AMBER)
		paused.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(paused)
	else:
		box.add_child(_guess_controls(index, node, channel))

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	box.add_child(controls)
	var ai_select := OptionButton.new()
	ai_select.custom_minimum_size.x = 220
	ai_select.add_item("手动控制")
	ai_select.set_item_metadata(0, "")
	var selected_ai_index := 0
	for ai_id in game.data.unlocked_ai:
		var definition := game.ai_definition(ai_id)
		if definition.is_empty():
			continue
		ai_select.add_item("%s · %d 算力" % [definition.name, int(definition.compute_cost)])
		var option_index := ai_select.item_count - 1
		ai_select.set_item_metadata(option_index, ai_id)
		if ai_id == channel.ai_id:
			selected_ai_index = option_index
	ai_select.select(selected_ai_index)
	ai_select.item_selected.connect(func(option: int) -> void: game.assign_ai(index, ai_select.get_item_metadata(option)))
	controls.add_child(ai_select)
	controls.add_child(_button("继续" if channel.state == "PAUSED" else "暂停", func() -> void: game.toggle_pause(index), channel.state in ["SOLVED", "FAILED", "ABANDONED"]))
	var action_text := "放弃节点" if bool(channel.started) else "卸载节点"
	controls.add_child(_button(action_text, func() -> void: _request_remove_node(index)))
	var control_spacer := Control.new()
	control_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(control_spacer)
	if int(node.attempt_limit) > 0:
		var rate_ai: String = channel.ai_id if channel.ai_id != "" else ""
		controls.add_child(_label("预计成功率 %d%%" % game.current_success_rate(node, rate_ai), 13, C_AMBER))


func _metric(title: String, value: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_label(title, 11, C_MUTED))
	box.add_child(_label(value, 15, C_TEXT))
	return box


func _tutorial_callout() -> PanelContainer:
	var panel := _panel(Color("102a25"), C_GREEN, 2)
	var step: String = game.data.tutorial_step
	var tutorial: Dictionary = game.config.data.get("tutorial", {})
	var text: String = tutorial.get("first_prompt", "请输入引导协议。")
	if step == "solve_hint":
		text = tutorial.get("solve_prompt", "根据反馈重新排列协议。")
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 3)
	panel.add_child(copy)
	copy.add_child(_label("GUIDED INPUT // 操作引导", 11, C_GREEN))
	var label := _label(text, 14, C_TEXT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(label)
	return panel


func _guess_controls(index: int, node: Dictionary, channel: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	guess_input = LineEdit.new()
	guess_input.max_length = int(node.length)
	guess_input.placeholder_text = "输入 %d 位协议" % int(node.length)
	var saved_draft: String = str(guess_drafts.get(index, ""))
	if saved_draft.length() <= int(node.length):
		guess_input.text = saved_draft
		guess_input.caret_column = saved_draft.length()
	guess_input.custom_minimum_size = Vector2(250, 44)
	guess_input.editable = channel.ai_id == "" and channel.state not in ["AI_THINKING", "AI_PENDING"]
	guess_input.text_changed.connect(func(value: String) -> void: guess_drafts[index] = value)
	guess_input.text_submitted.connect(func(_value: String) -> void: _submit_manual(index))
	row.add_child(guess_input)
	for symbol in range(int(node.radix)):
		var digit := str(symbol)
		var key := _button(digit, func() -> void:
			if guess_input != null and guess_input.text.length() < int(node.length):
				guess_input.text += digit
				guess_input.caret_column = guess_input.text.length()
		, not guess_input.editable)
		key.custom_minimum_size = Vector2(42, 42)
		row.add_child(key)
	row.add_child(_button("清除", func() -> void: guess_input.clear(), not guess_input.editable))
	row.add_child(_button("提交猜测", func() -> void: _submit_manual(index), not guess_input.editable))
	if channel.state == "AI_PENDING":
		row.add_child(_label("等待可用算力…", 14, C_AMBER))
	elif channel.state == "AI_THINKING":
		row.add_child(_label("AI 正在推演候选空间…", 14, C_CYAN))
	return row


func _submit_manual(index: int) -> void:
	if guess_input == null:
		return
	var draft := guess_input.text
	guess_drafts.erase(index)
	if not game.submit_guess(index, draft, "manual"):
		guess_drafts[index] = draft
		if is_instance_valid(guess_input):
			guess_input.text = draft
			guess_input.caret_column = draft.length()


func _history_text(channel: Dictionary, node: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("[color=#2d8d8a]> LINK %s / %d-SYMBOL RADIX-%d[/color]" % [node.code, int(node.length), int(node.radix)])
	var in_tutorial := not bool(game.data.tutorial_completed)
	var tutorial: Dictionary = game.config.data.get("tutorial", {})
	if channel.history.is_empty():
		if in_tutorial:
			var first_target: String = tutorial.get("first_guess", "100")
			lines.append("[color=#75f0a0]! GUIDE INPUT  >  %s[/color]" % "  ".join(first_target.split("")))
		else:
			lines.append("[color=#71908f]< NO HANDSHAKE DATA[/color]")
			lines.append("[color=#62f4e8]> _[/color]")
	else:
		for record: Dictionary in channel.history:
			var feedback: Dictionary = record.feedback
			var exact_text := "?" if int(feedback.exact) < 0 else str(int(feedback.exact))
			var misplaced_text := "?" if int(feedback.misplaced) < 0 else str(int(feedback.misplaced))
			var actor := "MAN" if record.operator == "manual" else "AI"
			lines.append("[color=#d1e8e7]> %s[/color]  [color=#71908f][%s][/color]" % [record.guess, actor])
			lines.append("[color=#75f0a0]< 位置正确:%s  数字错位:%s[/color]" % [exact_text, misplaced_text])
		if in_tutorial and channel.history.size() == 1 and game.data.tutorial_step == "solve_hint":
			lines.append("")
			lines.append("[color=#ffc766]// FEEDBACK EXPLANATION / 本次教学仅显示一次[/color]")
			lines.append("[color=#d1e8e7]%s[/color]" % tutorial.get("exact_explanation", "位置正确表示数字与位置均正确。"))
			lines.append("[color=#d1e8e7]%s[/color]" % tutorial.get("misplaced_explanation", "数字错位表示数字存在，但位置不正确。"))
			var next_target: String = tutorial.get("solution_guess", "001")
			lines.append("[color=#75f0a0]! NEXT INPUT   >  %s[/color]" % "  ".join(next_target.split("")))
		elif in_tutorial and game.data.tutorial_step == "claim_reward" and channel.state == "SOLVED":
			lines.append("")
			lines.append("[color=#75f0a0]* PROTOCOL VERIFIED / 协议验证成功[/color]")
			lines.append("[color=#ffc766]! GUIDE  >  %s[/color]" % tutorial.get("claim_prompt", "请点击“结算并继续”领取奖励。"))
	if bool(channel.started) and node.ownership != "permanent":
		lines.append("[color=#ffc766]! NODE LOCKED / 结算前不可移出[/color]")
	return "\n".join(lines)


func _state_name(state: String) -> String:
	return {
		"LOCKED": "未解锁", "EMPTY": "空闲", "READY": "等待输入", "WAITING_FOR_INPUT": "等待输入",
		"AI_PENDING": "算力排队", "AI_THINKING": "AI 运行中", "RESOLVING_GUESS": "校验中",
		"SOLVED": "已破解", "FAILED": "失败", "ABANDONED": "已放弃", "PAUSED": "已暂停"
	}.get(state, state)


func _state_color(state: String) -> Color:
	if state in ["SOLVED", "READY", "WAITING_FOR_INPUT"]:
		return C_GREEN
	if state in ["FAILED", "ABANDONED"]:
		return C_RED
	if state in ["AI_PENDING", "PAUSED"]:
		return C_AMBER
	if state == "AI_THINKING":
		return C_CYAN
	return C_MUTED


func _ownership_name(node: Dictionary) -> String:
	match node.get("ownership", "consumable"):
		"permanent": return "永久"
		"unique": return "唯一 / 受保护"
	if node.get("usage", "single") == "limited":
		return "有限次数"
	return "一次性消耗"


func _request_remove_node(index: int) -> void:
	var channel: Dictionary = game.data.channels[index]
	if not bool(channel.started):
		game.unload_node(index)
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "确认销毁已启动节点"
	dialog.dialog_text = "该节点已经启动。放弃后将无法恢复，也不会返还购买费用。"
	dialog.ok_button_text = "确认放弃"
	dialog.cancel_button_text = "继续破解"
	dialog.confirmed.connect(func() -> void: game.abandon_node(index))
	dialog.close_requested.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(470, 190))


func _page_scaffold(kicker: String, title: String, description: String) -> VBoxContainer:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	content_host.add_child(root)
	root.add_child(_section_title(kicker, title, description))
	return root


func _scroll_list(parent: VBoxContainer) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	return list


func _build_nodes_page() -> void:
	var root := _page_scaffold("NODE CATALOG", "协议节点目录", "购买前检查兼容性、消耗规则与失败损失。未启动节点可按半价回收。")
	var list := _scroll_list(root)
	for node: Dictionary in game.config.data.nodes:
		list.add_child(_node_catalog_card(node))


func _node_catalog_card(node: Dictionary) -> PanelContainer:
	var compatible := game.is_compatible(node)
	var border := C_CYAN_DIM if compatible else Color("3a4245")
	if node.risk in ["高", "异常"]:
		border = C_AMBER if compatible else Color("4b4231")
	var card := _panel(C_PANEL, border, 1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	card.add_child(row)
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 4)
	row.add_child(main)
	var heading := HBoxContainer.new()
	heading.add_child(_label(node.name, 19, C_TEXT if compatible else C_MUTED))
	heading.add_child(_label("  %s" % node.code, 12, C_CYAN_DIM))
	heading.add_child(_label("  [%s风险]" % node.risk, 12, C_RED if node.risk == "异常" else (C_AMBER if node.risk == "高" else C_MUTED)))
	main.add_child(heading)
	var tags := "%s · %d位%d进制 · %s · %s" % [
		_ownership_name(node), int(node.length), int(node.radix),
		"无限尝试" if int(node.attempt_limit) == 0 else "%d 次尝试" % int(node.attempt_limit),
		"允许重复" if bool(node.allow_duplicates) else "禁止重复"
	]
	main.add_child(_label(tags, 13, C_CYAN_DIM))
	var description := _label(node.description, 14, C_MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.add_child(description)
	var details := "推荐 AI：%s  ·  成功奖励：%d E" % [game.ai_definition(node.recommended_ai).get("name", "手动"), int(node.reward)]
	if game.has_tech("risk_analysis") or int(game.data.terminal_level) >= 3:
		details += "  ·  基准：平均 %.1f / 最坏 %d  ·  %s" % [float(node.benchmark.average), int(node.benchmark.worst), node.benchmark.solver]
	main.add_child(_label(details, 12, C_MUTED))
	var action := VBoxContainer.new()
	action.custom_minimum_size.x = 190
	action.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(action)
	if node.ownership == "permanent":
		action.add_child(_label("永久持有", 14, C_GREEN))
		action.add_child(_button("接入当前通道", func() -> void:
			game.load_permanent(node.id, selected_channel)
			_navigate("decrypt")
		, not compatible))
	else:
		var unique_owned: bool = node.ownership == "unique" and (node.id in game.data.unique_completed or game._owns_node_type(node.id))
		var free_grant_owned: bool = game.has_free_grant(node.id)
		action.add_child(_label("%d E" % int(node.cost), 21, C_GREEN))
		var button_text := "已取得" if unique_owned else ("先使用免费节点" if free_grant_owned else "购买节点")
		action.add_child(_button(button_text, func() -> void: game.buy_node(node.id), unique_owned or free_grant_owned))
		if not compatible:
			action.add_child(_label("需终端 T-%d" % int(node.terminal_level), 12, C_AMBER))
	return card


func _build_inventory_page() -> void:
	var root := _page_scaffold("NODE INVENTORY", "节点库存", "库存中的节点尚未启动。接入通道不会产生损耗，第一次猜测后才会锁定。")
	var list := _scroll_list(root)
	if game.data.inventory.is_empty():
		var empty := _panel(C_PANEL, C_CYAN_DIM, 1)
		var empty_label := _label("库存为空。可从节点目录购买消耗型节点。", 16, C_MUTED)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.custom_minimum_size.y = 100
		empty.add_child(empty_label)
		list.add_child(empty)
		return
	for instance: Dictionary in game.data.inventory:
		var node := game.node_definition(instance.def_id)
		var card := _panel(C_PANEL, C_AMBER if int(instance.locked_channel) >= 0 else C_CYAN_DIM, 1)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		card.add_child(row)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_child(_label("%s  //  %s" % [node.name, node.code], 18, C_TEXT))
		var usage := "剩余有效次数：%d" % int(instance.remaining_uses)
		var free_grant: bool = bool(instance.get("free_grant", int(instance.get("acquired_cost", 0)) == 0))
		if int(instance.locked_channel) >= 0:
			usage += "  ·  已接入通道 %02d" % (int(instance.locked_channel) + 1)
		if free_grant:
			text.add_child(_label("%s · 教学免费取得 · 不可出售" % usage, 13, C_AMBER))
		else:
			text.add_child(_label("%s · 购入成本 %d E · 回收价值 %d E" % [usage, int(instance.acquired_cost), int(floor(int(instance.acquired_cost) * 0.5))], 13, C_MUTED))
		text.add_child(_label("终端要求 T-%d · 推荐 %s · %s风险" % [int(node.terminal_level), game.ai_definition(node.recommended_ai).name, node.risk], 12, C_CYAN_DIM))
		row.add_child(text)
		var locked := int(instance.locked_channel) >= 0
		row.add_child(_button("接入当前通道", func() -> void:
			game.load_inventory(instance.uid, selected_channel)
			_navigate("decrypt")
		, locked or not game.is_compatible(node)))
		row.add_child(_button("不可出售" if free_grant else "折价回收", func() -> void: game.sell_node(instance.uid), locked or free_grant or bool(node.get("protected", false))))
		list.add_child(card)


func _build_terminal_page() -> void:
	var root := _page_scaffold("TERMINAL CONTROL", "破解终端", "终端决定协议兼容范围；算力是 AI 可占用并释放的容量，通道决定并行连接数量。")
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	columns.add_child(left)
	var current := game.terminal_spec()
	left.add_child(_info_card("当前终端 // T-%d" % int(game.data.terminal_level), current.name,
		"最大 %d 位 · 最大 %d 进制 · %d 条通道接口\n限步协议：%s · 特殊协议：%s" % [int(current.max_length), int(current.max_radix), int(current.max_channels), _yes_no(current.limited_protocols), _yes_no(current.special_protocols)], C_CYAN))
	if int(game.data.terminal_level) < game.config.max_terminal_level():
		var next := game.config.terminal(int(game.data.terminal_level) + 1)
		var upgrade := _info_card("NEXT UPGRADE // T-%d" % int(next.level), next.name,
			"支持至 %d 位 / %d 进制，开放 %d 条接口\n成本：%d 协议能量 + %d 计算碎片" % [int(next.max_length), int(next.max_radix), int(next.max_channels), int(next.energy_cost), int(next.fragment_cost)], C_AMBER)
		var upgrade_button := _button("执行终端升级", game.purchase_terminal_upgrade)
		upgrade.get_child(0).add_child(upgrade_button)
		left.add_child(upgrade)
	else:
		left.add_child(_info_card("UPGRADE STATUS", "兼容矩阵已全部恢复", "当前版本的全部终端能力已经解锁。", C_GREEN))

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	columns.add_child(right)
	var compute := _info_card("COMPUTE CAPACITY", "算力矩阵", "总算力 %d · 已占用 %d · 可用 %d\n扩容后按通道优先级自动唤醒等待中的 AI。" % [int(game.data.compute_capacity), game.used_compute(), game.available_compute()], C_VIOLET)
	compute.get_child(0).add_child(_button("购买 +%d 算力 · %d E" % [int(game.config.data.economy.compute_purchase_amount), game.next_compute_cost()], game.purchase_compute))
	right.add_child(compute)
	var unlocked := game.unlocked_channel_count()
	var channel_costs: Array = game.config.data.economy.channel_costs
	var channel_cost := int(channel_costs[unlocked]) if unlocked < channel_costs.size() else 0
	var channel_card := _info_card("CHANNEL ARRAY", "解译通道阵列", "已建立 %d / %d 条通道。通道增加不会自动增加算力。" % [unlocked, int(current.max_channels)], C_GREEN)
	channel_card.get_child(0).add_child(_button("建立下一通道 · %d E" % channel_cost, game.purchase_channel, unlocked >= int(current.max_channels)))
	right.add_child(channel_card)


func _info_card(kicker: String, title: String, body: String, accent: Color) -> PanelContainer:
	var panel := _panel(C_PANEL, accent.darkened(0.35), 1)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	panel.add_child(box)
	box.add_child(_label(kicker, 11, accent))
	box.add_child(_label(title, 20, C_TEXT))
	var body_label := _label(body, 14, C_MUTED)
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body_label)
	return panel


func _yes_no(value: bool) -> String:
	return "支持" if value else "不可用"


func _build_tech_page() -> void:
	var root := _page_scaffold("RESEARCH MATRIX", "科技研究", "研究同时消耗协议能量与稀有的计算碎片。前置条件和终端要求必须全部满足。")
	var list := _scroll_list(root)
	var branches := ["自动化", "AI", "经济", "战利品", "终端"]
	for branch in branches:
		var branch_items: Array[Dictionary] = []
		for definition: Dictionary in game.config.data.tech:
			if definition.branch == branch:
				branch_items.append(definition)
		if branch_items.is_empty():
			continue
		list.add_child(_label("// %s 分支" % branch, 15, C_CYAN))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		list.add_child(grid)
		for definition in branch_items:
			grid.add_child(_tech_card(definition))


func _tech_card(definition: Dictionary) -> PanelContainer:
	var purchased := game.has_tech(definition.id)
	var available := int(game.data.terminal_level) >= int(definition.terminal_level)
	for requirement in definition.requires:
		available = available and game.has_tech(requirement)
	var accent := C_GREEN if purchased else (C_CYAN_DIM if available else Color("3a4245"))
	var card := _panel(C_PANEL, accent, 1)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.custom_minimum_size.y = 132
	box.add_theme_constant_override("separation", 5)
	card.add_child(box)
	var header := HBoxContainer.new()
	header.add_child(_label(definition.name, 18, C_GREEN if purchased else C_TEXT))
	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_spacer)
	header.add_child(_label("已完成" if purchased else "T-%d" % int(definition.terminal_level), 12, C_GREEN if purchased else C_MUTED))
	box.add_child(header)
	var description := _label(definition.description, 13, C_MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(description)
	var requirements := "成本 %d E + %d 碎片" % [int(definition.energy_cost), int(definition.fragment_cost)]
	if not definition.requires.is_empty():
		var names: Array[String] = []
		for requirement in definition.requires:
			names.append(game.config.tech[requirement].name)
		requirements += " · 前置：" + " / ".join(names)
	box.add_child(_label(requirements, 11, C_MUTED))
	box.add_child(_button("研究完成" if purchased else "开始研究", func() -> void: game.purchase_tech(definition.id), purchased or not available))
	return card


func _build_collection_page() -> void:
	var root := _page_scaffold("RECOVERED ARTIFACTS", "战利品收藏", "首次获得会登记图鉴；重复品可分解为计算碎片，唯一物品永远不会自动分解。")
	var summary := HBoxContainer.new()
	summary.add_theme_constant_override("separation", 10)
	summary.add_child(_label("已发现 %d / %d" % [game.collected_unique_count(), game.config.loot.size()], 15, C_GREEN))
	summary.add_child(_label("系列完成 %d / %d" % [game.data.claimed_series.size(), game.config.series.size()], 15, C_VIOLET))
	root.add_child(summary)
	var list := _scroll_list(root)
	for series_def: Dictionary in game.config.data.series:
		var items: Array[Dictionary] = []
		for item_def: Dictionary in game.config.data.loot:
			if item_def.series == series_def.id:
				items.append(item_def)
		var found := 0
		for item_def in items:
			if int(game.data.loot.get(item_def.id, 0)) > 0:
				found += 1
		var series_panel := _panel(C_PANEL, C_GREEN if series_def.id in game.data.claimed_series else C_CYAN_DIM, 1)
		var series_box := VBoxContainer.new()
		series_box.add_theme_constant_override("separation", 8)
		series_panel.add_child(series_box)
		var series_head := HBoxContainer.new()
		series_head.add_child(_label(series_def.name, 19, C_TEXT))
		var series_spacer := Control.new()
		series_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		series_head.add_child(series_spacer)
		series_head.add_child(_label("%d / %d · 系列奖励 %d 碎片" % [found, items.size(), int(series_def.reward_fragments)], 13, C_GREEN if found == items.size() else C_MUTED))
		series_box.add_child(series_head)
		var item_row := HBoxContainer.new()
		item_row.add_theme_constant_override("separation", 8)
		series_box.add_child(item_row)
		for item_def in items:
			item_row.add_child(_loot_item_card(item_def))
		list.add_child(series_panel)


func _loot_item_card(item: Dictionary) -> PanelContainer:
	var count := int(game.data.loot.get(item.id, 0))
	var found := count > 0
	var card := _panel(Color("071117"), _rarity_color(item.rarity) if found else Color("26353a"), 1)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(230, 115)
	card.add_child(box)
	box.add_child(_label(item.name if found else "[ 未识别轮廓 ]", 15, _rarity_color(item.rarity) if found else C_MUTED))
	box.add_child(_label(item.rarity if found else "???", 11, C_MUTED))
	var description := _label(item.description if found else "数据未登记。相关节点的战利品信号仍然模糊。", 12, C_MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(description)
	if found:
		var count_row := HBoxContainer.new()
		count_row.add_child(_label("持有 × %d" % count, 12, C_TEXT))
		if count > 1 and not bool(item.get("unique", false)):
			count_row.add_child(_button("分解重复品 +%d" % int(item.fragment_value), func() -> void: game.dismantle_duplicate(item.id)))
		box.add_child(count_row)
	return card


func _rarity_color(rarity: String) -> Color:
	return {"常见": C_TEXT, "稀有": C_CYAN, "精密": C_VIOLET, "异常": C_AMBER, "唯一": C_RED}.get(rarity, C_TEXT)


func _build_memory_page() -> void:
	var root := _page_scaffold("MEMORY ARCHIVE", "记忆档案", "记忆片段不会被消耗。部分记录可能在后续发现中获得不同解释。")
	var list := _scroll_list(root)
	if game.data.memories.is_empty():
		list.add_child(_info_card("ARCHIVE EMPTY", "没有可读取的记忆", "继续破解特殊节点、升级终端或完成收藏系列。", C_MUTED))
		return
	for memory_id in game.data.memories:
		var memory: Dictionary = game.config.memories.get(memory_id, {})
		if memory.is_empty():
			continue
		var card := _panel(C_PANEL, C_VIOLET.darkened(0.3), 1)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 7)
		card.add_child(box)
		box.add_child(_label(memory.title, 18, C_VIOLET))
		var text := _label(memory.text, 15, C_TEXT)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(text)
		list.add_child(card)


func _build_stats_page() -> void:
	var root := _page_scaffold("OPERATION TELEMETRY", "运行统计", "统计包含手动与 AI 操作、节点损耗和收藏进度；它们不会改变游戏数值。")
	var stats: Dictionary = game.data.statistics
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	root.add_child(grid)
	var values := [
		["总运行时间", _format_time(float(stats.play_time)), C_CYAN],
		["总猜测", str(int(stats.guesses)), C_TEXT],
		["破解完成", str(int(stats.solved)), C_GREEN],
		["手动破解", str(int(stats.manual_solved)), C_GREEN],
		["失败节点", str(int(stats.failed)), C_RED],
		["主动放弃", str(int(stats.abandoned)), C_AMBER],
		["当前连续成功", str(int(stats.current_streak)), C_CYAN],
		["最高连续成功", str(int(stats.best_streak)), C_VIOLET],
		["累计协议能量", str(int(game.data.total_energy)), C_GREEN],
		["购买消耗节点", str(int(stats.nodes_bought)), C_TEXT],
		["损失估值", "%d E" % int(stats.energy_lost), C_RED],
		["首次直接成功", str(int(stats.direct_success)), C_AMBER],
		["战利品总数", str(int(stats.loot_total)), C_VIOLET],
		["不同收藏品", str(game.collected_unique_count()), C_VIOLET],
		["重复品分解", str(int(stats.duplicates_dismantled)), C_TEXT],
		["解译通道", str(game.unlocked_channel_count()), C_CYAN]
	]
	for item: Array in values:
		var card := _panel(C_PANEL, Color("244b50"), 1)
		card.custom_minimum_size.y = 80
		var box := VBoxContainer.new()
		box.add_child(_label(item[0], 11, C_MUTED))
		box.add_child(_label(item[1], 22, item[2]))
		card.add_child(box)
		grid.add_child(card)
	var node_list := RichTextLabel.new()
	node_list.bbcode_enabled = true
	node_list.fit_content = true
	node_list.text = _node_stats_text(stats.node_stats)
	root.add_child(node_list)


func _node_stats_text(node_stats: Dictionary) -> String:
	var lines: Array[String] = ["[color=#62f4e8]// 节点表现[/color]"]
	if node_stats.is_empty():
		lines.append("[color=#71908f]尚无结算记录。[/color]")
	for node_id in node_stats:
		var record: Dictionary = node_stats[node_id]
		var name: String = game.node_definition(node_id).get("name", node_id)
		lines.append("%s   [color=#75f0a0]成功 %d[/color]   [color=#ff7081]失败 %d[/color]" % [name, int(record.solved), int(record.failed)])
	return "\n".join(lines)


func _format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%02d:%02d:%02d" % [total / 3600, (total % 3600) / 60, total % 60]


func _build_settings_page() -> void:
	var root := _page_scaffold("SYSTEM CONFIGURATION", "设置与存档", "存档自动写入本地。导出码包含当前谜题、通道状态和结算令牌，可用于迁移进度。")
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)
	var preferences := _panel(C_PANEL, C_CYAN_DIM, 1)
	preferences.custom_minimum_size.x = 370
	columns.add_child(preferences)
	var pref_box := VBoxContainer.new()
	pref_box.add_theme_constant_override("separation", 14)
	preferences.add_child(pref_box)
	pref_box.add_child(_label("INTERFACE / AUTOMATION", 12, C_CYAN))
	pref_box.add_child(_label("运行偏好", 21, C_TEXT))
	var dismantle := CheckButton.new()
	dismantle.text = "重复战利品自动分解"
	dismantle.button_pressed = bool(game.data.settings.auto_dismantle)
	dismantle.disabled = not game.has_tech("auto_dismantle")
	dismantle.toggled.connect(func(value: bool) -> void: game.set_setting("auto_dismantle", value))
	pref_box.add_child(dismantle)
	if dismantle.disabled:
		pref_box.add_child(_label("需要研究“重复品自动分解”。", 11, C_MUTED))
	var motion := CheckButton.new()
	motion.text = "减少界面动态效果"
	motion.button_pressed = bool(game.data.settings.reduced_motion)
	motion.toggled.connect(func(value: bool) -> void: game.set_setting("reduced_motion", value))
	pref_box.add_child(motion)
	var reserve_label := _label("自动化安全储备：%d E" % int(game.data.settings.safe_reserve), 13, C_MUTED)
	pref_box.add_child(reserve_label)
	var reserve := HSlider.new()
	reserve.min_value = 0
	reserve.max_value = 200
	reserve.step = 5
	reserve.value = int(game.data.settings.safe_reserve)
	reserve.value_changed.connect(func(value: float) -> void: reserve_label.text = "自动化安全储备：%d E" % int(value))
	reserve.drag_ended.connect(func(changed_value: bool) -> void:
		if changed_value:
			game.set_setting("safe_reserve", int(reserve.value))
	)
	pref_box.add_child(reserve)
	var pref_spacer := Control.new()
	pref_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pref_box.add_child(pref_spacer)
	var reset := _button("清除存档并重新苏醒", _confirm_reset)
	reset.add_theme_color_override("font_color", C_RED)
	pref_box.add_child(reset)

	var save_panel := _panel(C_PANEL, C_VIOLET.darkened(0.45), 1)
	save_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(save_panel)
	var save_box := VBoxContainer.new()
	save_box.add_theme_constant_override("separation", 9)
	save_panel.add_child(save_box)
	save_box.add_child(_label("SAVE TRANSFER", 12, C_VIOLET))
	save_box.add_child(_label("导入 / 导出", 21, C_TEXT))
	export_box = TextEdit.new()
	export_box.placeholder_text = "点击导出生成存档码，或在此粘贴存档码后导入。"
	export_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	export_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	save_box.add_child(export_box)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.add_child(_button("生成导出码", func() -> void:
		export_box.text = game.export_save()
		export_box.select_all()
		_show_notice("导出码已生成。", "success")
	))
	actions.add_child(_button("复制", func() -> void:
		DisplayServer.clipboard_set(export_box.text)
		_show_notice("已复制到剪贴板。", "success")
	))
	actions.add_child(_button("从剪贴板粘贴", func() -> void: export_box.text = DisplayServer.clipboard_get()))
	actions.add_child(_button("校验并导入", func() -> void: game.import_save(export_box.text)))
	save_box.add_child(actions)
	save_box.add_child(_label("存档版本 %s · 配置版本 %s · 不包含离线收益" % [game.data.save_version, game.data.config_version], 11, C_MUTED))


func _confirm_reset() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "清除全部本地进度"
	dialog.dialog_text = "此操作不可撤销。建议先导出存档码。确认后将返回苏醒流程。"
	dialog.ok_button_text = "确认清除"
	dialog.cancel_button_text = "取消"
	dialog.confirmed.connect(func() -> void:
		current_page = "decrypt"
		selected_channel = 0
		game.reset_game()
		_show_awakening()
	)
	dialog.close_requested.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(500, 190))


func _show_awakening() -> void:
	var veil := ColorRect.new()
	veil.color = Color(0.01, 0.025, 0.035, 0.94)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.z_index = 50
	add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.add_child(center)
	var panel := _panel(Color("071117"), C_CYAN, 1)
	panel.custom_minimum_size = Vector2(670, 420)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(_label("EMERGENCY BOOT // UNKNOWN FACILITY", 12, C_CYAN))
	var tutorial: Dictionary = game.config.data.get("tutorial", {})
	box.add_child(_label(tutorial.get("title", "紧急唤醒"), 31, C_TEXT))
	var story_text: String = tutorial.get("story", "应急终端正在等待恢复协议。")
	var story := _label(story_text, 16, C_MUTED)
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(story)
	var boot := _panel(Color("020608"), Color("244b50"), 1)
	var boot_text := _label("LIFE SUPPORT ........ OFFLINE\nOPERATOR STATUS ..... UNVERIFIED\nRESTORE PROTOCOL .... 3-BIT / RADIX-2", 15, C_GREEN)
	boot.add_child(boot_text)
	box.add_child(boot)
	var begin := _button("连接应急终端  >", func() -> void:
		game.start_tutorial()
		veil.queue_free()
	)
	begin.custom_minimum_size.y = 48
	box.add_child(begin)
