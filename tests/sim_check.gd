extends SceneTree

const Rules = preload("res://scripts/run_state.gd")

var errors: Array[String] = []


func _init() -> void:
	_test_matches_and_gravity()
	_test_damage_table()
	_test_opening_board()
	_test_reject_and_accept()
	_test_seed_coherence()
	_test_scripted_clear_loop()
	_test_lose_when_moves_hit_zero()
	var greedy := _playout(true, 24)
	var random_bot := _playout(false, 24)
	print("GREEDY ", greedy)
	print("RANDOM ", random_bot)
	if errors.is_empty():
		print("SIM_OK")
		quit(0)
	else:
		for err in errors:
			print("FAIL ", err)
		quit(1)


func _test_matches_and_gravity() -> void:
	var state = Rules.new()
	state.cells.fill(-1)
	for i in 3:
		state.cells[i] = 1
	for i in range(3, 6):
		state.cells[i] = 2
	var groups: Array = state.find_match_groups()
	_check(groups.size() == 2, "two horizontal groups, got %d" % groups.size())

	state.cells.fill(-1)
	for y in 4:
		state.cells[y * Rules.SIZE] = 3
	groups = state.find_match_groups()
	_check(groups.size() == 1 and groups[0].size() == 4, "vertical 4-match")

	state.cells.fill(0)
	for y in Rules.SIZE:
		state.cells[y * Rules.SIZE] = [0, -1, 1, -1, 2, 2, -1, 3][y]
	state._compact()
	var column: Array[int] = []
	for y in Rules.SIZE:
		column.append(int(state.cells[y * Rules.SIZE]))
	_check(column == [-1, -1, -1, 0, 1, 2, 2, 3], "gravity compacts toward the bottom, got %s" % str(column))


func _test_damage_table() -> void:
	var state = Rules.new()
	var three := int(state.damage_for_group(3, 0))
	var four := int(state.damage_for_group(4, 0))
	var five := int(state.damage_for_group(5, 0))
	_check(four > three, "4-match outdamages 3-match")
	_check(five > four, "5-match outdamages 4-match")
	_check(int(state.damage_for_group(3, 1)) == three, "cascade index does nothing without the upgrade")
	state.stacks["cascade"] = 1
	_check(int(state.damage_for_group(3, 0)) == three, "first wave is not a cascade")
	_check(int(state.damage_for_group(3, 1)) > three, "cascade upgrade boosts later waves")
	state.stacks["damage"] = 1
	_check(int(state.damage_for_group(3, 0)) > three, "damage upgrade increases match damage")


func _test_opening_board() -> void:
	for seed_value in range(1, 41):
		var state = Rules.new()
		var opened: Dictionary = state.start_run(seed_value)
		_check(not state.has_match() or state.enemy_hp <= 0, "opening board stable seed %d" % seed_value)
		_check(state.has_move() or state.enemy_hp <= 0, "opening board has a move seed %d" % seed_value)
		_check(state.moves_left == Rules.BASE_MOVES, "base moves")
		_check(state.enemy_hp == state.enemy_max_hp, "bomb-less open does not damage")
		_check(state.last_board_matches(opened["steps"]), "open steps end on the live board")
		_check(str(opened["outcome"]) == "continue", "first floor does not auto-clear")


func _test_reject_and_accept() -> void:
	var state = Rules.new()
	state.start_run(5)
	var legal := {}
	for move in state.list_moves():
		legal["%s|%s" % [move[0], move[1]]] = true
	var rejected := false
	for y in Rules.SIZE:
		for x in Rules.SIZE:
			var neighbors: Array[Vector2i] = []
			if x + 1 < Rules.SIZE:
				neighbors.append(Vector2i(x + 1, y))
			if y + 1 < Rules.SIZE:
				neighbors.append(Vector2i(x, y + 1))
			for neighbor in neighbors:
				var origin := Vector2i(x, y)
				if legal.has("%s|%s" % [origin, neighbor]):
					continue
				var before: Array = state.cells.duplicate()
				var moves_before := int(state.moves_left)
				var result: Dictionary = state.commit_swap(origin, neighbor)
				_check(result["accepted"] == false, "illegal swap rejected")
				_check(int(state.moves_left) == moves_before, "illegal swap spends no move")
				_check(_same_cells(before, state.cells), "illegal swap restores the board")
				rejected = true
				break
			if rejected:
				break
		if rejected:
			break
	_check(rejected, "found an illegal adjacent swap")

	state = Rules.new()
	state.start_run(5)
	var move: Array = state.list_moves()[0]
	var moves_before := int(state.moves_left)
	var hp_before := int(state.enemy_hp)
	var result: Dictionary = state.commit_swap(move[0], move[1])
	_check(result["accepted"] == true, "legal swap accepted")
	_check(int(state.moves_left) == moves_before - 1, "legal swap spends one move")
	_check(int(result["damage"]) > 0, "legal swap deals damage")
	_check(int(state.enemy_hp) == hp_before - int(result["damage"]), "hp tracks damage")
	_check(not state.has_match(), "board stable after resolve")
	_check(state.last_board_matches(result["steps"]), "swap steps end on the live board")


