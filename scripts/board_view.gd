extends Control

const Rules = preload("res://scripts/run_state.gd")

const FIELD_W := 600.0
const FIELD_H := 500.0
const START_GEMS := 8
const SPAWN_INTERVAL := 0.7
const GEM_CAP := 16
const GEM_RADIUS := 30.0
const HIT_RADIUS := 42.0
const DRIFT_MIN := 26.0
const DRIFT_MAX := 48.0
const SWIPE_MIN := 18.0

signal chain_resolved(color_index: int, length: int, origin: Vector2)
signal chain_broken
signal path_changed(color_index: int, length: int)
signal board_note(text: String)

var accept_input := false
var roll_color: Callable = Callable()

var _gems: Array = []
var _next_id := 1
var _spawn_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _drawing := false
var _stroke: PackedVector2Array = PackedVector2Array()
var _hit_ids: Array[int] = []
var _hit_colors: Array[int] = []
var _hit_points: Array[Vector2] = []
var _travel := 0.0
var _line: Line2D


func _ready() -> void:
	custom_minimum_size = Vector2(FIELD_W, FIELD_H)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_rng.randomize()

	var background := ColorRect.new()
	background.color = Color("12161e")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.offset_left = 0
	background.offset_top = 0
	background.offset_right = 0
	background.offset_bottom = 0
	add_child(background)

	_line = Line2D.new()
	_line.width = 14.0
	_line.default_color = Color(1, 1, 1, 0.9)
	_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_line.z_index = 6
	add_child(_line)


func setup(roller: Callable) -> void:
	roll_color = roller


func refill() -> void:
	_drawing = false
	_clear_stroke()
	for gem in _gems:
		var node: Node = gem["node"]
		if is_instance_valid(node):
			node.queue_free()
	_gems.clear()
	_spawn_timer = SPAWN_INTERVAL
	for _i in START_GEMS:
		_spawn_gem()


func _process(delta: float) -> void:
	if not accept_input and not _drawing:
		return
	if accept_input:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_timer = SPAWN_INTERVAL
			if _gems.size() < GEM_CAP:
				_spawn_gem()
			# A full field skips this spawn and waits for the next interval.
	var margin := GEM_RADIUS + 8.0
	for gem in _gems:
		var pos: Vector2 = gem["pos"]
		var vel: Vector2 = gem["vel"]
		pos += vel * delta
		if pos.x < margin:
			pos.x = margin
			vel.x = absf(vel.x)
		elif pos.x > FIELD_W - margin:
			pos.x = FIELD_W - margin
			vel.x = -absf(vel.x)
		if pos.y < margin:
			pos.y = margin
			vel.y = absf(vel.y)
		elif pos.y > FIELD_H - margin:
			pos.y = FIELD_H - margin
			vel.y = -absf(vel.y)
		gem["pos"] = pos
		gem["vel"] = vel
		var node: Node2D = gem["node"]
		if is_instance_valid(node):
			node.position = pos


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			if not accept_input or _drawing:
				return
			if not get_global_rect().has_point(button.position):
				return
			_begin_stroke(button.position - get_global_rect().position)
			get_viewport().set_input_as_handled()
		elif _drawing:
			_end_stroke()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _drawing:
		var motion := event as InputEventMouseMotion
		var local := motion.position - get_global_rect().position
		_extend_stroke(local)
		get_viewport().set_input_as_handled()


func _begin_stroke(local: Vector2) -> void:
	_drawing = true
	_stroke = PackedVector2Array()
	_hit_ids.clear()
	_hit_colors.clear()
	_hit_points.clear()
	_travel = 0.0
	_line.clear_points()
	_line.default_color = Color(1, 1, 1, 0.92)
	_extend_stroke(local)


func _extend_stroke(local: Vector2) -> void:
	var clamped := Vector2(clampf(local.x, 0.0, FIELD_W), clampf(local.y, 0.0, FIELD_H))
	if _stroke.is_empty():
		_stroke.append(clamped)
		_line.add_point(clamped)
		_collect_along(clamped, clamped)
		_emit_preview()
		return
	var previous: Vector2 = _stroke[_stroke.size() - 1]
	var step := clamped - previous
	if step.length() < 2.0:
		return
	_travel += step.length()
	_stroke.append(clamped)
	_line.add_point(clamped)
	_collect_along(previous, clamped)
	_emit_preview()


func _collect_along(a: Vector2, b: Vector2) -> void:
	for gem in _gems:
		var id := int(gem["id"])
		if _hit_ids.has(id):
			continue
		var pos: Vector2 = gem["pos"]
		if _distance_to_segment(pos, a, b) > HIT_RADIUS:
			continue
		_hit_ids.append(id)
		_hit_colors.append(int(gem["color"]))
		_hit_points.append(pos)
		_mark_sliced(gem)


