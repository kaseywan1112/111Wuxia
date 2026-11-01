extends Control

const COLS := 6
const ROWS := 5
const TILE := 46
const GAP := 4
const PAD := 8
const HEADER := 36
const STRIDE := TILE + GAP
const MIN_CHAIN := 3

const NAMES: PackedStringArray = ["", "逆", "分", "凝"]
const EFFECT_IDS: PackedStringArray = ["", "reverse", "split", "freeze"]

signal chain_cast(length: int, effects: PackedStringArray)

var accept_input := false
var colors: Array[int] = []
var kinds: Array[int] = []
var path: Array = []
var drawing := false

var _rng := RandomNumberGenerator.new()
var _gems: Array[Polygon2D] = []
var _facets: Array[Polygon2D] = []
var _marks: Array[Label] = []
var _wells: Array[ColorRect] = []
var _line: Line2D
var _falling := false
var _held := false


func _ready() -> void:
	var pixel := _pixel_size()
	custom_minimum_size = pixel
	size = pixel
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	var count := COLS * ROWS
	colors.resize(count)
	kinds.resize(count)
	colors.fill(0)
	kinds.fill(0)
	var background := ColorRect.new()
	background.color = Color("12161e")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var title := Label.new()
	title.text = "划同色，可转弯"
	title.position = Vector2(PAD, 4)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("f0d7a2"))
	add_child(title)
	var hint := Label.new()
	hint.text = "至少三颗。逆反球，分多球，凝停怪。"
	hint.position = Vector2(PAD, 22)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("c9c3b4"))
	add_child(hint)
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
			gem.visible = false
			add_child(gem)
			_gems.append(gem)
			var facet := Polygon2D.new()
			facet.position = _origin(x, y)
			facet.polygon = _facet_polygon()
			facet.color = Color(1, 1, 1, 0.4)
			facet.visible = false
			add_child(facet)
			_facets.append(facet)
			var mark := Label.new()
			mark.position = _origin(x, y) + Vector2(14, 10)
			mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
			mark.add_theme_font_size_override("font_size", 18)
			mark.add_theme_color_override("font_color", Color("1a1d24"))
			mark.visible = false
			add_child(mark)
			_marks.append(mark)
	_line = Line2D.new()
	_line.width = 7.0
	_line.default_color = Color(1, 1, 1, 0.9)
	_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_line.z_index = 4
	add_child(_line)


func open(seed_value: int) -> void:
	_rng.seed = seed_value
	_held = false
	_falling = false
	drawing = false
	path = []
	_line.clear_points()
	_fill_playable()
	_snap_visuals()
	accept_input = true


func pause() -> void:
	_held = true
	accept_input = false
	drawing = false
	path = []
	if _line != null:
		_line.clear_points()
	_paint()


func resume() -> void:
	_held = false
	if not _falling:
		accept_input = true


static func try_extend(path: Array, next: Vector2i, colors: Array, kinds: Array, cols: int) -> Dictionary:
	if next.x < 0 or next.y < 0:
		return {"path": path, "action": "ignore"}
	var index := next.y * cols + next.x
	if index < 0 or index >= colors.size() or int(colors[index]) < 0:
		return {"path": path, "action": "ignore"}
	if path.is_empty():
		return {"path": [next], "action": "start"}
	if path.size() >= 2 and next == path[path.size() - 2]:
		var trimmed: Array = path.duplicate()
		trimmed.pop_back()
		return {"path": trimmed, "action": "undo"}
	if path.has(next):
		return {"path": path, "action": "ignore"}
	var last: Vector2i = path[path.size() - 1]
	if absi(last.x - next.x) + absi(last.y - next.y) != 1:
		return {"path": path, "action": "ignore"}
	if int(kinds[index]) == 0 and not _matches_anchor(path, colors, kinds, cols, int(colors[index])):
		return {"path": path, "action": "ignore"}
	var grown: Array = path.duplicate()
	grown.append(next)
	return {"path": grown, "action": "add"}


static func effects_of(path: Array, kinds: Array, cols: int) -> PackedStringArray:
	var found := PackedStringArray()
	for cell in path:
		var spot: Vector2i = cell
		var index := spot.y * cols + spot.x
		if index < 0 or index >= kinds.size():
			continue
		var kind := int(kinds[index])
		if kind <= 0 or kind >= EFFECT_IDS.size():
			continue
		var effect := EFFECT_IDS[kind]
		if not found.has(effect):
			found.append(effect)
	return found


