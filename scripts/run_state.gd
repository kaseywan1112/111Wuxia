extends RefCounted

## Match-3 roguelike rules. y = 0 is the top of the board; gems fall toward y = SIZE - 1.
## Board RNG and upgrade RNG are separate streams of the same run seed, so a run is
## reproducible and upgrade offers do not depend on which swaps the player made.

const SIZE := 8
const COLORS := 5
const FLOORS := 5
const BASE_MOVES := 13
const UPGRADE_IDS: Array[String] = ["moves", "damage", "bomb", "cascade", "long", "flat"]
const ENEMY_NAMES: Array[String] = ["山门小贼", "林中恶霸", "黑风寨主", "玄铁卫", "守关人"]
const FLOOR_HP: Array[int] = [230, 340, 470, 620, 800]

var seed_value: int = 1
var board_rng := RandomNumberGenerator.new()
var upgrade_rng := RandomNumberGenerator.new()

var floor_index: int = 1
var moves_left: int = 0
var enemy_hp: int = 0
var enemy_max_hp: int = 0
var enemy_name: String = ""
var cells: Array[int] = []
var stacks: Dictionary = {}
var offer: Array = []


func _init() -> void:
	cells.resize(SIZE * SIZE)
	cells.fill(-1)


func start_run(new_seed: int) -> Dictionary:
	seed_value = new_seed if new_seed != 0 else 1
	board_rng.seed = seed_value
	var upgrade_seed := int(seed_value ^ 0x9E3779B9)
	if upgrade_seed == 0 or upgrade_seed == seed_value:
		upgrade_seed = seed_value + 1
	upgrade_rng.seed = upgrade_seed
	stacks = {}
	offer = []
	floor_index = 1
	return begin_floor()


func begin_floor() -> Dictionary:
	floor_index = clampi(floor_index, 1, FLOORS)
	enemy_name = _enemy_name_for(floor_index)
	enemy_max_hp = _hp_for(floor_index)
	enemy_hp = enemy_max_hp
	moves_left = BASE_MOVES + 3 * _stack("moves")
	var steps: Array = []
	_generate_stable_board(steps)
	var bombs := _stack("bomb")
	for _i_bomb in bombs:
		if enemy_hp <= 0:
			break
		_detonate_bomb(steps)
	if enemy_hp > 0 and not has_move():
		_generate_stable_board(steps, "没有可消除的交换，棋盘已重排")
	var dealt := enemy_max_hp - enemy_hp
	var message := ""
	if enemy_hp <= 0:
		message = "开场爆弹击败了敌人"
	elif dealt > 0:
		message = "开场爆弹造成 %d 点伤害" % dealt
	var outcome := "floor_clear" if enemy_hp <= 0 else "continue"
	return {"steps": steps, "outcome": outcome, "message": message, "damage": dealt}


func commit_swap(a: Vector2i, b: Vector2i) -> Dictionary:
	var result := {
		"accepted": false,
		"steps": [],
		"damage": 0,
		"outcome": "continue",
		"message": "",
	}
	if not _inside(a) or not _inside(b) or not _adjacent(a, b):
		result["message"] = "只能交换相邻的宝石"
		return result
	if moves_left <= 0 or enemy_hp <= 0:
		result["message"] = "这一层已经结束"
		return result
	if not _would_match(a, b):
		_swap(a, b)
		var swapped := cells.duplicate()
		_swap(a, b)
		result["steps"] = [
			{"kind": "board", "board": swapped, "enemy_hp": enemy_hp, "delay": 0.16},
			{"kind": "board", "board": cells.duplicate(), "enemy_hp": enemy_hp, "delay": 0.1},
		]
		result["message"] = "不能消除，交换已弹回"
		return result

	_swap(a, b)
	moves_left -= 1
	result["accepted"] = true
	result["steps"].append({"kind": "board", "board": cells.duplicate(), "enemy_hp": enemy_hp, "delay": 0.08})
	var dealt: int = _resolve(result["steps"])
	result["damage"] = dealt
	if enemy_hp <= 0:
		result["outcome"] = "floor_clear"
		result["message"] = "造成 %d 点伤害，敌人被击败" % dealt
	elif moves_left <= 0:
		result["outcome"] = "lose"
		result["message"] = "造成 %d 点伤害，步数耗尽" % dealt
	elif not has_move():
		_generate_stable_board(result["steps"], "没有可消除的交换，棋盘已重排")
		if enemy_hp <= 0:
			result["outcome"] = "floor_clear"
			result["message"] = "造成 %d 点伤害，敌人被击败" % dealt
		else:
			result["message"] = "没有可消除的交换，棋盘已重排"
	elif _had_cascade(result["steps"]):
		result["message"] = "造成 %d 点伤害（含连锁）" % dealt
	else:
		result["message"] = "造成 %d 点伤害" % dealt
	return result


