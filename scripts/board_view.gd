extends Control

const SIZE := 8
const TILE := 62
const GAP := 6
const PAD := 12

const GEM_COLORS: Array[Color] = [
	Color("e85d4c"),
	Color("f0a202"),
	Color("7bc67e"),
	Color("3d9ee0"),
	Color("b07be0"),
]

signal swap_requested(a: Vector2i, b: Vector2i)

var accept_input := false
var colors: Array = []
var selected := Vector2i(-1, -1)
var cursor := Vector2i(0, 0)
var highlighted: Array[Vector2i] = []

var _wells: Array[ColorRect] = []
var _gems: Array[Polygon2D] = []
var _facets: Array[Polygon2D] = []
var _press_cell := Vector2i(-1, -1)
var _press_pos := Vector2.ZERO
var _drag_sent := false


func _ready() -> void:
	var pixel := _pixel_size()
	custom_minimum_size = Vector2(pixel, pixel)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true

	var background := ColorRect.new()
	background.color = Color("12161e")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.offset_left = 0
	background.offset_top = 0
	background.offset_right = 0
	background.offset_bottom = 0
	add_child(background)

	for y in SIZE:
		for x in SIZE:
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
			gem.color = GEM_COLORS[0]
			gem.visible = false
			add_child(gem)
			_gems.append(gem)

			var facet := Polygon2D.new()
			facet.position = _origin(x, y)
			facet.polygon = _facet_polygon()
			facet.color = Color(1, 1, 1, 0.38)
			facet.visible = false
			add_child(facet)
			_facets.append(facet)


func show_cells(data: Array) -> void:
	colors = data.duplicate()
	highlighted.clear()
	_redraw()


func highlight(list: Array) -> void:
	highlighted.clear()
	for item in list:
		if item is Vector2i:
			highlighted.append(item)
	_redraw()


func clear_highlight() -> void:
	highlighted.clear()
	_redraw()


func clear_selection() -> void:
	selected = Vector2i(-1, -1)
	_redraw()


func handle_key(keycode: Key) -> bool:
	if not accept_input:
		return false
	var direction := Vector2i.ZERO
	match keycode:
		KEY_LEFT, KEY_A:
			direction = Vector2i(-1, 0)
		KEY_RIGHT, KEY_D:
			direction = Vector2i(1, 0)
		KEY_UP, KEY_W:
			direction = Vector2i(0, -1)
		KEY_DOWN, KEY_S:
			direction = Vector2i(0, 1)
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			_activate(cursor)
			return true
		_:
			return false
	var next := cursor + direction
	if next.x < 0 or next.y < 0 or next.x >= SIZE or next.y >= SIZE:
		return true
	cursor = next
	_redraw()
	return true


func _input(event: InputEvent) -> void:
	if not accept_input:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			if not get_global_rect().has_point(button.position):
				_press_cell = Vector2i(-1, -1)
				return
			var local := button.position - get_global_rect().position
			var cell := _cell_at(local)
			if cell.x < 0:
				_press_cell = Vector2i(-1, -1)
				return
			_press_cell = cell
			_press_pos = local
			_drag_sent = false
			get_viewport().set_input_as_handled()
		else:
			if _press_cell.x < 0:
				return
			if not _drag_sent:
				_activate(_press_cell)
			_press_cell = Vector2i(-1, -1)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _press_cell.x >= 0 and not _drag_sent:
		var motion := event as InputEventMouseMotion
		var local := motion.position - get_global_rect().position
		var delta := local - _press_pos
		if delta.length() < 20.0:
			return
		var direction := Vector2i.ZERO
		if absf(delta.x) > absf(delta.y):
			direction = Vector2i(1 if delta.x > 0.0 else -1, 0)
		else:
			direction = Vector2i(0, 1 if delta.y > 0.0 else -1)
		var target := _press_cell + direction
		_drag_sent = true
		if target.x >= 0 and target.y >= 0 and target.x < SIZE and target.y < SIZE:
			_request_swap(_press_cell, target)
		get_viewport().set_input_as_handled()


func _activate(cell: Vector2i) -> void:
	if cell.x < 0:
		return
	cursor = cell
	if selected.x < 0:
		selected = cell
	elif selected == cell:
		selected = Vector2i(-1, -1)
	elif absi(selected.x - cell.x) + absi(selected.y - cell.y) == 1:
		var origin := selected
		selected = Vector2i(-1, -1)
		_redraw()
		_request_swap(origin, cell)
		return
	else:
		selected = cell
	_redraw()


func _request_swap(a: Vector2i, b: Vector2i) -> void:
	selected = Vector2i(-1, -1)
	cursor = b
	_redraw()
	swap_requested.emit(a, b)


func _redraw() -> void:
	if colors.size() != SIZE * SIZE or _wells.is_empty():
		return
	for y in SIZE:
		for x in SIZE:
			var i := y * SIZE + x
			var color_id := int(colors[i])
			var cell := Vector2i(x, y)
			var occupied := color_id >= 0
			_gems[i].visible = occupied
			_facets[i].visible = occupied
			if occupied:
				_gems[i].color = GEM_COLORS[color_id]
			var well := Color("1a2030")
			if not occupied:
				well = Color("121722")
			elif highlighted.has(cell):
				well = Color("f4e7c3")
				_gems[i].color = GEM_COLORS[color_id].lightened(0.42)
			elif selected == cell:
				well = Color("e2b340")
			elif cursor == cell:
				well = Color("31405c")
			_wells[i].color = well


func _cell_at(local: Vector2) -> Vector2i:
	if local.x < PAD or local.y < PAD:
		return Vector2i(-1, -1)
	var x := int((local.x - PAD) / float(TILE + GAP))
	var y := int((local.y - PAD) / float(TILE + GAP))
	if x < 0 or y < 0 or x >= SIZE or y >= SIZE:
		return Vector2i(-1, -1)
	var origin := _origin(x, y)
	if local.x >= origin.x + TILE or local.y >= origin.y + TILE:
		return Vector2i(-1, -1)
	return Vector2i(x, y)


func _origin(x: int, y: int) -> Vector2:
	return Vector2(PAD + x * (TILE + GAP), PAD + y * (TILE + GAP))


func _pixel_size() -> int:
	return PAD * 2 + SIZE * TILE + (SIZE - 1) * GAP


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
