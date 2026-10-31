extends Control

const Rules = preload("res://scripts/run_state.gd")

const COLS := 13
const R := 28.0
const COL_STEP := 56.0
const ROW_STEP := 48.5
const FIELD_W := 760.0
const FIELD_H := 690.0
const SHOT_SPEED := 860.0
const CREEP_SPEED := 13.0
const BURST_GAP := 0.22
const DEATH_Y := 572.0

signal chained(color_index: int, length: int, positions: Array)
signal basics(color_index: int, amount: float, at: Vector2)
signal cleared(count: int)
signal crushed
signal waved(wave_number: int)

var accept_input := false
var running := false
var dead := false
var state: Rules = null

var _cells: Array = []
var _shots: Array = []
var _burst: Array[int] = []
var _burst_wait := 0.0
var _knife_time := 0.6
var _book_time := 1.4
var _creep := 0.0
var _row_timer := 11.0
var _freeze := 0.0
var _aim := 0.0
var _next_id := 1
var _aim_line: Line2D
var _player: Node2D
var _freeze_tint: ColorRect


func _ready() -> void:
	custom_minimum_size = Vector2(FIELD_W, FIELD_H)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	var background := ColorRect.new()
	background.color = Color("10151d")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_freeze_tint = ColorRect.new()
	_freeze_tint.color = Color(0.45, 0.75, 1.0, 0.18)
	_freeze_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_freeze_tint.visible = false
	_freeze_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_freeze_tint)
	_aim_line = Line2D.new()
	_aim_line.width = 3.0
	_aim_line.default_color = Color(1, 1, 1, 0.45)
	_aim_line.z_index = 5
	add_child(_aim_line)
	_player = Node2D.new()
	_player.z_index = 6
	add_child(_player)
	var base := Polygon2D.new()
	base.polygon = PackedVector2Array([
		Vector2(-26, 16), Vector2(26, 16), Vector2(18, -8), Vector2(-18, -8),
	])
	base.color = Color("d9c7a2")
	_player.add_child(base)
	var nozzle := Polygon2D.new()
	nozzle.polygon = PackedVector2Array([
		Vector2(-7, -6), Vector2(7, -6), Vector2(4, -28), Vector2(-4, -28),
	])
	nozzle.color = Color("f4f1ea")
	_player.add_child(nozzle)
	queue_redraw()


func _draw() -> void:
	var wall := Color("6d788c")
	draw_line(Vector2(8, 0), Vector2(8, FIELD_H), wall, 6.0)
	draw_line(Vector2(FIELD_W - 8, 0), Vector2(FIELD_W - 8, FIELD_H), wall, 6.0)
	draw_line(Vector2(8, 10), Vector2(FIELD_W - 8, 10), Color("8aa0b8"), 8.0)
	draw_line(Vector2(18, DEATH_Y), Vector2(FIELD_W - 18, DEATH_Y), Color(0.85, 0.35, 0.32, 0.55), 2.0)


func begin(run_state) -> void:
	state = run_state
	running = true
	dead = false
	accept_input = true
	_clear_board()
	_knife_time = 0.45
	_book_time = 1.2
	_burst.clear()
	_burst_wait = 0.0
	_creep = 0.0
	_row_timer = 11.0
	_freeze = 0.0
	_aim = 0.0
	_spawn_ceiling(5)
	_place_player()


func stop() -> void:
	running = false
	accept_input = false


func next_color() -> int:
	if not _burst.is_empty():
		return _burst[0]
	if state != null and state.has_book and _book_time < _knife_time:
		return Rules.BOOK_SEQUENCE[0]
	return Rules.KNIFE_SEQUENCE[0]


func knife_ratio() -> float:
	if state == null:
		return 0.0
	return clampf(1.0 - _knife_time / maxf(state.knife_interval, 0.1), 0.0, 1.0)


func book_ratio() -> float:
	if state == null or not state.has_book:
		return 0.0
	return clampf(1.0 - _book_time / maxf(state.book_interval, 0.1), 0.0, 1.0)


func arm_book() -> void:
	_book_time = 0.35


