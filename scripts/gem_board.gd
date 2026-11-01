extends Control

const COLS := 8
const ROWS := 8
const TILE := 34
const GAP := 3
const PAD := 4
const HEADER := 22
const STRIDE := TILE + GAP

const GEM_COLORS: Array[Color] = [
	Color("e85d4c"),
	Color("3d9ee0"),
	Color("5cbf6a"),
	Color("b07be0"),
	Color("f0d7a2"),
]

signal matched(color_index: int, length: int, kind: String, wave: int)

var accept_input := false
var colors: Array[int] = []
var pieces: Array[int] = []

var _rng := RandomNumberGenerator.new()
var _gems: Array[Polygon2D] = []
var _marks: Array[Label] = []
var _wells: Array[ColorRect] = []
var _selected := Vector2i(-1, -1)
var _press := Vector2i(-1, -1)
var _busy := false
var _held := false


func _ready() -> void:
	custom_minimum_size = _pixel_size()
	size = custom_minimum_size
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	var count := COLS * ROWS
	colors.resize(count)
	pieces.resize(count)
	colors.fill(0)
	pieces.fill(0)
	var background := ColorRect.new()
	background.color = Color("12161e")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var title := Label.new()
	title.text = "交换相邻。三连满蓄，四连连射，五连特殊。"
	title.position = Vector2(PAD, 2)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color("f0d7a2"))
	add_child(title)
	for y in ROWS:
		for x in COLS:
			var well := ColorRect.new()
			well.mouse_filter = Control.MOUSE_FILTER_IGNORE
			well.position = _origin(x, y)
			well.size = Vector2(TILE, TILE)
			well.color = Color("1a2030")
			add_child(well)
			_wells.append(well)
			var gem := Polygon2D.new()
			gem.position = _origin(x, y)
			gem.polygon = _gem_polygon()
			add_child(gem)
			_gems.append(gem)
			var mark := Label.new()
			mark.text = "特"
			mark.position = _origin(x, y) + Vector2(8, 6)
			mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
			mark.add_theme_font_size_override("font_size", 14)
			mark.add_theme_color_override("font_color", Color("1a1d24"))
			mark.visible = false
			add_child(mark)
			_marks.append(mark)


func open(seed_value: int) -> void:
	_rng.seed = seed_value
	_held = false
	_busy = false
	_selected = Vector2i(-1, -1)
	_press = Vector2i(-1, -1)
	_fill_playable()
	_snap()
	accept_input = true


func pause() -> void:
	_held = true
	accept_input = false
	_selected = Vector2i(-1, -1)
	_press = Vector2i(-1, -1)
	_paint()


func resume() -> void:
	_held = false
	if not _busy:
		accept_input = true


static func find_matches(grid: Array, cols: int) -> Array:
	var runs: Array = []
	var rows := int(grid.size() / cols)
	for y in rows:
		var x := 0
		while x < cols:
			var color := int(grid[y * cols + x])
			if color < 0:
				x += 1
				continue
			var end := x + 1
			while end < cols and int(grid[y * cols + end]) == color:
				end += 1
			if end - x >= 3:
				var cells: Array = []
				for i in range(x, end):
					cells.append(Vector2i(i, y))
				runs.append({"color": color, "cells": cells, "length": end - x})
			x = end
	for x in cols:
		var y := 0
		while y < rows:
			var color := int(grid[y * cols + x])
			if color < 0:
				y += 1
				continue
			var end := y + 1
			while end < rows and int(grid[end * cols + x]) == color:
				end += 1
			if end - y >= 3:
				var cells: Array = []
				for i in range(y, end):
					cells.append(Vector2i(x, i))
				runs.append({"color": color, "cells": cells, "length": end - y})
			y = end
	return _merge_runs(runs)


static func kind_for_length(length: int) -> String:
	if length >= 5:
		return "special"
	if length >= 4:
		return "burst"
	return "shot"


static func clear_cells(grid: Array, cols: int, cells: Array) -> Array:
	var next: Array = grid.duplicate()
	for cell in cells:
		var spot: Vector2i = cell
		next[spot.y * cols + spot.x] = -1
	return next