func roll_offers() -> void:
	var pool: Array[String] = []
	for id in UPGRADE_IDS:
		pool.append(id)
	offer = []
	for _n in 3:
		var index := upgrade_rng.randi() % pool.size()
		var id := pool[index]
		pool.remove_at(index)
		offer.append({
			"id": id,
			"name": upgrade_name(id),
			"desc": upgrade_desc(id),
		})


func choose_upgrade(index: int) -> bool:
	if index < 0 or index >= offer.size():
		return false
	var id := str(offer[index]["id"])
	stacks[id] = _stack(id) + 1
	offer = []
	floor_index += 1
	return true


func upgrade_summary() -> String:
	var parts := PackedStringArray()
	for id in UPGRADE_IDS:
		var count := _stack(id)
		if count <= 0:
			continue
		if count == 1:
			parts.append(upgrade_name(id))
		else:
			parts.append("%s ×%d" % [upgrade_name(id), count])
	if parts.is_empty():
		return "无"
	return "、".join(parts)


func upgrade_name(id: String) -> String:
	match id:
		"moves":
			return "步数充盈"
		"damage":
			return "锋锐宝石"
		"bomb":
			return "开场爆弹"
		"cascade":
			return "连锁余波"
		"long":
			return "四连精通"
		"flat":
			return "厚积伤害"
		_:
			return id


func upgrade_desc(id: String) -> String:
	match id:
		"moves":
			return "之后每层开始时，步数 +3。可叠加。"
		"damage":
			return "所有消除与爆弹伤害 +25%。可叠加。"
		"bomb":
			return "每层开始时，额外引爆一处随机 3×3，不消耗步数。可叠加。"
		"cascade":
			return "连锁消除（第 2 波及之后）伤害 +50%。可叠加。"
		"long":
			return "4 连及以上的每次消除额外 +12 伤害。可叠加。"
		"flat":
			return "每次消除的基础伤害 +6。可叠加。"
		_:
			return ""


func damage_for_group(length: int, cascade_index: int) -> int:
	var base := 12
	if length == 4:
		base = 24
	elif length >= 5:
		base = 24 + (length - 4) * 14
	base += 6 * _stack("flat")
	if length >= 4:
		base += 12 * _stack("long")
	var mult := 1.0 + 0.25 * float(_stack("damage"))
	if cascade_index > 0:
		mult += 0.5 * float(_stack("cascade"))
	return maxi(roundi(float(base) * mult), 1)


func has_match() -> bool:
	return not find_match_groups().is_empty()


func has_move() -> bool:
	return not list_moves().is_empty()


func list_moves() -> Array:
	var moves: Array = []
	for y in SIZE:
		for x in SIZE:
			var origin := Vector2i(x, y)
			if x + 1 < SIZE:
				var right := Vector2i(x + 1, y)
				if _would_match(origin, right):
					moves.append([origin, right])
			if y + 1 < SIZE:
				var below := Vector2i(x, y + 1)
				if _would_match(origin, below):
					moves.append([origin, below])
	return moves