func cut_cooldowns(amount: float) -> void:
	_knife_time = maxf(_knife_time - amount, 0.05)
	_book_time = maxf(_book_time - amount, 0.05)


func hurt_color(color_index: int, amount: float) -> int:
	var doomed: Array = []
	for cell in _cells:
		if int(cell["color"]) != color_index:
			continue
		cell["hp"] = float(cell["hp"]) - amount
		_popup(_visual(cell), str(int(round(amount))), Rules.GEM_COLORS[color_index])
		_refresh_bar(cell)
		if float(cell["hp"]) <= 0.0:
			doomed.append(cell)
	return _remove_cells(doomed, true)


func hurt_near(origins: Array, radius: float, amount: float, ignore_color: int = -1) -> int:
	var doomed: Array = []
	for cell in _cells:
		if ignore_color >= 0 and int(cell["color"]) == ignore_color:
			continue
		var pos := _visual(cell)
		var close := false
		for origin in origins:
			var at: Vector2 = origin
			if pos.distance_to(at) <= radius:
				close = true
				break
		if not close:
			continue
		cell["hp"] = float(cell["hp"]) - amount
		_popup(pos, str(int(round(amount))), Color("ffb089"))
		_refresh_bar(cell)
		if float(cell["hp"]) <= 0.0:
			doomed.append(cell)
	return _remove_cells(doomed, true)


func hurt_ids(ids: Array, amount: float) -> int:
	var doomed: Array = []
	var wanted := {}
	for id in ids:
		wanted[int(id)] = true
	for cell in _cells:
		if not wanted.has(int(cell["id"])):
			continue
		cell["hp"] = float(cell["hp"]) - amount
		_popup(_visual(cell), str(int(round(amount))), Color("d7c4ff"))
		_refresh_bar(cell)
		if float(cell["hp"]) <= 0.0:
			doomed.append(cell)
	return _remove_cells(doomed, true)


func nearest_ids(origins: Array, jumps: int, exclude: Array) -> Array:
	var blocked := {}
	for id in exclude:
		blocked[int(id)] = true
	var picked: Array[int] = []
	var froms: Array = origins.duplicate()
	for _n in jumps:
		var best_id := -1
		var best_pos := Vector2.ZERO
		var best_d := 240.0
		for cell in _cells:
			var id := int(cell["id"])
			if blocked.has(id):
				continue
			var pos := _visual(cell)
			for origin in froms:
				var at: Vector2 = origin
				var dist := pos.distance_to(at)
				if dist < best_d:
					best_d = dist
					best_id = id
					best_pos = pos
		if best_id < 0:
			break
		picked.append(best_id)
		blocked[best_id] = true
		if not froms.is_empty():
			var src: Vector2 = froms[0]
			bolt_between(src, best_pos)
		froms = [best_pos]
	return picked


func bolt_between(a: Vector2, b: Vector2) -> void:
	var line := Line2D.new()
	line.width = 4.0
	line.default_color = Color("f3e7ff")
	line.z_index = 7
	line.add_point(a)
	line.add_point(b)
	add_child(line)
	var tween := create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.22)
	tween.tween_callback(line.queue_free)


func vine_marks(pairs: Array) -> void:
	for pair in pairs:
		var line := Line2D.new()
		line.width = 5.0
		line.default_color = Color("7dffa0")
		line.z_index = 7
		line.add_point(pair[0])
		line.add_point(pair[1])
		add_child(line)
		var tween := create_tween()
		tween.tween_property(line, "modulate:a", 0.0, 0.35)
		tween.tween_callback(line.queue_free)


func burst_rings(origins: Array, radius: float) -> void:
	for origin in origins:
		var ring := Polygon2D.new()
		ring.polygon = _hex(radius * 0.45)
		ring.color = Color(1.0, 0.45, 0.2, 0.55)
		ring.position = origin
		ring.z_index = 7
		add_child(ring)
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(ring, "scale", Vector2(2.4, 2.4), 0.22)
		tween.tween_property(ring, "modulate:a", 0.0, 0.22)
		tween.chain().tween_callback(ring.queue_free)


