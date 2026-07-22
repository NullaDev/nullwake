class_name AISolver
extends RefCounted


static func choose_guess(strategy: String, node: Dictionary, history: Array) -> String:
	var candidates := PuzzleEngine.generate_candidates(node)
	var feedback_type: String = node.get("feedback", "full")
	var guessed := {}
	for record: Dictionary in history:
		guessed[record.get("guess", "")] = true
	match strategy:
		"brute_force":
			for candidate in candidates:
				if not guessed.has(candidate):
					return candidate
		"elimination":
			var remaining := _remaining_candidates(candidates, history, feedback_type)
			for candidate in remaining:
				if not guessed.has(candidate):
					return candidate
		"information_gain":
			return _information_guess(candidates, history, guessed, feedback_type)
	for candidate in candidates:
		if not guessed.has(candidate):
			return candidate
	return ""


static func candidate_count(node: Dictionary, history: Array) -> int:
	return _remaining_candidates(PuzzleEngine.generate_candidates(node), history, node.get("feedback", "full")).size()


static func _remaining_candidates(candidates: Array[String], history: Array, feedback_type: String) -> Array[String]:
	var result: Array[String] = []
	for candidate in candidates:
		if PuzzleEngine.candidate_consistent(candidate, history, feedback_type):
			result.append(candidate)
	return result


static func _information_guess(all_guesses: Array[String], history: Array, guessed: Dictionary, feedback_type: String) -> String:
	var remaining := _remaining_candidates(all_guesses, history, feedback_type)
	if remaining.size() <= 2:
		for candidate in remaining:
			if not guessed.has(candidate):
				return candidate
	var guess_pool := all_guesses
	if guess_pool.size() > 256:
		guess_pool = remaining.slice(0, 256)
	var best_guess := ""
	var best_score := INF
	var best_is_candidate := false
	var remaining_lookup := {}
	for candidate in remaining:
		remaining_lookup[candidate] = true
	for possible_guess in guess_pool:
		if guessed.has(possible_guess):
			continue
		var partitions := {}
		for candidate in remaining:
			var result := PuzzleEngine.visible_feedback(candidate, possible_guess, feedback_type)
			var key := "%d:%d" % [result.exact, result.misplaced]
			partitions[key] = int(partitions.get(key, 0)) + 1
		var squared_sum := 0.0
		for size: int in partitions.values():
			squared_sum += size * size
		var is_candidate := remaining_lookup.has(possible_guess)
		if squared_sum < best_score or (is_equal_approx(squared_sum, best_score) and is_candidate and not best_is_candidate):
			best_score = squared_sum
			best_guess = possible_guess
			best_is_candidate = is_candidate
	return best_guess