static func collapse(grid: Array, cols: int, rows: int, fill: int) -> Array:
	var next: Array = []
	next.resize(grid.size())
	for x in cols:
		var survivors: Array[int] = []
		for y in range(rows - 1, -1, -1):
			var color := int(grid[y * cols + x])
			if color >= 0:
				survivors.append(color)
		var write := rows - 1
		for color in survivors:
			next[write * cols + x] = color
			write -= 1
		while write >= 0:
			next[write * cols + x] = fill
			write -= 1
	return next


static func bomb_cells(cells: Array, cols: int, rows: int) -> Array:
	var spot: Vector2i = cells[int(cells.size() / 2)]
	var extra: Array = []
	for cell in cells:
		extra.append(cell)
	for y in range(spot.y - 1, spot.y + 2):
		for x in range(spot.x - 1, spot.x + 2):
			if x < 0 or y < 0 or x >= cols or y >= rows:
				continue
			var around := Vector2i(x, y)
			if not extra.has(around):
				extra.append(around)
	return extra


func _input(event: InputEvent) -> void:
	if not accept_input or _busy or _held or not visible:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
			return
		if not get_global_rect().has_point(button.position):
			return
		var cell := _cell_at(button.position - get_global_rect().position)
		get_viewport().set_input_as_handled()
		if cell.x < 0:
			return
		_press = cell
		if _selected.x < 0:
			_selected = cell
			_paint()
			return
		if _selected == cell:
			_selected = Vector2i(-1, -1)
			_paint()
			return
		if _adjacent(_selected, cell):
			var origin := _selected
			_selected = Vector2i(-1, -1)
			_try_swap(origin, cell)
			return
		_selected = cell
		_paint()
	elif event is InputEventMouseMotion and _press.x >= 0:
		var motion := event as InputEventMouseMotion
		if not get_global_rect().has_point(motion.position):
			return
		var cell := _cell_at(motion.position - get_global_rect().position)
		if cell.x < 0 or cell == _press or not _adjacent(_press, cell):
			return
		var origin := _press
		_press = Vector2i(-1, -1)
		_selected = Vector2i(-1, -1)
		_try_swap(origin, cell)
		get_viewport().set_input_as_handled()


func _try_swap(a: Vector2i, b: Vector2i) -> void:
	_exchange(a, b)
	if find_matches(colors, COLS).is_empty():
		_exchange(a, b)
		_paint()
		return
	_resolve()


func _resolve() -> void:
	_busy = true
	accept_input = false
	var wave := 0
	while wave < 6:
		var groups := find_matches(colors, COLS)
		if groups.is_empty():
			break
		for group in groups:
			var length := int(group["length"])
			var kind := kind_for_length(length)
			var cells: Array = group["cells"]
			matched.emit(int(group["color"]), length, kind, wave)
			_apply_group(cells)
		_gravity()
		wave += 1
	if find_matches(colors, COLS).is_empty() and not _has_move():
		_fill_playable()
	_snap()
	_busy = false
	if not _held:
		accept_input = true


func _apply_group(cells: Array) -> void:
	for cell in cells:
		var spot: Vector2i = cell
		var index := _index(spot.x, spot.y)
		colors[index] = -1
		pieces[index] = 0


func _gravity() -> void:
	for x in COLS:
		var survivors: Array[Dictionary] = []
		for y in range(ROWS - 1, -1, -1):
			var index := _index(x, y)
			if colors[index] < 0:
				continue
			survivors.append({"color": colors[index], "piece": pieces[index]})
		var write := ROWS - 1
		for item in survivors:
			var index := _index(x, write)
			colors[index] = int(item["color"])
			pieces[index] = int(item["piece"])
			write -= 1
		while write >= 0:
			var index := _index(x, write)
			colors[index] = _rng.randi_range(0, GEM_COLORS.size() - 1)
			pieces[index] = 0
			write -= 1


func _fill_playable() -> void:
	for _attempt in 40:
		for i in colors.size():
			colors[i] = _rng.randi_range(0, GEM_COLORS.size() - 1)
			pieces[i] = 0
		if find_matches(colors, COLS).is_empty() and _has_move():
			return


func _has_move() -> bool:
	for y in ROWS:
		for x in COLS:
			if x + 1 < COLS and _swap_would_match(Vector2i(x, y), Vector2i(x + 1, y)):
				return true
			if y + 1 < ROWS and _swap_would_match(Vector2i(x, y), Vector2i(x, y + 1)):
				return true
	return false


