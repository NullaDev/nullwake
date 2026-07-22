class_name PuzzleEngine
extends RefCounted


static func feedback(secret: String, guess: String) -> Dictionary:
	var exact := 0
	var secret_used: Array[bool] = []
	var guess_used: Array[bool] = []
	secret_used.resize(secret.length())
	guess_used.resize(guess.length())
	secret_used.fill(false)
	guess_used.fill(false)
	for i in range(mini(secret.length(), guess.length())):
		if secret[i] == guess[i]:
			exact += 1
			secret_used[i] = true
			guess_used[i] = true
	var misplaced := 0
	for guess_index in range(guess.length()):
		if guess_used[guess_index]:
			continue
		for secret_index in range(secret.length()):
			if secret_used[secret_index]:
				continue
			if guess[guess_index] == secret[secret_index]:
				misplaced += 1
				guess_used[guess_index] = true
				secret_used[secret_index] = true
				break
	return {"exact": exact, "misplaced": misplaced}


static func visible_feedback(secret: String, guess: String, feedback_type: String) -> Dictionary:
	var result := feedback(secret, guess)
	match feedback_type:
		"exact_only":
			result["misplaced"] = -1
		"total_only":
			result = {"exact": -1, "misplaced": result.exact + result.misplaced}
	return result


static func validate_guess(guess: String, node: Dictionary) -> String:
	var expected_length: int = int(node.get("length", 3))
	var radix: int = int(node.get("radix", 2))
	if guess.length() != expected_length:
		return "请输入 %d 位协议。" % expected_length
	var seen := {}
	for character in guess:
		var value := int(character)
		if character < "0" or character > "9" or value >= radix:
			return "每一位只能使用 0—%d。" % (radix - 1)
		if not bool(node.get("allow_duplicates", true)):
			if seen.has(character):
				return "该协议不允许重复数字。"
			seen[character] = true
	if node.get("protocol", "standard") == "mirror":
		# Guesses need not be mirrored; off-pattern guesses can still reveal information.
		pass
	return ""


static func generate_candidates(node: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var length: int = int(node.get("length", 3))
	var radix: int = int(node.get("radix", 2))
	var total := int(pow(radix, length))
	for number in range(total):
		var value := number
		var candidate := ""
		for _position in range(length):
			candidate = str(value % radix) + candidate
			value /= radix
		if not _candidate_matches_rule(candidate, node):
			continue
		result.append(candidate)
	return result


static func _candidate_matches_rule(candidate: String, node: Dictionary) -> bool:
	if not bool(node.get("allow_duplicates", true)):
		var seen := {}
		for character in candidate:
			if seen.has(character):
				return false
			seen[character] = true
	if node.get("protocol", "standard") == "mirror":
		for i in range(candidate.length() / 2):
			if candidate[i] != candidate[candidate.length() - i - 1]:
				return false
	if node.get("protocol", "standard") == "checksum":
		if candidate.length() < 2:
			return false
		var checksum := 0
		for i in range(candidate.length() - 1):
			checksum += int(candidate[i])
		if checksum % int(node.get("radix", 2)) != int(candidate[candidate.length() - 1]):
			return false
	return true


static func generate_secret(node: Dictionary, seed_value: int) -> String:
	var candidates := generate_candidates(node)
	if candidates.is_empty():
		return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func candidate_consistent(candidate: String, history: Array, feedback_type := "full") -> bool:
	for record: Dictionary in history:
		var expected: Dictionary = record.get("feedback", {})
		var actual := visible_feedback(candidate, record.get("guess", ""), feedback_type)
		if int(expected.get("exact", -1)) >= 0 and actual.exact != int(expected.exact):
			return false
		if int(expected.get("misplaced", -1)) >= 0 and actual.misplaced != int(expected.misplaced):
			return false
	return true
