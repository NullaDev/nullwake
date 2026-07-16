extends SceneTree

var failures := 0


func _initialize() -> void:
	_test_feedback()
	_test_candidates()
	_test_ai()
	if failures == 0:
		print("NULLWAKE TESTS: 13 assertions passed")
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


func _test_ai() -> void:
	var node := {"length": 3, "radix": 2, "allow_duplicates": true, "protocol": "standard"}
	var history := [{"guess": "000", "feedback": PuzzleEngine.feedback("101", "000")}]
	var guess := AISolver.choose_guess("elimination", node, history)
	_expect(guess != "000", "AI must not repeat a submitted complete guess")