func set_frozen(on: bool) -> void:
	_freeze_tint.visible = on


func neighbor_pairs(origins: Array, hops: int) -> Dictionary:
	var ids: Array[int] = []
	var pairs: Array = []
	var seen := {}
	var frontier: Array = []
	for origin in origins:
		frontier.append(origin)
	for _hop in hops:
		var next: Array = []
		for origin in frontier:
			var at: Vector2 = origin
			for cell in _cells:
				var id := int(cell["id"])
				if seen.has(id):
					continue
				var pos := _visual(cell)
				if pos.distance_to(at) > R * 2.35:
					continue
				seen[id] = true
				ids.append(id)
				pairs.append([at, pos])
				next.append(pos)
		frontier = next
	return {"ids": ids, "pairs": pairs}


func _process(delta: float) -> void:
	if not running:
		return
	_steer(delta)
	_draw_aim()
	_place_player()
	if not accept_input or dead:
		return
	var creep_scale := 0.18 if _freeze > 0.0 else 1.0 as float
	if _freeze > 0.0:
		_freeze = maxf(_freeze - delta, 0.0)
		if _freeze <= 0.0:
			_freeze_tint.visible = false
	_creep += CREEP_SPEED * creep_scale * delta
	_row_timer -= delta
	if _row_timer <= 0.0:
		_row_timer = 11.0
		_push_row()
	_tick_weapons(delta)
	_tick_shots(delta)
	_sync_cells()
	_check_crush()


func _steer(delta: float) -> void:
	var steered := false
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		_aim -= delta * 1.35
		steered = true
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		_aim += delta * 1.35
		steered = true
	_aim = clampf(_aim, -1.15, 1.15)
	if not steered:
		_aim_from_pointer()


func _aim_from_pointer() -> void:
	var mouse := get_local_mouse_position()
	var origin := _player_pos()
	if mouse.distance_to(origin) < 8.0:
		return
	var ang := atan2(mouse.x - origin.x, origin.y - mouse.y)
	_aim = clampf(ang, -1.15, 1.15)


func _player_pos() -> Vector2:
	return Vector2(FIELD_W * 0.5, FIELD_H - 52.0)


func _place_player() -> void:
	_player.position = _player_pos()
	_player.rotation = _aim


func _draw_aim() -> void:
	_aim_line.clear_points()
	var color_index := next_color()
	_aim_line.default_color = Rules.GEM_COLORS[color_index]
	_aim_line.default_color.a = 0.55
	var pos := _player_pos() + _aim_dir() * 36.0
	var dir := _aim_dir()
	_aim_line.add_point(pos)
	var left := 280.0
	while left > 0.0:
		var hit := _ray_limit(pos, dir, left)
		pos += dir * hit
		left -= hit
		_aim_line.add_point(pos)
		if left <= 1.0 or _blocked(pos):
			break
		if pos.x <= R + 10.0:
			dir.x = absf(dir.x)
		elif pos.x >= FIELD_W - R - 10.0:
			dir.x = -absf(dir.x)
		else:
			break


func _ray_limit(pos: Vector2, dir: Vector2, max_dist: float) -> float:
	var limit := max_dist
	if dir.x < -0.01:
		limit = minf(limit, (R + 10.0 - pos.x) / dir.x)
	elif dir.x > 0.01:
		limit = minf(limit, (FIELD_W - R - 10.0 - pos.x) / dir.x)
	return maxf(limit, 8.0)


func _blocked(pos: Vector2) -> bool:
	if pos.y <= R + _creep:
		return true
	for cell in _cells:
		if pos.distance_to(_visual(cell)) <= R * 1.7:
			return true
	return false


func _aim_dir() -> Vector2:
	return Vector2(sin(_aim), -cos(_aim))


