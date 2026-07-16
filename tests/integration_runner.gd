extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	SaveSystem.erase()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Control = packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	_expect(main.theme.default_font != null, "global UI theme should embed a project font")
	_expect(main.theme.default_font.has_char(0x89E3), "embedded UI font must contain the Chinese glyph U+89E3")
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
	_expect(main.nav_bar.visible, "bottom navigation should appear after the tutorial is settled")
	_expect(main.game.data.inventory.size() == 1, "tutorial should grant one consumable node")
	var gifted: Dictionary = main.game.data.inventory[0]
	var energy_before_free_sale: int = int(main.game.data.energy)
	main.game.sell_node(gifted.uid)
	_expect(main.game.data.inventory.size() == 1 and int(main.game.data.energy) == energy_before_free_sale, "tutorial free grant must not be sellable")
	main.game.data.energy = 100
	main.game.buy_node("data_packet")
	_expect(main.game.data.inventory.size() == 1 and int(main.game.data.energy) == 100, "tutorial free grant should block buying the same node while held")
	for page in ["nodes", "inventory", "terminal", "tech", "collection", "memory", "stats", "settings", "decrypt"]:
		main._navigate(page)
		await process_frame
	main.game.data.energy = 1000
	main.game.data.fragments = 50
	main.game.purchase_terminal_upgrade()
	main.game.purchase_terminal_upgrade()
	main.game.purchase_compute()
	main.game.purchase_compute()
	main.game.purchase_tech("logic_filter")
	main.game.unload_node(0)
	main.game.load_inventory(gifted.uid, 0)
	main.game.assign_ai(0, "filter")
	_expect(main.game.data.channels[0].state == "AI_THINKING", "unlocked AI should occupy compute and start")
	var energy_before_ai: int = int(main.game.data.energy)
	for _step in range(10):
		var channel: Dictionary = main.game.data.channels[0]
		if channel.state == "AI_THINKING":
			channel.ai_due_ms = 1
			main.game._process_ai()
		if channel.state == "SOLVED":
			main.game.claim_resolution(0)
			break
	_expect(main.game.data.channels[0].state == "EMPTY", "AI settlement should consume a single-use node and clear the channel")
	_expect(int(main.game.data.energy) > energy_before_ai, "AI settlement should grant configured protocol energy")
	main.game.buy_node("data_packet")
	_expect(main.game.data.inventory.size() == 1 and int(main.game.data.inventory[0].acquired_cost) > 0, "same node should become purchasable after the free grant is consumed")
	main._navigate("decrypt")
	await process_frame
	SaveSystem.erase()
	if failures == 0:
		print("NULLWAKE INTEGRATION: all flows passed")
		quit(0)
	else:
		quit(1)