func _input(event: InputEvent) -> void:
	if not accept_input or _falling or not visible:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			if not get_global_rect().has_point(button.position):
				return
			var cell := _cell_at(button.position - get_global_rect().position)
			if cell.x < 0:
				get_viewport().set_input_as_handled()
				return
			var result: Dictionary = try_extend([], cell, colors, kinds, COLS)
			if str(result["action"]) != "start":
				return
			path = result["path"]
			drawing = true
			_sync_path_visual()
			get_viewport().set_input_as_handled()
		elif drawing:
			_release_path()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and drawing:
		var motion := event as InputEventMouseMotion
		var local := motion.position - get_global_rect().position
		var cell := _cell_at(local)
		if cell.x < 0:
			return
		var result: Dictionary = try_extend(path, cell, colors, kinds, COLS)
		if str(result["action"]) == "ignore":
			return
		path = result["path"]
		_sync_path_visual()
		get_viewport().set_input_as_handled()


func _release_path() -> void:
	drawing = false
	var length := path.size()
	var committed: Array = path.duplicate()
	var effects := effects_of(committed, kinds, COLS)
	path = []
	_line.clear_points()
	_paint()
	if length >= MIN_CHAIN:
		chain_cast.emit(length, effects)
		_collapse(committed)
	else:
		accept_input = true


func _collapse(removed_cells: Array) -> void:
	_falling = true
	accept_input = false
	var removed := {}
	for cell in removed_cells:
		removed[_index(cell.x, cell.y)] = true
	var next_colors: Array[int] = []
	var next_kinds: Array[int] = []
	var from_y: Array[float] = []
	var count := COLS * ROWS
	next_colors.resize(count)
	next_kinds.resize(count)
	from_y.resize(count)
	for x in COLS:
		var survivors: Array[Dictionary] = []
		for y in range(ROWS - 1, -1, -1):
			var index := _index(x, y)
			if removed.has(index) or colors[index] < 0:
				continue
			survivors.append({
				"color": colors[index],
				"kind": kinds[index],
				"from": float(y),
			})
		var write := ROWS - 1
		for item in survivors:
			var index := _index(x, write)
			next_colors[index] = int(item["color"])
			next_kinds[index] = int(item["kind"])
			from_y[index] = float(item["from"])
			write -= 1
		var above := 1
		while write >= 0:
			var index := _index(x, write)
			var rolled := _roll_into(next_kinds)
			next_colors[index] = rolled.x
			next_kinds[index] = rolled.y
			from_y[index] = float(-above)
			above += 1
			write -= 1
	var seen_kind := {}
	for i in next_kinds.size():
		var kind := int(next_kinds[i])
		if kind == 0:
			continue
		if seen_kind.has(kind):
			next_kinds[i] = 0
		else:
			seen_kind[kind] = true
	colors = next_colors
	kinds = next_kinds
	_paint()
	var tween := create_tween()
	tween.set_parallel(true)
	for y in ROWS:
		for x in COLS:
			var index := _index(x, y)
			var start := _origin(x, from_y[index])
			var dest := _origin(x, y)
			_gems[index].position = start
			_facets[index].position = start
			_marks[index].position = start + Vector2(14, 10)
			tween.tween_property(_gems[index], "position", dest, 0.16)
			tween.tween_property(_facets[index], "position", dest, 0.16)
			tween.tween_property(_marks[index], "position", dest + Vector2(14, 10), 0.16)
	tween.chain().tween_callback(_finish_fall)


func _finish_fall() -> void:
	if not _has_chain():
		_fill_playable()
	_snap_visuals()
	_falling = false
	if not _held:
		accept_input = true


func _fill_playable() -> void:
	for _attempt in 24:
		for i in colors.size():
			colors[i] = _rng.randi_range(0, 3)
			kinds[i] = 0
		if _has_chain():
			break
	_stamp_specials()


func _stamp_specials() -> void:
	for kind in [1, 2, 3]:
		for _try in 24:
			var index := _rng.randi() % colors.size()
			if kinds[index] != 0:
				continue
			kinds[index] = kind
			if _has_chain():
				break
			kinds[index] = 0


func _roll_into(next_kinds: Array) -> Vector2i:
	var kind := 0
	if _rng.randf() < 0.14:
		var options: Array[int] = []
		for candidate in [1, 2, 3]:
			if _count_in(next_kinds, candidate) == 0:
				options.append(candidate)
		if not options.is_empty():
			kind = options[_rng.randi() % options.size()]
	return Vector2i(_rng.randi_range(0, 3), kind)


func _sync_path_visual() -> void:
	_line.clear_points()
	var tint := Color("f4f1ea")
	for cell in path:
		_line.add_point(_center_local(cell))
		var index := _index(cell.x, cell.y)
		if int(kinds[index]) == 0:
			tint = _color_of(int(colors[index]), 0)
	tint.a = 0.9
	_line.default_color = tint
	_line.width = 6.0 + float(mini(path.size(), 8)) * 0.6
	_paint()


