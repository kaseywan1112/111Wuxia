extends Control

const Rules = preload("res://scripts/run_state.gd")

const COLS := 8
const ROWS := 8
const TILE := 56
const GAP := 5
const PAD := 12
const STRIDE := TILE + GAP

signal chain_resolved(color_index: int, length: int, origin: Vector2)
signal chain_broken
signal path_changed(color_index: int, length: int)
signal board_note(text: String)

var accept_input := false
var colors: Array[int] = []
var path: Array = []
var drawing := false
var roll_color: Callable = Callable()

var _wells: Array[ColorRect] = []
var _gems: Array[Polygon2D] = []
var _facets: Array[Polygon2D] = []
var _line: Line2D
var _falling := false


func _ready() -> void:
	var pixel := _pixel_size()
	custom_minimum_size = Vector2(pixel, pixel)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	colors.resize(COLS * ROWS)
	colors.fill(-1)

	var background := ColorRect.new()
	background.color = Color("12161e")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.offset_left = 0
	background.offset_top = 0
	background.offset_right = 0
	background.offset_bottom = 0
	add_child(background)

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
			gem.color = Rules.GEM_COLORS[0]
			gem.visible = false
			add_child(gem)
			_gems.append(gem)

			var facet := Polygon2D.new()
			facet.position = _origin(x, y)
			facet.polygon = _facet_polygon()
			facet.color = Color(1, 1, 1, 0.42)
			facet.visible = false
			add_child(facet)
			_facets.append(facet)

	_line = Line2D.new()
	_line.width = 8.0
	_line.default_color = Color(1, 1, 1, 0.85)
	_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_line.z_index = 4
	add_child(_line)


func setup(roller: Callable) -> void:
	roll_color = roller


func refill() -> void:
	_falling = false
	drawing = false
	path = []
	_line.clear_points()
	for _attempt in 24:
		for i in colors.size():
			colors[i] = int(roll_color.call())
		if _has_chain():
			break
	_snap_visuals()
	path_changed.emit(-1, 0)


func _input(event: InputEvent) -> void:
	if not accept_input or _falling:
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
				return
			var result: Dictionary = Rules.try_extend([], cell, colors, COLS)
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
		var result: Dictionary = Rules.try_extend(path, cell, colors, COLS)
		if str(result["action"]) == "ignore":
			return
		path = result["path"]
		_sync_path_visual()
		get_viewport().set_input_as_handled()


func _release_path() -> void:
	drawing = false
	var length := path.size()
	var color_index := -1
	var origin := Vector2.ZERO
	if length > 0:
		var last: Vector2i = path[length - 1]
		color_index = int(colors[_index(last.x, last.y)])
		origin = _center_global(last)
	var committed: Array = path.duplicate()
	path = []
	_line.clear_points()
	_paint()
	path_changed.emit(-1, 0)
	if length >= Rules.MIN_CHAIN and color_index >= 0:
		chain_resolved.emit(color_index, length, origin)
		_collapse(committed)
	else:
		chain_broken.emit()


func _collapse(removed_cells: Array) -> void:
	_falling = true
	accept_input = false
	var removed := {}
	for cell in removed_cells:
		removed[_index(cell.x, cell.y)] = true
	var next_colors: Array[int] = []
	next_colors.resize(COLS * ROWS)
	var from_y: Array[float] = []
	from_y.resize(COLS * ROWS)
	for x in COLS:
		var survivors: Array[Dictionary] = []
		for y in range(ROWS - 1, -1, -1):
			var index := _index(x, y)
			if removed.has(index) or colors[index] < 0:
				continue
			survivors.append({"color": colors[index], "from": float(y)})
		var write := ROWS - 1
		for item in survivors:
			var index := _index(x, write)
			next_colors[index] = int(item["color"])
			from_y[index] = float(item["from"])
			write -= 1
		var above := 1
		while write >= 0:
			var index := _index(x, write)
			next_colors[index] = int(roll_color.call())
			from_y[index] = float(-above)
			above += 1
			write -= 1
	colors = next_colors
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
			tween.tween_property(_gems[index], "position", dest, 0.16)
			tween.tween_property(_facets[index], "position", dest, 0.16)
	tween.chain().tween_callback(_finish_fall)


func _finish_fall() -> void:
	_snap_visuals()
	if not _has_chain():
		for _attempt in 24:
			for i in colors.size():
				colors[i] = int(roll_color.call())
			if _has_chain():
				break
		_snap_visuals()
		board_note.emit("没有可连的三连，棋盘已重排")
	_falling = false
	accept_input = true


func _sync_path_visual() -> void:
	_line.clear_points()
	var color_index := -1
	for cell in path:
		_line.add_point(_center_local(cell))
		color_index = int(colors[_index(cell.x, cell.y)])
	if color_index >= 0:
		var tint: Color = Rules.GEM_COLORS[color_index]
		tint.a = 0.9
		_line.default_color = tint
		_line.width = 6.0 + float(mini(path.size(), 8)) * 0.7
	_paint()
	path_changed.emit(color_index, path.size())


func _paint() -> void:
	var heads := {}
	if not path.is_empty():
		var head: Vector2i = path[path.size() - 1]
		heads[_index(head.x, head.y)] = true
	var marked := {}
	for cell in path:
		marked[_index(cell.x, cell.y)] = true
	for i in colors.size():
		var color_id := int(colors[i])
		var shown := color_id >= 0
		_gems[i].visible = shown
		_facets[i].visible = shown
		if shown:
			var tint: Color = Rules.GEM_COLORS[color_id]
			if heads.has(i):
				tint = tint.lightened(0.35)
			_gems[i].color = tint
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
	_paint()


func _has_chain() -> bool:
	var seen := {}
	for y in ROWS:
		for x in COLS:
			var index := _index(x, y)
			if seen.has(index) or colors[index] < 0:
				continue
			if _flood(x, y, colors[index], seen) >= Rules.MIN_CHAIN:
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
		if seen.has(index) or colors[index] != color_id:
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
	var y := int((local.y - PAD) / float(STRIDE))
	if x < 0 or y < 0 or x >= COLS or y >= ROWS:
		return Vector2i(-1, -1)
	var origin := _origin(x, y)
	if local.x >= origin.x + TILE or local.y >= origin.y + TILE:
		return Vector2i(-1, -1)
	return Vector2i(x, y)


func _center_local(cell: Vector2i) -> Vector2:
	return _origin(cell.x, cell.y) + Vector2(TILE * 0.5, TILE * 0.5)


func _center_global(cell: Vector2i) -> Vector2:
	return _gems[_index(cell.x, cell.y)].global_position + Vector2(TILE * 0.5, TILE * 0.5)


func _origin(x: int, y: float) -> Vector2:
	return Vector2(PAD + float(x) * STRIDE, PAD + y * STRIDE)


func _index(x: int, y: int) -> int:
	return y * COLS + x


func _pixel_size() -> int:
	return PAD * 2 + COLS * TILE + (COLS - 1) * GAP


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