func _swap_would_match(a: Vector2i, b: Vector2i) -> bool:
	_exchange(a, b)
	var matched_now := not find_matches(colors, COLS).is_empty()
	_exchange(a, b)
	return matched_now


func _touches_special(cells: Array) -> bool:
	for cell in cells:
		var spot: Vector2i = cell
		if pieces[_index(spot.x, spot.y)] > 0:
			return true
	return false


func _exchange(a: Vector2i, b: Vector2i) -> void:
	var ia := _index(a.x, a.y)
	var ib := _index(b.x, b.y)
	var color := colors[ia]
	colors[ia] = colors[ib]
	colors[ib] = color
	var piece := pieces[ia]
	pieces[ia] = pieces[ib]
	pieces[ib] = piece


func _snap() -> void:
	for y in ROWS:
		for x in COLS:
			var index := _index(x, y)
			_gems[index].position = _origin(x, y)
			_marks[index].position = _origin(x, y) + Vector2(8, 6)
	_paint()


func _paint() -> void:
	for i in colors.size():
		var color_id := int(colors[i])
		var shown := color_id >= 0
		_gems[i].visible = shown
		_marks[i].visible = shown and int(pieces[i]) > 0
		if shown:
			var tint := GEM_COLORS[clampi(color_id, 0, GEM_COLORS.size() - 1)]
			if int(pieces[i]) > 0:
				tint = tint.lightened(0.35)
			_gems[i].color = tint
		var x := i % COLS
		var y := int(i / COLS)
		if _selected == Vector2i(x, y):
			_wells[i].color = Color("f4e7c3")
		elif shown:
			_wells[i].color = Color("1a2030")
		else:
			_wells[i].color = Color("121722")


func _cell_at(local: Vector2) -> Vector2i:
	if local.x < PAD or local.y < PAD + HEADER:
		return Vector2i(-1, -1)
	var x := int((local.x - PAD) / float(STRIDE))
	var y := int((local.y - PAD - HEADER) / float(STRIDE))
	if x < 0 or y < 0 or x >= COLS or y >= ROWS:
		return Vector2i(-1, -1)
	var origin := _origin(x, y)
	if local.x < origin.x or local.y < origin.y:
		return Vector2i(-1, -1)
	if local.x >= origin.x + TILE or local.y >= origin.y + TILE:
		return Vector2i(-1, -1)
	return Vector2i(x, y)


func _origin(x: int, y: float) -> Vector2:
	return Vector2(PAD + float(x) * STRIDE, PAD + HEADER + y * STRIDE)


func _index(x: int, y: int) -> int:
	return y * COLS + x


func _pixel_size() -> Vector2:
	return Vector2(
		PAD * 2 + COLS * TILE + (COLS - 1) * GAP,
		PAD * 2 + HEADER + ROWS * TILE + (ROWS - 1) * GAP
	)


func _gem_polygon() -> PackedVector2Array:
	var t := float(TILE)
	return PackedVector2Array([
		Vector2(t * 0.50, t * 0.10),
		Vector2(t * 0.88, t * 0.50),
		Vector2(t * 0.50, t * 0.90),
		Vector2(t * 0.12, t * 0.50),
	])


static func _adjacent(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) == 1


static func _merge_runs(runs: Array) -> Array:
	var groups: Array = []
	for run in runs:
		var copy: Array = []
		for cell in run["cells"]:
			copy.append(cell)
		groups.append({
			"color": int(run["color"]),
			"cells": copy,
			"length": int(run["length"]),
		})
	var changed := true
	while changed:
		changed = false
		var i := 0
		while i < groups.size():
			var j := i + 1
			while j < groups.size():
				var left: Dictionary = groups[i]
				var right: Dictionary = groups[j]
				var share := int(left["color"]) == int(right["color"]) and _shares(left["cells"], right["cells"])
				if share:
					left["length"] = maxi(int(left["length"]), int(right["length"]))
					for cell in right["cells"]:
						if not left["cells"].has(cell):
							left["cells"].append(cell)
					groups.remove_at(j)
					changed = true
				else:
					j += 1
			i += 1
	return groups


static func _shares(left: Array, right: Array) -> bool:
	for cell in left:
		if right.has(cell):
			return true
	return false