func _tick_weapons(delta: float) -> void:
	if state == null:
		return
	_knife_time -= delta
	if _knife_time <= 0.0:
		_knife_time = state.knife_interval
		for color_index in Rules.KNIFE_SEQUENCE:
			_burst.append(int(color_index))
	if state.has_book:
		_book_time -= delta
		if _book_time <= 0.0:
			_book_time = state.book_interval
			for color_index in Rules.BOOK_SEQUENCE:
				_burst.append(int(color_index))
	if _burst.is_empty():
		return
	_burst_wait -= delta
	if _burst_wait > 0.0:
		return
	_fire(_burst[0])
	_burst.remove_at(0)
	_burst_wait = BURST_GAP


func _fire(color_index: int) -> void:
	var node := _make_bubble(color_index, R * 0.72, false)
	var pos := _player_pos() + _aim_dir() * 40.0
	node.position = pos
	node.z_index = 4
	add_child(node)
	_shots.append({
		"color": color_index,
		"pos": pos,
		"dir": _aim_dir(),
		"node": node,
		"life": 0.0,
	})


func _tick_shots(delta: float) -> void:
	var kept: Array = []
	for shot in _shots:
		var pos: Vector2 = shot["pos"]
		var dir: Vector2 = shot["dir"]
		pos += dir * SHOT_SPEED * delta
		shot["life"] = float(shot["life"]) + delta
		if pos.x < R + 8.0:
			pos.x = R + 8.0
			dir.x = absf(dir.x)
		elif pos.x > FIELD_W - R - 8.0:
			pos.x = FIELD_W - R - 8.0
			dir.x = -absf(dir.x)
		shot["pos"] = pos
		shot["dir"] = dir
		var node: Node2D = shot["node"]
		if is_instance_valid(node):
			node.position = pos
		if float(shot["life"]) > 3.5:
			if is_instance_valid(node):
				node.queue_free()
			continue
		if _try_stick(shot):
			continue
		kept.append(shot)
	_shots = kept


func _try_stick(shot: Dictionary) -> bool:
	var pos: Vector2 = shot["pos"]
	var hit: Dictionary = {}
	var best := R * 1.86
	for cell in _cells:
		var dist := pos.distance_to(_visual(cell))
		if dist < best:
			best = dist
			hit = cell
	var ceiling := pos.y <= R + _creep + 2.0
	if hit.is_empty() and not ceiling:
		return false
	var slot := _empty_slot(pos, hit)
	if slot.x < 0:
		return false
	_place_cell(int(shot["color"]), slot.x, slot.y, Rules.MONSTER_HP)
	var node: Node = shot["node"]
	if is_instance_valid(node):
		node.queue_free()
	_resolve_stick(int(shot["color"]), slot, hit)
	return true


func _resolve_stick(color_index: int, slot: Vector2i, hit: Dictionary) -> void:
	var start := _index_at(slot.x, slot.y)
	if start < 0:
		return
	var group: Array = Rules.same_color_component(_logic_cells(), start)
	if group.size() >= Rules.MIN_CHAIN:
		var positions: Array = []
		var doomed: Array = []
		for index in group:
			var cell: Dictionary = _cells[int(index)]
			positions.append(_visual(cell))
			doomed.append(cell)
		_remove_cells(doomed, true)
		chained.emit(color_index, group.size(), positions)
		refill_if_empty()
		return
	if not hit.is_empty() and int(hit["color"]) != color_index:
		var amount := Rules.BASIC_DAMAGE
		hit["hp"] = float(hit["hp"]) - amount
		_popup(_visual(hit), str(int(amount)), Color("f4f1ea"))
		_refresh_bar(hit)
		basics.emit(color_index, amount, _visual(hit))
		if float(hit["hp"]) <= 0.0:
			_remove_cells([hit], true)
			refill_if_empty()