func _end_stroke() -> void:
	_drawing = false
	var moved := _travel >= SWIPE_MIN or _hit_colors.size() >= 2
	var resolved: Dictionary = Rules.resolve_swipe(_hit_colors)
	var color_index := int(resolved["color"])
	var length := int(resolved["length"])
	var origin := _origin_for(color_index)
	_fade_stroke()
	_restore_gems()
	if not moved:
		path_changed.emit(-1, 0)
		return
	if length >= Rules.MIN_CHAIN and color_index >= 0:
		chain_resolved.emit(color_index, length, origin)
	else:
		chain_broken.emit()


func _origin_for(color_index: int) -> Vector2:
	if color_index < 0:
		if _stroke.is_empty():
			return global_position + size * 0.5
		var last: Vector2 = _stroke[_stroke.size() - 1]
		return get_global_rect().position + last
	for i in range(_hit_colors.size() - 1, -1, -1):
		if _hit_colors[i] == color_index:
			return get_global_rect().position + _hit_points[i]
	return get_global_rect().position + size * 0.5


func _emit_preview() -> void:
	var resolved: Dictionary = Rules.resolve_swipe(_hit_colors)
	path_changed.emit(int(resolved["color"]), int(resolved["length"]))


func _spawn_gem() -> void:
	if _gems.size() >= GEM_CAP or not roll_color.is_valid():
		return
	var margin := GEM_RADIUS + 16.0
	var pos := Vector2(
		_rng.randf_range(margin, FIELD_W - margin),
		_rng.randf_range(margin, FIELD_H - margin)
	)
	for _try in 6:
		var crowded := false
		for other in _gems:
			var other_pos: Vector2 = other["pos"]
			if other_pos.distance_to(pos) < HIT_RADIUS * 1.35:
				crowded = true
				break
		if not crowded:
			break
		pos = Vector2(
			_rng.randf_range(margin, FIELD_W - margin),
			_rng.randf_range(margin, FIELD_H - margin)
		)
	var angle := _rng.randf() * TAU
	var speed := _rng.randf_range(DRIFT_MIN, DRIFT_MAX)
	var color_index := int(roll_color.call())
	var node := Node2D.new()
	node.position = pos
	add_child(node)
	move_child(node, _line.get_index())
	var gem := Polygon2D.new()
	gem.polygon = _gem_polygon()
	gem.color = Rules.GEM_COLORS[clampi(color_index, 0, Rules.GEM_COLORS.size() - 1)]
	node.add_child(gem)
	var facet := Polygon2D.new()
	facet.polygon = _facet_polygon()
	facet.color = Color(1, 1, 1, 0.45)
	node.add_child(facet)
	_gems.append({
		"id": _next_id,
		"color": color_index,
		"pos": pos,
		"vel": Vector2(cos(angle), sin(angle)) * speed,
		"node": node,
		"gem": gem,
		"base": gem.color,
	})
	_next_id += 1


func _mark_sliced(gem: Dictionary) -> void:
	var poly: Polygon2D = gem["gem"]
	if is_instance_valid(poly):
		poly.color = Color(gem["base"]).lightened(0.42)
	var node: Node2D = gem["node"]
	if not is_instance_valid(node):
		return
	var slash := Line2D.new()
	slash.width = 4.0
	slash.default_color = Color(1, 1, 1, 0.95)
	slash.add_point(Vector2(-18, -14))
	slash.add_point(Vector2(18, 14))
	slash.z_index = 2
	node.add_child(slash)
	var tween := create_tween()
	tween.tween_property(slash, "modulate:a", 0.0, 0.45)
	tween.tween_callback(slash.queue_free)


func _restore_gems() -> void:
	for gem in _gems:
		var poly: Polygon2D = gem["gem"]
		if is_instance_valid(poly):
			poly.color = gem["base"]


func _fade_stroke() -> void:
	var fading := _line
	_line = Line2D.new()
	_line.width = 14.0
	_line.default_color = Color(1, 1, 1, 0.9)
	_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_line.z_index = 6
	add_child(_line)
	var tween := create_tween()
	tween.tween_property(fading, "modulate:a", 0.0, 0.28)
	tween.tween_callback(fading.queue_free)


func _clear_stroke() -> void:
	_stroke = PackedVector2Array()
	_hit_ids.clear()
	_hit_colors.clear()
	_hit_points.clear()
	_travel = 0.0
	if _line != null:
		_line.clear_points()


func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_sq := ab.length_squared()
	if length_sq < 0.001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)


func _gem_polygon() -> PackedVector2Array:
	var r := GEM_RADIUS
	return PackedVector2Array([
		Vector2(0, -r),
		Vector2(r * 0.86, 0),
		Vector2(0, r),
		Vector2(-r * 0.86, 0),
	])


func _facet_polygon() -> PackedVector2Array:
	var r := GEM_RADIUS
	return PackedVector2Array([
		Vector2(0, -r * 0.55),
		Vector2(r * 0.28, -r * 0.12),
		Vector2(0, r * 0.05),
		Vector2(-r * 0.22, -r * 0.16),
	])
