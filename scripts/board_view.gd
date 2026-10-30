extends Control

const Rules = preload("res://scripts/run_state.gd")

const FIELD_W := 600.0
const FIELD_H := 500.0
const START_GEMS := 10
const SPAWN_INTERVAL := 0.16
const BURST_INTERVAL := 0.85
const GEM_CAP := 22
const GEM_RADIUS := 30.0
const HIT_RADIUS := 44.0
const FLY_MIN := 165.0
const FLY_MAX := 245.0
const SWIPE_MIN := 18.0
const SLASH_MAX_LENGTH := 220.0
const SLASH_MAX_TIME := 0.32

signal chain_resolved(color_index: int, length: int, origin: Vector2)
signal chain_broken
signal path_changed(color_index: int, length: int)
signal board_note(text: String)

var accept_input := false
var roll_color: Callable = Callable()

var _gems: Array = []
var _next_id := 1
var _spawn_timer := 0.0
var _burst_timer := 0.35
var _rng := RandomNumberGenerator.new()
var _drawing := false
var _pointer_down := false
var _stroke: PackedVector2Array = PackedVector2Array()
var _hit_ids: Array[int] = []
var _hit_colors: Array[int] = []
var _hit_points: Array[Vector2] = []
var _travel := 0.0
var _stroke_started_ms := 0
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
	_burst_timer = 0.45
	for _i in START_GEMS:
		_spawn_flyer(true)
	_spawn_burst()


func _process(delta: float) -> void:
	if not accept_input and not _drawing:
		return
	if accept_input:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_timer = SPAWN_INTERVAL
			if _gems.size() < GEM_CAP:
				_spawn_flyer(false)
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_burst_timer = BURST_INTERVAL
			if _gems.size() < GEM_CAP - 2:
				_spawn_burst()
	if _drawing:
		var elapsed := float(Time.get_ticks_msec() - _stroke_started_ms) / 1000.0
		if elapsed >= SLASH_MAX_TIME:
			var at := _stroke[_stroke.size() - 1] if not _stroke.is_empty() else Vector2(FIELD_W * 0.5, FIELD_H * 0.5)
			var held := _pointer_down
			_end_stroke()
			if held and accept_input:
				_begin_stroke(at)
	var alive: Array = []
	for gem in _gems:
		var pos: Vector2 = gem["pos"]
		var vel: Vector2 = gem["vel"]
		pos += vel * delta
		gem["life"] = float(gem["life"]) + delta
		gem["pos"] = pos
		var node: Node2D = gem["node"]
		var outside := pos.x < -70.0 or pos.x > FIELD_W + 70.0 or pos.y < -70.0 or pos.y > FIELD_H + 70.0
		if float(gem["life"]) > 0.4 and outside:
			if is_instance_valid(node):
				node.queue_free()
			continue
		if is_instance_valid(node):
			node.position = pos
		alive.append(gem)
	_gems = alive


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
			_pointer_down = true
			_begin_stroke(button.position - get_global_rect().position)
			get_viewport().set_input_as_handled()
		elif _drawing or _pointer_down:
			_pointer_down = false
			if _drawing:
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
	_stroke_started_ms = Time.get_ticks_msec()
	_line.clear_points()
	_line.width = 18.0
	_line.default_color = Color(1, 1, 1, 0.95)
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
	if _travel >= SLASH_MAX_LENGTH:
		var held := _pointer_down
		_end_stroke()
		if held and accept_input:
			_begin_stroke(clamped)


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
	if not moved:
		_restore_gems()
		path_changed.emit(-1, 0)
		return
	_consume_hits()
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


func _spawn_flyer(already_inside: bool) -> void:
	if _gems.size() >= GEM_CAP or not roll_color.is_valid():
		return
	var edge := _rng.randi() % 4
	var lateral := _rng.randf_range(48.0, (FIELD_H if edge < 2 else FIELD_W) - 48.0)
	var jitter := _rng.randf_range(-180.0, 180.0)
	var speed := _rng.randf_range(FLY_MIN, FLY_MAX)
	var progress := _rng.randf_range(0.18, 0.72) if already_inside else 0.0
	_launch_gem(int(roll_color.call()), edge, lateral, jitter, speed, progress)


func _spawn_burst() -> void:
	if not roll_color.is_valid() or _gems.size() >= GEM_CAP - 2:
		return
	var color_index := int(roll_color.call())
	var edge := _rng.randi() % 4
	var span := FIELD_H if edge < 2 else FIELD_W
	var lateral := _rng.randf_range(90.0, span - 90.0)
	var jitter := _rng.randf_range(-90.0, 90.0)
	var speed := _rng.randf_range(FLY_MIN, FLY_MIN + 40.0)
	var count := 4 if _rng.randf() < 0.35 else 3
	for i in count:
		if _gems.size() >= GEM_CAP:
			return
		var offset := (float(i) - float(count - 1) * 0.5) * 36.0
		_launch_gem(color_index, edge, lateral + offset, jitter, speed, 0.0)


func _launch_gem(color_index: int, edge: int, lateral: float, jitter: float, speed: float, progress: float) -> void:
	var start := Vector2.ZERO
	var aim := Vector2.ZERO
	match edge:
		0:
			start = Vector2(-46.0, clampf(lateral, 20.0, FIELD_H - 20.0))
			aim = Vector2(FIELD_W + 46.0, clampf(start.y + jitter, 24.0, FIELD_H - 24.0))
		1:
			start = Vector2(FIELD_W + 46.0, clampf(lateral, 20.0, FIELD_H - 20.0))
			aim = Vector2(-46.0, clampf(start.y + jitter, 24.0, FIELD_H - 24.0))
		2:
			start = Vector2(clampf(lateral, 20.0, FIELD_W - 20.0), -46.0)
			aim = Vector2(clampf(start.x + jitter, 24.0, FIELD_W - 24.0), FIELD_H + 46.0)
		_:
			start = Vector2(clampf(lateral, 20.0, FIELD_W - 20.0), FIELD_H + 46.0)
			aim = Vector2(clampf(start.x + jitter, 24.0, FIELD_W - 24.0), -46.0)
	var direction := aim - start
	if direction.length_squared() < 1.0:
		direction = Vector2.RIGHT
	direction = direction.normalized()
	var pos := start.lerp(aim, clampf(progress, 0.0, 0.85))
	var node := Node2D.new()
	node.position = pos
	add_child(node)
	if _line != null:
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
		"vel": direction * speed,
		"life": progress * 1.2,
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


func _consume_hits() -> void:
	var doomed := {}
	for id in _hit_ids:
		doomed[id] = true
	var kept: Array = []
	for gem in _gems:
		if doomed.has(int(gem["id"])):
			_pop_gem(gem)
		else:
			kept.append(gem)
	_gems = kept


func _pop_gem(gem: Dictionary) -> void:
	var node: Node2D = gem["node"]
	if not is_instance_valid(node):
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(node, "scale", Vector2(0.05, 0.05), 0.12)
	tween.tween_property(node, "modulate:a", 0.0, 0.12)
	tween.chain().tween_callback(node.queue_free)


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
	tween.tween_property(fading, "modulate:a", 0.0, 0.14)
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
