extends SceneTree

var failures := 0


func _initialize() -> void:
	_test_feedback()
	_test_candidates()
	_test_ai()
	_test_config()
	if failures == 0:
		print("NULLWAKE TESTS: all assertions passed")
		quit(0)
	else:
		push_error("NULLWAKE TESTS: %d assertion(s) failed" % failures)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _expect_feedback(secret: String, guess: String, exact: int, misplaced: int) -> void:
	var result := PuzzleEngine.feedback(secret, guess)
	_expect(result.exact == exact, "%s/%s exact expected %d got %d" % [secret, guess, exact, result.exact])
	_expect(result.misplaced == misplaced, "%s/%s misplaced expected %d got %d" % [secret, guess, misplaced, result.misplaced])


func _test_feedback() -> void:
	_expect_feedback("001", "100", 1, 2)
	_expect_feedback("001", "001", 3, 0)
	_expect_feedback("000", "111", 0, 0)
	_expect_feedback("001", "000", 2, 0)
	_expect_feedback("011", "110", 1, 2)


func _test_candidates() -> void:
	var no_repeat := {"length": 3, "radix": 3, "allow_duplicates": false, "protocol": "no_repeat"}
	_expect(PuzzleEngine.generate_candidates(no_repeat).size() == 6, "3-place ternary no-repeat space must contain 6 candidates")
	var mirror := {"length": 5, "radix": 2, "allow_duplicates": true, "protocol": "mirror"}
	_expect(PuzzleEngine.generate_candidates(mirror).size() == 8, "5-place binary mirror space must contain 8 candidates")
	var checksum := {"length": 7, "radix": 2, "allow_duplicates": true, "protocol": "checksum"}
	var checksum_candidates := PuzzleEngine.generate_candidates(checksum)
	_expect(checksum_candidates.size() == 64, "7-place binary checksum space must contain 64 candidates")
	var all_valid := true
	for candidate: String in checksum_candidates:
		var total := 0
		for index in range(6):
			total += int(candidate[index])
		all_valid = all_valid and total % 2 == int(candidate[6])
	_expect(all_valid, "checksum candidates must encode the parity of their first six digits")
	var total_feedback := PuzzleEngine.visible_feedback("001", "100", "total_only")
	_expect(total_feedback.exact == -1 and total_feedback.misplaced == 3, "total-only feedback must hide positions and expose only total hits")
	var total_history := [{"guess": "100", "feedback": total_feedback}]
	_expect(PuzzleEngine.candidate_consistent("001", total_history, "total_only"), "special-feedback consistency must use only visible information")
	_expect(not PuzzleEngine.candidate_consistent("000", total_history, "total_only"), "inconsistent total-hit candidates must be excluded")


func _test_ai() -> void:
	var node := {"length": 3, "radix": 2, "allow_duplicates": true, "protocol": "standard"}
	var history := [{"guess": "000", "feedback": PuzzleEngine.feedback("101", "000")}]
	var guess := AISolver.choose_guess("elimination", node, history)
	_expect(guess != "000", "AI must not repeat a submitted complete guess")
	var special_node := {"length": 3, "radix": 2, "allow_duplicates": true, "protocol": "standard", "feedback": "total_only"}
	var special_history := [{"guess": "100", "feedback": PuzzleEngine.visible_feedback("001", "100", "total_only")}]
	var special_guess := AISolver.choose_guess("information_gain", special_node, special_history)
	_expect(special_guess != "" and special_guess != "100", "entropy AI must support visible-only feedback without repeating a guess")


func _test_config() -> void:
	var config := ConfigDB.new()
	_expect(config.load_config(), "game balance configuration must load")
	_expect(config.nodes.size() == 15, "launch balance must define 15 node types")
	_expect(config.series.size() == 9, "launch balance must define 9 collection series")
	_expect(int(config.tech.auto_restock.terminal_level) == 1, "the first automatic-restock level must be purchasable on the starter terminal")
	_expect(config.memories.size() == 18 and config.memories.has("automation_guide") and config.memories.has("collection_guide") and config.memories.has("compute_guide"), "memory archive must retain all operational guides and the full index")
	_expect(float(config.data.get("balance", {}).get("manual_reward_bonus", -1.0)) == 0.0 and float(config.data.get("balance", {}).get("manual_active_bonus_cap", 0.0)) == 0.75, "manual percentage bonus must start at zero and retain a safe active-play cap")
	_expect(int(config.tech["overclock"].max_level) == 20 and int(config.tech["manual_calibration"].max_level) == 10, "general production technologies must expose long finite level tracks")
	_expect(bool(config.tech["protocol_amplification"].infinite) and float(config.tech["protocol_amplification"].cost_growth) > 2.0, "late-game research must include a safely escalating infinite investment")
	_expect(not config.tech["candidate_cache"].has("max_level") and config.tech["candidate_cache"].effects[0].ai_ids == ["filter"], "AI-specific acceleration must remain a cheap one-time specialization")
	_expect(config.data.get("terminal_levels", []).size() == 4, "balance must define four terminal tiers")
	_expect(int(config.nodes["security_4b"].attempt_limit) == 4, "security node must use the four-attempt limit")
	_expect(config.nodes["ternary_echo_matrix"].feedback == "total_only", "ternary echo matrix must expose total-only feedback")
	_expect(float(config.ai["probe"].decision_time) == 1.0 and float(config.ai["filter"].decision_time) == 1.5 and float(config.ai["entropy"].decision_time) == 2.0, "AI decision times must be fast enough to compete with skilled manual play while differing by strategy")
	_expect(float(config.nodes["data_packet"].handshake_time) == 5.0 and float(config.nodes["memory_core"].handshake_time) == 30.0, "handshake time should scale with node complexity without imposing minute-long artificial waits")