func find_match_groups() -> Array:
	var groups: Array = []
	for y in SIZE:
		var run_start := 0
		for x in range(SIZE + 1):
			var broke := x == SIZE
			if not broke:
				var color := cells[_index(x, y)]
				var start_color := cells[_index(run_start, y)]
				broke = color != start_color or color < 0
			if broke:
				var start_color := cells[_index(run_start, y)]
				if start_color >= 0 and x - run_start >= 3:
					var group: Array[Vector2i] = []
					for i in range(run_start, x):
						group.append(Vector2i(i, y))
					groups.append(group)
				run_start = x
	for x in SIZE:
		var run_start := 0
		for y in range(SIZE + 1):
			var broke := y == SIZE
			if not broke:
				var color := cells[_index(x, y)]
				var start_color := cells[_index(x, run_start)]
				broke = color != start_color or color < 0
			if broke:
				var start_color := cells[_index(x, run_start)]
				if start_color >= 0 and y - run_start >= 3:
					var group: Array[Vector2i] = []
					for i in range(run_start, y):
						group.append(Vector2i(x, i))
					groups.append(group)
				run_start = y
	return groups


func clone() -> RefCounted:
	var copy = get_script().new()
	copy.seed_value = seed_value
	copy.floor_index = floor_index
	copy.moves_left = moves_left
	copy.enemy_hp = enemy_hp
	copy.enemy_max_hp = enemy_max_hp
	copy.enemy_name = enemy_name
	copy.cells = cells.duplicate()
	copy.stacks = stacks.duplicate(true)
	copy.offer = offer.duplicate(true)
	copy.board_rng.seed = board_rng.seed
	copy.board_rng.state = board_rng.state
	copy.upgrade_rng.seed = upgrade_rng.seed
	copy.upgrade_rng.state = upgrade_rng.state
	return copy


func last_board_matches(steps: Array) -> bool:
	for i in range(steps.size() - 1, -1, -1):
		if str(steps[i].get("kind", "")) != "board":
			continue
		var board: Array = steps[i]["board"]
		if board.size() != cells.size():
			return false
		for j in cells.size():
			if int(board[j]) != int(cells[j]):
				return false
		return true
	return false


func _resolve(steps: Array) -> int:
	var total := 0
	var cascade := 0
	while cascade < 40:
		var groups := find_match_groups()
		if groups.is_empty():
			return total
		var matched: Array[Vector2i] = []
		var seen := {}
		var dealt := 0
		for group in groups:
			dealt += damage_for_group(group.size(), cascade)
			for cell in group:
				var key := int(cell.x) + int(cell.y) * SIZE
				if seen.has(key):
					continue
				seen[key] = true
				matched.append(cell)
		total += dealt
		enemy_hp = maxi(enemy_hp - dealt, 0)
		steps.append({
			"kind": "clear",
			"matched": matched.duplicate(),
			"damage": dealt,
			"cascade": cascade,
			"enemy_hp": enemy_hp,
		})
		for cell in matched:
			cells[_index(cell.x, cell.y)] = -1
		_gravity_and_refill()
		steps.append({"kind": "board", "board": cells.duplicate(), "enemy_hp": enemy_hp, "delay": 0.12})
		cascade += 1
		if enemy_hp <= 0:
			return total
	_break_remaining_matches()
	steps.append({"kind": "board", "board": cells.duplicate(), "enemy_hp": enemy_hp, "delay": 0.12})
	return total


func _break_remaining_matches() -> void:
	for _attempt in 12:
		var groups := find_match_groups()
		if groups.is_empty():
			return
		for group in groups:
			var cell: Vector2i = group[0]
			cells[_index(cell.x, cell.y)] = board_rng.randi_range(0, COLORS - 1)
	_fill_avoiding()