func _empty_slot(pos: Vector2, hit: Dictionary) -> Vector2i:
	var candidates: Array = []
	if hit.is_empty():
		var col := clampi(int(round((pos.x - R) / COL_STEP)), 0, Rules.row_width(0, COLS) - 1)
		for offset in [0, -1, 1, -2, 2]:
			var near: int = col + int(offset)
			if near >= 0 and near < Rules.row_width(0, COLS):
				candidates.append(Vector2i(near, 0))
			if near >= 0 and near < Rules.row_width(1, COLS):
				candidates.append(Vector2i(near, 1))
	else:
		for npos in Rules.neighbors(int(hit["col"]), int(hit["row"])):
			var spot: Vector2i = npos
			if spot.y < 0 or spot.x < 0 or spot.x >= Rules.row_width(spot.y, COLS):
				continue
			candidates.append(spot)
	var best := Vector2i(-1, -1)
	var best_d := 99999.0
	for spot in candidates:
		var cell: Vector2i = spot
		if _index_at(cell.x, cell.y) >= 0:
			continue
		var dist := pos.distance_to(_nominal(cell.x, cell.y))
		if dist < best_d:
			best_d = dist
			best = cell
	return best


func _logic_cells() -> Array:
	var rows: Array = []
	for cell in _cells:
		rows.append({"col": int(cell["col"]), "row": int(cell["row"]), "color": int(cell["color"])})
	return rows


func _index_at(col: int, row: int) -> int:
	for i in _cells.size():
		var cell: Dictionary = _cells[i]
		if int(cell["col"]) == col and int(cell["row"]) == row:
			return i
	return -1


func _remove_cells(doomed: Array, count_clear: bool) -> int:
	if doomed.is_empty():
		return 0
	var gone := {}
	for cell in doomed:
		gone[int(cell["id"])] = true
	var kept: Array = []
	var removed := 0
	for cell in _cells:
		if gone.has(int(cell["id"])):
			_pop_node(cell)
			removed += 1
		else:
			kept.append(cell)
	_cells = kept
	var fallen := _drop_floating()
	var total := removed + fallen
	if count_clear and total > 0:
		cleared.emit(total)
	elif removed > 0 and not count_clear:
		cleared.emit(removed)
	return total


func _drop_floating() -> int:
	var floating: Array = Rules.floating_indices(_logic_cells())
	if floating.is_empty():
		return 0
	var doomed: Array = []
	for index in floating:
		doomed.append(_cells[int(index)])
	var gone := {}
	for cell in doomed:
		gone[int(cell["id"])] = true
		_fall_node(cell)
	var kept: Array = []
	for cell in _cells:
		if not gone.has(int(cell["id"])):
			kept.append(cell)
	_cells = kept
	return doomed.size()


func _check_crush() -> void:
	for cell in _cells:
		if _visual(cell).y + R >= DEATH_Y:
			dead = true
			accept_input = false
			crushed.emit()
			return


func refill_if_empty() -> void:
	if running and _cells.is_empty() and not dead:
		_next_wave()


func _next_wave() -> void:
	if state != null:
		state.wave += 1
	_creep = 0.0
	_spawn_ceiling(5 + mini(state.wave if state != null else 1, 3))
	waved.emit(state.wave if state != null else 1)


func _push_row() -> void:
	for cell in _cells:
		cell["row"] = int(cell["row"]) + 1
	_creep = maxf(_creep - ROW_STEP, 0.0)
	_fill_row(0)
	_sync_cells()


func _spawn_ceiling(rows: int) -> void:
	for row in rows:
		_fill_row(row)


func _fill_row(row: int) -> void:
	var width := Rules.row_width(row, COLS)
	var wave: int = 1 if state == null else state.wave
	for col in width:
		if _index_at(col, row) >= 0:
			continue
		_place_cell(_color_for(col, row, wave), col, row, Rules.MONSTER_HP)


func _color_for(col: int, row: int, wave: int) -> int:
	if row < 5 and col >= 5 and col <= 9:
		if (col + row) % 5 == 0:
			return 3
		return 0
	var palette: Array[int] = [1, 1, 2, 2, 3, 0, 4]
	return palette[(col + row * 2 + wave) % palette.size()]


func _place_cell(color_index: int, col: int, row: int, hp: float) -> void:
	var node := _make_bubble(color_index, R, true)
	node.z_index = 2
	add_child(node)
	var cell := {
		"id": _next_id,
		"color": color_index,
		"col": col,
		"row": row,
		"hp": hp,
		"node": node,
	}
	_next_id += 1
	_cells.append(cell)
	_refresh_bar(cell)
	node.position = _visual(cell)