func _test_seed_coherence() -> void:
	var first = Rules.new()
	var second = Rules.new()
	first.start_run(42)
	second.start_run(42)
	_check(_same_cells(first.cells, second.cells), "same seed, same opening board")
	var move: Array = first.list_moves()[0]
	first.commit_swap(move[0], move[1])
	first.roll_offers()
	second.roll_offers()
	_check(_offer_key(first) == _offer_key(second), "offers ignore how the board was played")
	second.commit_swap(move[0], move[1])
	_check(_same_cells(first.cells, second.cells), "same seed and same swap, same board")
	_check(int(first.enemy_hp) == int(second.enemy_hp), "same damage")

	var offer_keys := {}
	var board_keys := {}
	for seed_value in range(1, 31):
		var state = Rules.new()
		state.start_run(1000 + seed_value)
		board_keys[str(state.cells)] = true
		state.roll_offers()
		offer_keys[_offer_key(state)] = true
	_check(board_keys.size() > 1, "different seeds roll different boards")
	_check(offer_keys.size() > 1, "different seeds roll different upgrade offers")


func _test_scripted_clear_loop() -> void:
	var state = Rules.new()
	state.start_run(12345)
	for expected_floor in range(1, Rules.FLOORS + 1):
		_check(int(state.floor_index) == expected_floor, "scripted floor %d" % expected_floor)
		if int(state.enemy_hp) > 0:
			state.enemy_hp = 1
			var moves: Array = state.list_moves()
			_check(not moves.is_empty(), "scripted floor has a move")
			if moves.is_empty():
				return
			var result: Dictionary = state.commit_swap(moves[0][0], moves[0][1])
			_check(str(result["outcome"]) == "floor_clear", "one hit clears a 1-hp enemy")
		if expected_floor == Rules.FLOORS:
			break
		state.roll_offers()
		_check(state.offer.size() == 3, "three upgrade offers")
		_check(state.choose_upgrade(0), "pick the first offer")
		state.begin_floor()
	_check(int(state.floor_index) == Rules.FLOORS, "ended on the last floor")
	_check(int(state.enemy_hp) <= 0, "last enemy defeated")
	var kept := 0
	for id in state.stacks.keys():
		kept += int(state.stacks[id])
	_check(kept == Rules.FLOORS - 1, "upgrades kept across the run, got %d" % kept)


func _test_lose_when_moves_hit_zero() -> void:
	var state = Rules.new()
	state.start_run(9)
	state.moves_left = 1
	state.enemy_hp = 999999
	var move: Array = state.list_moves()[0]
	var result: Dictionary = state.commit_swap(move[0], move[1])
	_check(str(result["outcome"]) == "lose", "moves hitting zero loses the run")
	_check(int(state.moves_left) == 0, "no moves remain")
	_check(int(state.enemy_hp) > 0, "enemy still standing")


func _playout(greedy: bool, count: int) -> Dictionary:
	var wins := 0
	var floor_sum := 0
	var stuck := 0
	for n in count:
		var outcome := _play_one(100 + n, greedy)
		if outcome.begins_with("win"):
			wins += 1
			floor_sum += Rules.FLOORS
		elif outcome.begins_with("lose"):
			var at := int(outcome.get_slice(" ", 1))
			floor_sum += at
		else:
			stuck += 1
			print("PLAYOUT ", outcome)
	return {"wins": wins, "avg_floor": float(floor_sum) / float(count), "stuck": stuck, "games": count}


func _play_one(seed_value: int, greedy: bool) -> String:
	var state = Rules.new()
	var roller := RandomNumberGenerator.new()
	roller.seed = seed_value * 17 + 3
	var opened: Dictionary = state.start_run(seed_value)
	var guard := 0
	while guard < 500:
		guard += 1
		if int(state.enemy_hp) <= 0 or str(opened.get("outcome", "")) == "floor_clear":
			if int(state.floor_index) >= Rules.FLOORS:
				return "win"
			state.roll_offers()
			state.choose_upgrade(_best_offer(state))
			opened = state.begin_floor()
			continue
		if int(state.moves_left) <= 0:
			return "lose %d" % int(state.floor_index)
		var move: Array = _best_move(state) if greedy else _random_move(state, roller)
		if move.is_empty():
			return "stuck %d" % int(state.floor_index)
		var result: Dictionary = state.commit_swap(move[0], move[1])
		opened = {"outcome": result["outcome"]}
		if str(result["outcome"]) == "lose":
			return "lose %d" % int(state.floor_index)
	return "timeout %d" % int(state.floor_index)


func _best_move(state) -> Array:
	var best: Array = []
	var best_score := -1
	for move in state.list_moves():
		var copy = state.clone()
		var result: Dictionary = copy.commit_swap(move[0], move[1])
		var score := int(result["damage"])
		if int(copy.enemy_hp) <= 0:
			score += 100000
		if score > best_score:
			best_score = score
			best = move
	return best


func _random_move(state, roller: RandomNumberGenerator) -> Array:
	var moves: Array = state.list_moves()
	if moves.is_empty():
		return []
	return moves[roller.randi() % moves.size()]


func _best_offer(state) -> int:
	var priority := ["damage", "long", "cascade", "moves", "flat", "bomb"]
	var best_index := 0
	var best_rank := 99
	for i in state.offer.size():
		var rank := priority.find(str(state.offer[i]["id"]))
		if rank >= 0 and rank < best_rank:
			best_rank = rank
			best_index = i
	return best_index


func _offer_key(state) -> String:
	var parts: PackedStringArray = []
	for item in state.offer:
		parts.append(str(item["id"]))
	return "|".join(parts)


func _same_cells(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if int(a[i]) != int(b[i]):
			return false
	return true


func _check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)
		print("FAIL ", message)