func _paint() -> void:
	var marked := {}
	for cell in path:
		marked[_index(cell.x, cell.y)] = true
	for i in colors.size():
		var shown := int(colors[i]) >= 0
		_gems[i].visible = shown
		_facets[i].visible = shown and int(kinds[i]) == 0
		var kind := int(kinds[i])
		_marks[i].visible = shown and kind > 0
		if kind > 0 and kind < NAMES.size():
			_marks[i].text = NAMES[kind]
		if shown:
			_gems[i].color = _color_of(int(colors[i]), kind)
		if marked.has(i):
			_wells[i].color = Color("f4e7c3")
		elif shown:
			_wells[i].color = Color("1a2030")
		else:
			_wells[i].color = Color("121722")


func _snap_visuals() -> void:
	for y in ROWS:
		for x in COLS:
			var index := _index(x, y)
			var home := _origin(x, y)
			_gems[index].position = home
			_facets[index].position = home
			_marks[index].position = home + Vector2(14, 10)
	_paint()


func _has_chain() -> bool:
	var seen := {}
	for y in ROWS:
		for x in COLS:
			var index := _index(x, y)
			if seen.has(index) or colors[index] < 0 or kinds[index] != 0:
				continue
			if _flood(x, y, colors[index], seen) >= MIN_CHAIN:
				return true
	return false


func _flood(x: int, y: int, color_id: int, seen: Dictionary) -> int:
	var stack: Array[Vector2i] = [Vector2i(x, y)]
	var count := 0
	while not stack.is_empty():
		var cell: Vector2i = stack.pop_back()
		if cell.x < 0 or cell.y < 0 or cell.x >= COLS or cell.y >= ROWS:
			continue
		var index := _index(cell.x, cell.y)
		if seen.has(index) or colors[index] != color_id or kinds[index] != 0:
			continue
		seen[index] = true
		count += 1
		stack.append(cell + Vector2i(1, 0))
		stack.append(cell + Vector2i(-1, 0))
		stack.append(cell + Vector2i(0, 1))
		stack.append(cell + Vector2i(0, -1))
	return count


func _cell_at(local: Vector2) -> Vector2i:
	if local.x < PAD or local.y < PAD:
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


func _center_local(cell: Vector2i) -> Vector2:
	return _origin(cell.x, cell.y) + Vector2(TILE * 0.5, TILE * 0.5)


func _origin(x: int, y: float) -> Vector2:
	return Vector2(PAD + float(x) * STRIDE, PAD + HEADER + y * STRIDE)


func _index(x: int, y: int) -> int:
	return y * COLS + x


func _pixel_size() -> Vector2:
	var width := PAD * 2 + COLS * TILE + (COLS - 1) * GAP
	var height := PAD * 2 + HEADER + ROWS * TILE + (ROWS - 1) * GAP
	return Vector2(width, height)


func _color_of(color_id: int, kind: int) -> Color:
	if kind == 1:
		return Color("c9b6ff")
	if kind == 2:
		return Color("ffb15a")
	if kind == 3:
		return Color("b9fff1")
	var palette: Array[Color] = [
		Color("e85d4c"),
		Color("3d9ee0"),
		Color("5cbf6a"),
		Color("f0d7a2"),
	]
	return palette[clampi(color_id, 0, palette.size() - 1)]


func _gem_polygon() -> PackedVector2Array:
	var t := float(TILE)
	return PackedVector2Array([
		Vector2(t * 0.50, t * 0.12),
		Vector2(t * 0.86, t * 0.50),
		Vector2(t * 0.50, t * 0.88),
		Vector2(t * 0.14, t * 0.50),
	])


func _facet_polygon() -> PackedVector2Array:
	var t := float(TILE)
	return PackedVector2Array([
		Vector2(t * 0.50, t * 0.22),
		Vector2(t * 0.66, t * 0.42),
		Vector2(t * 0.50, t * 0.50),
		Vector2(t * 0.34, t * 0.40),
	])


static func _matches_anchor(path: Array, colors: Array, kinds: Array, cols: int, color_id: int) -> bool:
	for cell in path:
		var spot: Vector2i = cell
		var index := spot.y * cols + spot.x
		if int(kinds[index]) != 0:
			continue
		return int(colors[index]) == color_id
	return true


static func _count_in(values: Array, kind: int) -> int:
	var count := 0
	for value in values:
		if int(value) == kind:
			count += 1
	return count