func _make_bubble(color_index: int, radius: float, faced: bool) -> Node2D:
	var node := Node2D.new()
	var body := Polygon2D.new()
	body.polygon = _hex(radius)
	body.color = Rules.GEM_COLORS[color_index]
	body.name = "body"
	node.add_child(body)
	if faced:
		var eye_l := Polygon2D.new()
		eye_l.polygon = _hex(4.2)
		eye_l.color = Color("1a1d24")
		eye_l.position = Vector2(-8, -6)
		node.add_child(eye_l)
		var eye_r := Polygon2D.new()
		eye_r.polygon = _hex(4.2)
		eye_r.color = Color("1a1d24")
		eye_r.position = Vector2(8, -6)
		node.add_child(eye_r)
		var mouth := Polygon2D.new()
		mouth.polygon = PackedVector2Array([
			Vector2(-7, 6), Vector2(7, 6), Vector2(5, 10), Vector2(-5, 10),
		])
		mouth.color = Color("1a1d24")
		node.add_child(mouth)
		var bar := Polygon2D.new()
		bar.name = "hp"
		bar.color = Color("1b2420")
		bar.polygon = PackedVector2Array([
			Vector2(-16, 16), Vector2(16, 16), Vector2(16, 20), Vector2(-16, 20),
		])
		node.add_child(bar)
	return node


func _refresh_bar(cell: Dictionary) -> void:
	var node: Node2D = cell["node"]
	if not is_instance_valid(node):
		return
	var bar := node.get_node_or_null("hp") as Polygon2D
	if bar == null:
		return
	var ratio := clampf(float(cell["hp"]) / Rules.MONSTER_HP, 0.0, 1.0)
	var width := 32.0 * ratio
	bar.polygon = PackedVector2Array([
		Vector2(-16, 16), Vector2(-16 + width, 16), Vector2(-16 + width, 20), Vector2(-16, 20),
	])
	bar.color = Color("f0d7a2") if ratio > 0.35 else Color("e07a72")


func _nominal(col: int, row: int) -> Vector2:
	var x := 18.0 + R + float(col) * COL_STEP
	if row % 2 == 1:
		x += R
	var y := 24.0 + R + float(row) * ROW_STEP + _creep
	return Vector2(x, y)


func _visual(cell: Dictionary) -> Vector2:
	return _nominal(int(cell["col"]), int(cell["row"]))


func _sync_cells() -> void:
	for cell in _cells:
		var node: Node2D = cell["node"]
		if is_instance_valid(node):
			node.position = _visual(cell)


func _pop_node(cell: Dictionary) -> void:
	var node: Node2D = cell["node"]
	if not is_instance_valid(node):
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(node, "scale", Vector2(0.05, 0.05), 0.12)
	tween.tween_property(node, "modulate:a", 0.0, 0.12)
	tween.chain().tween_callback(node.queue_free)


func _fall_node(cell: Dictionary) -> void:
	var node: Node2D = cell["node"]
	if not is_instance_valid(node):
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(node, "position:y", node.position.y + 220.0, 0.35)
	tween.tween_property(node, "modulate:a", 0.0, 0.35)
	tween.chain().tween_callback(node.queue_free)


func _popup(at: Vector2, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = at + Vector2(-12, -28)
	label.z_index = 8
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 28.0, 0.4)
	tween.tween_property(label, "modulate:a", 0.0, 0.4)
	tween.chain().tween_callback(label.queue_free)


func _hex(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 6:
		var angle := TAU * float(i) / 6.0 - PI / 6.0
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


func _clear_board() -> void:
	for cell in _cells:
		var node: Node = cell["node"]
		if is_instance_valid(node):
			node.queue_free()
	for shot in _shots:
		var node: Node = shot["node"]
		if is_instance_valid(node):
			node.queue_free()
	_cells.clear()
	_shots.clear()


func freeze_for(seconds: float) -> void:
	_freeze = maxf(_freeze, seconds)
	_freeze_tint.visible = true
