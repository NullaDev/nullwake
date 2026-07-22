extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _tree_contains_text(node: Node, fragment: String) -> bool:
	if node is Label and fragment in (node as Label).text:
		return true
	if node is RichTextLabel and fragment in (node as RichTextLabel).text:
		return true
	if node is BaseButton and fragment in (node as BaseButton).text:
		return true
	for child: Node in node.get_children():
		if _tree_contains_text(child, fragment):
			return true
	return false


func _run() -> void:
	SaveSystem.use_storage_paths("user://nullwake_integration_test.json", "user://nullwake_integration_test.tmp")
	SaveSystem.erase()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Control = packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	_expect(main.theme.default_font != null, "global UI theme should embed a project font")
	_expect(main.theme.default_font.has_char(0x89E3), "embedded UI font must contain the Chinese glyph U+89E3")
	_expect(main.game.config.nodes.size() == 15, "runtime should load all fifteen designed node types")
	_expect(main.game.config.series.size() == 9 and main.game.visible_series_count() == 8, "first cycle should expose eight series and reserve the ninth for reversion")
	_expect(main.game.next_compute_cost() == 36, "first compute purchase should cost 36 energy")
	_expect(not main.nav_bar.visible, "bottom navigation must stay hidden during the guided protocol")
	main.game.start_tutorial()
	var free_node: Dictionary = main.game.node_definition("maintenance")
	var paid_node: Dictionary = main.game.node_definition("data_packet")
	_expect(PuzzleEngine.generate_candidates(paid_node).size() > PuzzleEngine.generate_candidates(free_node).size(), "paid starter node must be more complex than the free fallback node")
	_expect(not "100" in main.guess_input.placeholder_text, "guided target must not be written inside the input field")
	var guide_log: String = main._history_text(main.game.data.channels[0], free_node)
	_expect("GUIDE INPUT" in guide_log and "1  0  0" in guide_log, "guided target should be displayed in the DOS protocol log")
	_expect(not "NO HANDSHAKE" in guide_log, "initial tutorial log must not show a no-handshake line below the guide input")
	_expect(main.game.submit_guess(0, "100", "manual"), "guided first guess should submit")
	var feedback_log: String = main._history_text(main.game.data.channels[0], free_node)
	_expect("位置正确:1" in feedback_log and "数字错位:2" in feedback_log, "feedback labels should use four-character terminology")
	_expect("位置正确 1：" in feedback_log and "数字错位 2：" in feedback_log, "first tutorial result should explain what the values mean")
	_expect("NEXT INPUT" in feedback_log and "0  0  1" in feedback_log, "tutorial explanation should lead to the 001 input")
	_expect(main.game.data.tutorial_step == "solve_hint", "tutorial should advance after 100")
	_expect(main.game.submit_guess(0, "001", "manual"), "guided solution should submit")
	var solved_log: String = main._history_text(main.game.data.channels[0], free_node)
	_expect(not "FEEDBACK EXPLANATION" in solved_log, "tutorial feedback explanation must not repeat after the 001 submission")
	_expect("PROTOCOL VERIFIED" in solved_log and "点击“结算并继续”" in solved_log, "settlement guidance must be displayed in the DOS protocol log")
	_expect(main.game.data.channels[0].state == "SOLVED", "tutorial channel should solve")
	_expect(main.game.data.tutorial_step == "claim_reward", "tutorial should explicitly wait for the settlement button after 001")
	_expect(not main.game.data.tutorial_completed and not main.nav_bar.visible, "tutorial must remain incomplete until settlement is clicked")
	main.game.claim_resolution(0)
	_expect(main.game.data.tutorial_completed, "tutorial should complete after settlement")
	_expect(main.game.data.tutorial_step == "automation_hint", "tutorial settlement should open the automation follow-up objective")
	_expect(int(main.game.data.energy) == 7, "tutorial reward should include efficiency but no default manual percentage bonus")
	_expect(int(main.game.data.loot.get("pod_seal", 0)) == 1, "tutorial settlement should guarantee the first collection item")
	_expect("automation_guide" in main.game.data.memories and "feedback_guide" in main.game.data.memories and "collection_guide" in main.game.data.memories, "tutorial and first-collection instructions should be saved in the memory archive")
	var automation_log: String = main._history_text(main.game.data.channels[0], free_node)
	_expect("NEXT OBJECTIVE" in automation_log and "36 E" in automation_log and "04 终端" in automation_log, "post-tutorial DOS log should direct the player toward the first compute purchase")
	_expect(not "已写入" in automation_log and not "07 记忆" in automation_log, "DOS guidance should not announce that it was copied into memory")
	_expect(not "NO HANDSHAKE" in automation_log, "automation objective should replace the empty handshake message")
	var pod_card: PanelContainer = main._loot_item_card(main.game.config.loot["pod_seal"])
	_expect(_tree_contains_text(pod_card, "持有效果：基础维护协议能量 +2%") and _tree_contains_text(pod_card, "集齐后本效果 ×2"), "collection cards must show their held effect and set multiplier")
	pod_card.free()
	main._navigate("memory")
	await process_frame
	await process_frame
	_expect(_tree_contains_text(main.content_host, "自动化起步"), "memory archive should expose the automation guide")
	_expect(_tree_contains_text(main.content_host, "收藏被动") and _tree_contains_text(main.content_host, "反馈判读"), "memory archive should retain first-collection and feedback instructions")
	var automation_body := main.content_host.find_child("MemoryBody_automation_guide", true, false) as RichTextLabel
	_expect(is_instance_valid(automation_body) and "36 E" in automation_body.text and automation_body.size.y >= 44.0, "unlocked memory cards must render their complete instruction body instead of only the title")
	_expect(_tree_contains_text(main.content_host, "记录 01 / 损耗") and _tree_contains_text(main.content_host, "成功结算一次消耗型节点"), "locked memories should remain visible with their unlock condition")
	main._navigate("collection")
	await process_frame
	await process_frame
	_expect(_tree_contains_text(main.content_host, "系列规则：单件取得后立即生效") and _tree_contains_text(main.content_host, "持有效果：基础维护协议能量 +2%"), "rendered collection page must visibly explain both item effects and set doubling")
	_expect(_tree_contains_text(main.content_host, "来源：教学结算；T-1 基础维护协议与常规数据封装"), "collection series must reveal their source tier and node families without requiring probability disclosure")
	main._navigate("decrypt")
	var fragments_before_duplicate := int(main.game.data.fragments)
	main.game._award_loot("pod_seal")
	_expect(int(main.game.data.loot.get("pod_seal", 0)) == 1 and int(main.game.data.fragments) == fragments_before_duplicate + 1, "duplicate collections should dismantle into fragments by default")
	main.game.data.series_pity["awakening_set"] = 13
	main.game._roll_loot(free_node)
	_expect(int(main.game.data.loot.get("emergency_capacitor", 0)) > 0 or int(main.game.data.loot.get("wake_log", 0)) > 0, "series hard pity should award a missing eligible collection item")
	_expect(int(main.game.data.series_pity.get("awakening_set", -1)) == 0, "new collection discovery should reset its series pity")
	var post_tutorial_channel: Dictionary = main.game.data.channels[0]
	var post_tutorial_secret: String = post_tutorial_channel.secret
	var wrong_guess := "000"
	if wrong_guess == post_tutorial_secret:
		wrong_guess = "111"
	_expect(main.game.submit_guess(0, wrong_guess, "manual"), "post-tutorial maintenance guess should submit")
	var objective_with_history: String = main._history_text(post_tutorial_channel, free_node)
	_expect(objective_with_history.find("NEXT OBJECTIVE") < objective_with_history.find("> %s" % wrong_guess), "automation objective must stay above DOS guess history")
	_expect(main.game.submit_guess(0, post_tutorial_secret, "manual"), "post-tutorial maintenance protocol should solve")
	main.game.claim_resolution(0)
	_expect(main.game.data.tutorial_step == "completed" and not "NEXT OBJECTIVE" in main._history_text(main.game.data.channels[0], free_node), "automation objective should disappear after the next completed protocol")
	_expect(main.nav_bar.visible, "bottom navigation should appear after the tutorial is settled")
	_expect(main.game.data.inventory.size() == 1, "tutorial should grant one consumable node")
	var gifted: Dictionary = main.game.data.inventory[0]
	var energy_before_free_sale: int = int(main.game.data.energy)
	main.game.sell_node(gifted.uid)
	_expect(main.game.data.inventory.size() == 1 and int(main.game.data.energy) == energy_before_free_sale, "tutorial free grant must not be sellable")
	main.game.data.energy = 100
	main.game.buy_node("data_packet")
	_expect(main.game.data.inventory.size() == 2 and int(main.game.data.energy) == 90, "paid starter nodes must remain purchasable while the tutorial grant is held")
	var purchased: Dictionary = main.game.data.inventory[1]
	main.game.sell_node(purchased.uid)
	_expect(main.game.data.inventory.size() == 1 and int(main.game.data.energy) == 95, "paid starter node should remain a normal sellable inventory item")
	main._navigate("nodes")
	await process_frame
	await process_frame
	var catalog_scroll: ScrollContainer = main.active_scroll
	catalog_scroll.scroll_vertical = 100
	await process_frame
	var catalog_position: int = catalog_scroll.scroll_vertical
	_expect(catalog_position > 0, "node catalog should have a usable vertical scroll range")
	main.game.changed.emit("channel:0:guess")
	_expect(main.active_scroll == catalog_scroll and main.active_scroll.scroll_vertical == catalog_position, "background channel updates must not rebuild or reset a scrolled page")
	main.game.changed.emit("inventory")
	await process_frame
	await process_frame
	_expect(is_instance_valid(main.active_scroll) and main.active_scroll.scroll_vertical == catalog_position, "required page rebuilds must restore the previous scroll position")
	for index in range(30):
		main.game.data.statistics.node_stats["stress_%02d" % index] = {"solved": index, "failed": 0}
	main._navigate("stats")
	await process_frame
	await process_frame
	var stats_scroll: ScrollContainer = main.active_scroll
	_expect(is_instance_valid(stats_scroll) and stats_scroll.get_v_scroll_bar().max_value > stats_scroll.size.y, "long statistics content should use a bounded scroll area")
	stats_scroll.scroll_vertical = 100
	await process_frame
	_expect(stats_scroll.scroll_vertical > 0, "long statistics content should remain vertically scrollable")
	_expect(main.nav_bar.global_position.y + main.nav_bar.size.y <= main.size.y + 1.0, "statistics content must not push the bottom navigation outside the window")
	for page in ["nodes", "inventory", "terminal", "tech", "collection", "memory", "stats", "settings", "decrypt"]:
		main._navigate(page)
		await process_frame
	main._navigate("stats")
	await process_frame
	var stats_grid := main.content_host.find_child("StatsGrid", true, false) as GridContainer
	_expect(is_instance_valid(stats_grid) and stats_grid.get_child_count() == 16, "statistics page should render all sixteen telemetry cards")
	if is_instance_valid(stats_grid):
		for card: Control in stats_grid.get_children():
			var title := card.find_child("StatsTitle", true, false) as Label
			var value := card.find_child("StatsValue", true, false) as Label
			_expect(is_instance_valid(title) and title.text != "" and title.size.x > 0.0, "every statistics card should have a visible title")
			_expect(is_instance_valid(value) and value.text != "" and value.size.x > 0.0, "every statistics card should have a visible value")
	main._navigate("terminal")
	await process_frame
	await process_frame
	_expect(main.nav_bar.global_position.y + main.nav_bar.size.y <= main.size.y + 1.0, "expanded terminal and reversion data must not push navigation outside the window")
	main._navigate("decrypt")
	main.game.data.energy = 20000
	main.game.data.fragments = 50
	main.game.purchase_terminal_upgrade()
	main.game.purchase_terminal_upgrade()
	main.game.purchase_channel()
	main.game.purchase_compute()
	_expect(main.game.data.tutorial_step == "completed", "the completed post-tutorial protocol should keep the automation objective cleared")
	_expect("compute_guide" in main.game.data.memories, "first compute purchase instructions should be saved in memory")
	main.game.purchase_compute()
	_expect(main.game.next_compute_cost() == 110, "third compute purchase should follow the exponential price curve")
	main.game.purchase_tech("logic_filter")
	_expect(is_equal_approx(main.game._effect_sum("manual_reward_bonus"), 0.0), "manual percentage bonus should start at zero")
	main.game.purchase_tech("manual_calibration")
	_expect(main.game.tech_level("manual_calibration") == 1 and is_equal_approx(main.game._effect_sum("manual_reward_bonus"), 0.06), "manual calibration should grant six percent per purchased level")
	_expect(int(main.game.next_tech_cost("manual_calibration").energy) == 55, "the second manual calibration level should use its configured exponential price")
	main.game.set_bulk_tech_purchase(true)
	var calibration_preview: Dictionary = main.game.tech_purchase_preview("manual_calibration", true)
	_expect(int(calibration_preview.levels) == 9, "bulk research preview should calculate the exact affordable level count")
	main._navigate("tech")
	await process_frame
	_expect(_tree_contains_text(main.content_host, "当前资源可提升 9 级") and _tree_contains_text(main.content_host, "提升 9 级"), "bulk research cards should show the calculated purchase count before buying")
	main.game.purchase_tech("manual_calibration")
	_expect(main.game.tech_level("manual_calibration") == 10 and is_equal_approx(main.game._effect_sum("manual_reward_bonus"), 0.60), "bulk research should buy all affordable finite levels without exceeding the cap")
	main.game.set_bulk_tech_purchase(false)
	_expect(main.game.tech_max_level("protocol_amplification") == -1 and int(main.game.next_tech_cost("protocol_amplification").energy) == 3000, "infinite research should have no level cap and expose its first escalating cost")
	main._navigate("tech")
	await process_frame
	await process_frame
	_expect(_tree_contains_text(main.content_host, "当前等级：10 / 10") and _tree_contains_text(main.content_host, "当前提升：手动协议能量 +60%") and _tree_contains_text(main.content_host, "当前等级：0 / ∞"), "technology cards must show current levels and their currently active cumulative effects")
	_expect(_tree_contains_text(main.content_host, "批量研究：一次购买当前资源可承担的全部等级"), "technology page must expose the persisted bulk-research toggle")
	var bulk_toggle := main.content_host.find_child("BulkTechPurchase", true, false) as CheckButton
	_expect(is_instance_valid(bulk_toggle) and not bulk_toggle.button_pressed, "bulk research should default to one level per click")
	bulk_toggle.button_pressed = true
	await process_frame
	_expect(bool(main.game.data.settings.bulk_tech_purchase), "changing the visible bulk-research toggle must persist the preference")
	main.game.set_bulk_tech_purchase(false)
	main._navigate("decrypt")
	main.game.unload_node(0)
	main.game.load_inventory(gifted.uid, 0)
	var gifted_channel: Dictionary = main.game.data.channels[0]
	var gifted_wrong_guess := "0000"
	if gifted_wrong_guess == str(gifted_channel.secret):
		gifted_wrong_guess = "1111"
	var inventory_count_before_gift_abandon: int = main.game.data.inventory.size()
	_expect(main.game.submit_guess(0, gifted_wrong_guess, "manual"), "tutorial free grant should accept a valid guess before abandonment")
	_expect(main.game.is_channel_free_grant(0), "loaded tutorial gift should retain its free-grant identity")
	main.game.abandon_node(0)
	var returned_gift: Dictionary = main.game.inventory_instance(gifted.uid)
	_expect(main.game.data.inventory.size() == inventory_count_before_gift_abandon, "abandoning the started tutorial gift must not remove it from inventory")
	_expect(not returned_gift.is_empty() and int(returned_gift.locked_channel) == -1, "abandoned tutorial gift should return to unlocked inventory")
	_expect(main.game.data.channels[0].node_ref.is_empty(), "abandoning the tutorial gift should clear its channel and current guess progress")
	main.game.load_inventory(gifted.uid, 0)
	main.game.assign_ai(0, "filter")
	_expect(main.game.data.channels[0].state == "AI_HANDSHAKE", "a newly assigned AI must enter the handshake phase before solving")
	_expect(main.game.estimated_automation_cycle(paid_node, "filter") >= 9.0 and main.game.estimated_automation_cycle(paid_node, "filter") <= 12.0, "starter filter cycle should remain competitive with an experienced human solver")
	var handshake_log: String = main._history_text(main.game.data.channels[0], paid_node)
	_expect("协议握手中" in handshake_log and not "AI 正在猜测中" in handshake_log, "DOS log must not claim that the AI is solving before the handshake completes")
	var handshake_now := Time.get_ticks_msec()
	main.game.data.channels[0].ai_phase_started_ms = handshake_now - 500
	main.game.data.channels[0].ai_due_ms = handshake_now + 500
	main._update_handshake_progress()
	_expect(is_instance_valid(main.handshake_progress_bar) and main.handshake_progress_bar.value >= 45.0 and main.handshake_progress_bar.value <= 55.0, "handshake progress bar should reflect elapsed handshake time")
	_expect("剩余" in main.handshake_progress_label.text, "handshake progress should show its remaining time")
	var open_ai_selector: OptionButton = main.current_ai_selector
	_expect(is_instance_valid(open_ai_selector), "loaded channel should expose its AI selector")
	var ai_popup: PopupMenu = open_ai_selector.get_popup()
	ai_popup.popup()
	await process_frame
	_expect(main.ai_menu_open, "opening the AI selector should suspend asynchronous detail refreshes")
	main.game.changed.emit("channel:0:settled")
	_expect(main.current_ai_selector == open_ai_selector and main.ai_menu_open, "channel settlement must not destroy an open AI selector")
	_expect(main.pending_decrypt_detail_refresh, "a selected-channel refresh should be queued while the AI selector is open")
	ai_popup.hide()
	await process_frame
	_expect(not main.pending_decrypt_detail_refresh and is_instance_valid(main.current_ai_selector), "queued channel detail refresh should run after the AI selector closes")
	var active_phase_due_before_priority_change := int(main.game.data.channels[0].ai_due_ms)
	main.game.load_permanent("maintenance", 1)
	_expect(main.game.channel_priority_rank(0) == 1 and main.game.channel_priority_rank(1) == 2, "new channels should begin in their visible queue order")
	_expect(main.game.move_channel_priority(1, -1), "an unlocked channel should be able to move up the compute queue")
	_expect(main.game.channel_priority_rank(1) == 1 and main.game.channel_priority_rank(0) == 2, "compute priority controls should swap the visible queue order")
	_expect(main.game.data.channels[0].state == "AI_HANDSHAKE" and int(main.game.data.channels[0].ai_due_ms) == active_phase_due_before_priority_change, "priority changes must not preempt or restart an active AI phase")
	main.selected_channel = 1
	main._navigate("decrypt")
	await process_frame
	_expect(_tree_contains_text(main.content_host, "算力优先级 1 / 2"), "multi-channel decrypt view should expose the selected channel's compute priority")
	main.guess_input.text = "10"
	var manual_input: LineEdit = main.guess_input
	main.game.data.channels[0].ai_due_ms = 1
	main.game._process_ai()
	_expect(is_instance_valid(manual_input) and main.guess_input == manual_input and main.guess_input.text == "10", "background AI updates must not rebuild another channel or clear its draft")
	_expect(main.game.data.channels[0].state == "AI_THINKING" and main.game.data.channels[0].history.is_empty(), "handshake completion should start AI solving without submitting an early guess")
	var ai_thinking_log: String = main._history_text(main.game.data.channels[0], paid_node)
	_expect("协议握手完成" in ai_thinking_log and "AI 正在猜测中" in ai_thinking_log, "DOS log should announce solving only after the handshake completes")
	main.selected_channel = 0
	main._navigate("decrypt")
	var energy_before_ai: int = int(main.game.data.energy)
	for _step in range(10):
		var channel: Dictionary = main.game.data.channels[0]
		if channel.state == "AI_HANDSHAKE":
			channel.ai_due_ms = 1
			main.game._process_ai()
		if channel.state == "AI_THINKING":
			channel.ai_due_ms = 1
			main.game._process_ai()
		if channel.state == "SOLVED":
			channel.resolution_due_ms = 1
			main.game._process_ai()
			_expect(channel.state == "SOLVED", "AI result must wait for manual settlement before the auto-settle technology is researched")
			main.game.claim_resolution(0)
			break
	_expect(main.game.data.channels[0].state == "EMPTY", "AI settlement should consume a single-use node and clear the channel")
	_expect(int(main.game.data.energy) > energy_before_ai, "AI settlement should grant configured protocol energy")
	main.game.buy_node("data_packet")
	_expect(main.game.data.inventory.size() == 1 and int(main.game.data.inventory[0].acquired_cost) > 0, "same node should become purchasable after the free grant is consumed")
	_expect(int(main.game.next_tech_cost("auto_settle").energy) == 40, "the first automatic-settlement channel should cost 40 energy")
	main.game.purchase_tech("auto_settle")
	_expect(main.game.tech_level("auto_settle") == 1 and int(main.game.next_tech_cost("auto_settle").energy) == 85, "automatic settlement should price the second covered channel from its channel cost")
	_expect(int(main.game.next_tech_cost("auto_settle", 2).energy) == 750 and int(main.game.next_tech_cost("auto_settle", 3).energy) == 2700, "later automatic-settlement prices should stay aligned with their corresponding channels")
	_expect(main.game.channel_has_auto_settlement(1) and not main.game.channel_has_auto_settlement(0), "automatic settlement coverage should follow the player-controlled channel priority")
	var settlement_preview: Dictionary = main.game.tech_purchase_preview("auto_settle", true)
	_expect(int(settlement_preview.levels) == 1, "bulk automatic-settlement research must not buy coverage beyond the number of established channels")
	var energy_before_auto_settlement := int(main.game.data.energy)
	var covered_secret: String = main.game.data.channels[1].secret
	_expect(main.game.submit_guess(1, covered_secret, "manual"), "covered channel should reach a result for automatic settlement")
	main.game.data.channels[1].resolution_due_ms = 1
	main.game._process_ai()
	_expect(main.game.data.channels[1].state == "READY" and int(main.game.data.energy) > energy_before_auto_settlement, "a covered channel should automatically claim and reset its completed permanent node")
	_expect(int(main.game.next_tech_cost("auto_restock").energy) == 60, "the first automatic-restock channel should cost 60 energy")
	var terminal_level_before_restock_test := int(main.game.data.terminal_level)
	main.game.data.terminal_level = 1
	main.game.purchase_tech("auto_restock")
	_expect(main.game.tech_level_cap("auto_restock") == 1 and int(main.game.tech_purchase_preview("auto_restock", true).levels) == 0, "automatic-restock research must stop at the current terminal tier")
	main.game.data.terminal_level = terminal_level_before_restock_test
	_expect(main.game.tech_level("auto_restock") == 1 and int(main.game.next_tech_cost("auto_restock").energy) == 120, "automatic restock should price its second tier from the next terminal stage")
	_expect(int(main.game.next_tech_cost("auto_restock", 2).energy) == 440 and int(main.game.next_tech_cost("auto_restock", 3).energy) == 4200, "later automatic-restock prices should stay aligned with their corresponding terminal tiers")
	_expect(main.game.node_has_auto_restock(main.game.node_definition("maintenance")) and not main.game.node_has_auto_restock(main.game.node_definition("security_4b")), "automatic-restock level one should cover T-1 nodes but not T-2 nodes")
	_expect(main.game.channel_has_auto_restock(1) and not main.game.channel_has_auto_restock(0), "automatic-restock coverage should follow the loaded node tier")
	main.game.set_channel_auto_restock(0, true)
	_expect(not bool(main.game.data.channels[0].auto_restock), "an empty channel must not enable automatic restock")
	var restock_uid: String = main.game.data.inventory[0].uid
	main.game.load_inventory(restock_uid, 0)
	_expect(main.game.channel_has_auto_restock(0), "loading a T-1 node should make the channel eligible for automatic restock regardless of priority")
	main.game.assign_ai(0, "filter")
	main.game.set_channel_auto_restock(0, true)
	var energy_before_restock := int(main.game.data.energy)
	var restock_secret: String = main.game.data.channels[0].secret
	_expect(main.game.submit_guess(0, restock_secret, "filter"), "automatic restock test node should solve")
	main.game.claim_resolution(0)
	_expect(main.game.channel_node(0).id == "data_packet" and main.game.data.channels[0].state == "AI_HANDSHAKE", "successful automated channel should buy, attach, and restart the same node from a new handshake")
	_expect(int(main.game.data.energy) > energy_before_restock, "automatic restock should retain positive net energy after buying the replacement node")
	main.game.data.terminal_level = 4
	main.game.data.energy = 3000
	main.game.purchase_tech("protocol_amplification")
	_expect(main.game.tech_level("protocol_amplification") == 1 and is_equal_approx(main.game._tech_effect_sum("energy_bonus"), 0.03), "infinite amplification should provide its configured independent energy multiplier")
	_expect(int(main.game.next_tech_cost("protocol_amplification").energy) == 6750, "infinite amplification should continue with its exponential next-level cost")
	main.game.data.run_score = 24000
	main.game.data.cycle_memory_core_solved = true
	main.game.data.series_pity["maintenance_set"] = 7
	main.game.data.fragments = 99
	main.game.set_bulk_tech_purchase(true)
	var solved_before_prestige := int(main.game.data.statistics.solved)
	_expect(main.game.can_prestige() and main.game.preview_prestige_echo() == 5, "first reversion should unlock at 24000 score and award five echoes")
	_expect(main.game.prestige(), "eligible reversion should complete")
	_expect(int(main.game.data.cycle) == 2 and int(main.game.data.echo) == 5 and int(main.game.data.lifetime_echo) == 5, "reversion should advance the cycle and preserve lifetime echoes")
	_expect(int(main.game.data.energy) == 0 and int(main.game.data.fragments) == 0 and int(main.game.data.terminal_level) == 1, "reversion should reset run resources and terminal progress")
	_expect(main.game.tech_level("manual_calibration") == 0 and bool(main.game.data.settings.bulk_tech_purchase), "reversion should reset local technology levels while preserving the bulk-research preference")
	_expect(int(main.game.data.loot.get("pod_seal", 0)) == 1 and int(main.game.data.series_pity.get("maintenance_set", 0)) == 7, "collections and pity counters must cross cycles")
	_expect(int(main.game.data.statistics.solved) == solved_before_prestige and main.game.visible_series_count() == 9, "lifetime statistics persist and cycle two reveals reversion collections")
	_expect(main.game.prestige_multiplier() > 1.78 and main.game.data.tutorial_completed, "echoes must apply the strengthened independent multiplier without replaying tutorial")
	_expect(main.game.prestige_target_score() == 52000, "second-cycle reversion target should rise to 52000 score")
	main._navigate("decrypt")
	await process_frame
	SaveSystem.erase()
	SaveSystem.restore_default_storage_paths()
	if failures == 0:
		print("NULLWAKE INTEGRATION: all flows passed")
		quit(0)
	else:
		quit(1)