func _detonate_bomb(steps: Array) -> void:
	var spots: Array[Vector2i] = []
	for y in SIZE:
		for x in SIZE:
			if cells[_index(x, y)] >= 0:
				spots.append(Vector2i(x, y))
	if spots.is_empty():
		return
	var center: Vector2i = spots[board_rng.randi() % spots.size()]
	var matched: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cell := center + Vector2i(dx, dy)
			if not _inside(cell):
				continue
			if cells[_index(cell.x, cell.y)] < 0:
				continue
			matched.append(cell)
	var mult := 1.0 + 0.25 * float(_stack("damage"))
	var dealt := roundi(float(matched.size()) * 6.0 * mult)
	dealt = maxi(dealt, 1)
	enemy_hp = maxi(enemy_hp - dealt, 0)
	steps.append({
		"kind": "bomb",
		"matched": matched.duplicate(),
		"damage": dealt,
		"cascade": 0,
		"enemy_hp": enemy_hp,
		"center": center,
	})
	for cell in matched:
		cells[_index(cell.x, cell.y)] = -1
	_gravity_and_refill()
	steps.append({"kind": "board", "board": cells.duplicate(), "enemy_hp": enemy_hp, "delay": 0.12})
	if enemy_hp > 0:
		_resolve(steps)


func _generate_stable_board(steps: Array, note: String = "") -> void:
	for _attempt in 80:
		_fill_avoiding()
		if not has_match() and has_move():
			_append_board(steps, note)
			return
	_fill_avoiding()
	_append_board(steps, note)


func _append_board(steps: Array, note: String) -> void:
	var step := {"kind": "board", "board": cells.duplicate(), "enemy_hp": enemy_hp, "delay": 0.12}
	if note != "":
		step["message"] = note
	steps.append(step)


func _fill_avoiding() -> void:
	for y in SIZE:
		for x in SIZE:
			cells[_index(x, y)] = _color_avoiding(x, y)


func _color_avoiding(x: int, y: int) -> int:
	var banned := {}
	if x >= 2:
		var left := cells[_index(x - 1, y)]
		if left >= 0 and left == cells[_index(x - 2, y)]:
			banned[left] = true
	if y >= 2:
		var above := cells[_index(x, y - 1)]
		if above >= 0 and above == cells[_index(x, y - 2)]:
			banned[above] = true
	var options: Array[int] = []
	for color in COLORS:
		if not banned.has(color):
			options.append(color)
	if options.is_empty():
		return board_rng.randi_range(0, COLORS - 1)
	return options[board_rng.randi() % options.size()]


func _compact() -> void:
	for x in SIZE:
		var stack: Array[int] = []
		for y in range(SIZE - 1, -1, -1):
			var color := cells[_index(x, y)]
			if color >= 0:
				stack.append(color)
		for y in SIZE:
			cells[_index(x, y)] = -1
		for i in stack.size():
			cells[_index(x, SIZE - 1 - i)] = stack[i]


func _gravity_and_refill() -> void:
	_compact()
	for y in SIZE:
		for x in SIZE:
			if cells[_index(x, y)] < 0:
				cells[_index(x, y)] = board_rng.randi_range(0, COLORS - 1)


func _would_match(a: Vector2i, b: Vector2i) -> bool:
	_swap(a, b)
	var matched := has_match()
	_swap(a, b)
	return matched


func _swap(a: Vector2i, b: Vector2i) -> void:
	var ia := _index(a.x, a.y)
	var ib := _index(b.x, b.y)
	var tmp := cells[ia]
	cells[ia] = cells[ib]
	cells[ib] = tmp


func _had_cascade(steps: Array) -> bool:
	for step in steps:
		if str(step.get("kind", "")) == "clear" and int(step.get("cascade", 0)) > 0:
			return true
	return false


func _hp_for(floor_n: int) -> int:
	var index := clampi(floor_n, 1, FLOORS) - 1
	return FLOOR_HP[index]


func _enemy_name_for(floor_n: int) -> String:
	var index := clampi(floor_n, 1, FLOORS) - 1
	return ENEMY_NAMES[index]


func _stack(id: String) -> int:
	return int(stacks.get(id, 0))


func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < SIZE and cell.y < SIZE


func _adjacent(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) == 1


func _index(x: int, y: int) -> int:
	return y * SIZE + x
