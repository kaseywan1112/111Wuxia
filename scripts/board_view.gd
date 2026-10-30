extends Control

const Rules = preload("res://scripts/run_state.gd")

const FIELD_W := 600.0
const FIELD_H := 500.0
const GEM_RADIUS := 27.0
const COLLIDE_R := 24.8
const TOUCH_DIST := 62.0
const HIT_RADIUS := 42.0
const GRAVITY := 520.0
const TERMINAL := 128.0
const SPAWN_INTERVAL := 0.48
const CLUSTER_INTERVAL := 2.15

signal chain_resolved(color_index: int, length: int, origin: Vector2)
signal chain_broken
signal path_changed(color_index: int, length: int)
signal board_note(text: String)

var accept_input := false
var roll_color: Callable = Callable()

var _gems: Array = []
var _next_id := 1
var _spawn_timer := 0.4
var _cluster_timer := 1.2
var _rng := RandomNumberGenerator.new()
var _drawing := false
var _pointer_down := false
var _stroke: PackedVector2Array = PackedVector2Array()
var _chain_ids: Array[int] = []
var _chain_color := -1
var _ceiling_note := false
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
	queue_redraw()


func _draw() -> void:
	var wall := Color("6d788c")
	draw_line(Vector2(2, 0), Vector2(2, FIELD_H - 2), wall, 4.0)
	draw_line(Vector2(FIELD_W - 2, 0), Vector2(FIELD_W - 2, FIELD_H - 2), wall, 4.0)
	draw_line(Vector2(0, FIELD_H - 2), Vector2(FIELD_W, FIELD_H - 2), wall, 5.0)


func setup(roller: Callable) -> void:
	roll_color = roller


func refill() -> void:
	_drawing = false
	_pointer_down = false
	_clear_stroke()
	for gem in _gems:
		var node: Node = gem["node"]
		if is_instance_valid(node):
			node.queue_free()
	_gems.clear()
	_ceiling_note = false
	_spawn_timer = 0.35
	_cluster_timer = 1.15
	_seed_pile()


func cancel_stroke() -> void:
	_pointer_down = false
	if _drawing:
		_drawing = false
		_fade_stroke()
	_clear_chain()
	path_changed.emit(-1, 0)


func _process(delta: float) -> void:
	if not accept_input:
		return
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = SPAWN_INTERVAL
		_spawn_from_top()
	_cluster_timer -= delta
	if _cluster_timer <= 0.0:
		_cluster_timer = CLUSTER_INTERVAL
		_spawn_cluster()
	var blocked := _ceiling_blocked()
	if blocked and not _ceiling_note:
		board_note.emit("宝石堆到顶了，先消开一点")
	_ceiling_note = blocked
	_simulate(delta)


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
	_clear_chain()
	_line.clear_points()
	_line.width = 16.0
	_line.default_color = Color(1, 1, 1, 0.92)
	_extend_stroke(local)


func _extend_stroke(local: Vector2) -> void:
	var clamped := Vector2(clampf(local.x, 0.0, FIELD_W), clampf(local.y, 0.0, FIELD_H))
	if _stroke.is_empty():
		_stroke.append(clamped)
		_line.add_point(clamped)
		_collect_along(clamped, clamped)
		return
	var previous: Vector2 = _stroke[_stroke.size() - 1]
	if previous.distance_to(clamped) < 3.0:
		return
	_stroke.append(clamped)
	_line.add_point(clamped)
	_collect_along(previous, clamped)


func _collect_along(a: Vector2, b: Vector2) -> void:
	var span := a.distance_to(b)
	var steps := maxi(int(span / 8.0), 1)
	var found: Array = []
	for gem in _gems:
		var id := int(gem["id"])
		if _chain_ids.has(id):
			continue
		var pos: Vector2 = gem["pos"]
		var best := HIT_RADIUS + 1.0
		var along := 0.0
		for step in steps + 1:
			var point := a.lerp(b, float(step) / float(steps))
			var distance := pos.distance_to(point)
			if distance < best:
				best = distance
				along = float(step)
		if best <= HIT_RADIUS:
			found.append({"gem": gem, "along": along})
	found.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return float(left["along"]) < float(right["along"])
	)
	for item in found:
		_try_add(item["gem"])


func _try_add(gem: Dictionary) -> void:
	var id := int(gem["id"])
	if _chain_ids.has(id):
		return
	var color := int(gem["color"])
	var pos: Vector2 = gem["pos"]
	if _chain_ids.is_empty():
		_chain_ids.append(id)
		_chain_color = color
		_tint_stroke()
		_paint_chain()
		path_changed.emit(color, _chain_ids.size())
		return
	if color != _chain_color:
		return
	var previous := _gem_by_id(_chain_ids[_chain_ids.size() - 1])
	if previous.is_empty():
		return
	var previous_pos: Vector2 = previous["pos"]
	if previous_pos.distance_to(pos) > TOUCH_DIST:
		return
	_chain_ids.append(id)
	_paint_chain()
	path_changed.emit(_chain_color, _chain_ids.size())


func _end_stroke() -> void:
	_drawing = false
	var length := _chain_ids.size()
	var color_index := _chain_color
	var origin := _chain_origin()
	_fade_stroke()
	if length >= Rules.MIN_CHAIN and color_index >= 0:
		_consume_chain()
		chain_resolved.emit(color_index, length, origin)
		return
	_clear_chain()
	path_changed.emit(-1, 0)


func _chain_origin() -> Vector2:
	if _chain_ids.is_empty():
		return global_position + size * 0.5
	var gem := _gem_by_id(_chain_ids[_chain_ids.size() - 1])
	if gem.is_empty():
		return global_position + size * 0.5
	var pos: Vector2 = gem["pos"]
	return get_global_rect().position + pos


func _simulate(delta: float) -> void:
	for gem in _gems:
		var vel: Vector2 = gem["vel"]
		vel.y = minf(vel.y + GRAVITY * delta, TERMINAL)
		vel.x *= exp(-1.8 * delta)
		gem["vel"] = vel
		gem["pos"] = gem["pos"] + vel * delta
	for _i in 8:
		_separate()
		_constrain_walls()
	for gem in _gems:
		_try_sleep(gem)
		_constrain_one(gem)
		var node: Node2D = gem["node"]
		if is_instance_valid(node):
			node.position = gem["pos"]


func _separate() -> void:
	for i in _gems.size():
		for j in range(i + 1, _gems.size()):
			var a: Dictionary = _gems[i]
			var b: Dictionary = _gems[j]
			var pa: Vector2 = a["pos"]
			var pb: Vector2 = b["pos"]
			var delta := pb - pa
			var dist := delta.length()
			var min_dist := COLLIDE_R * 2.0
			if dist >= min_dist:
				continue
			var normal := Vector2.UP
			if dist > 0.001:
				normal = delta / dist
			var push := (min_dist - dist) * 0.5
			pa -= normal * push
			pb += normal * push
			a["pos"] = pa
			b["pos"] = pb
			var va: Vector2 = a["vel"]
			var vb: Vector2 = b["vel"]
			var closing := (vb - va).dot(normal)
			if closing < 0.0:
				var correction := normal * closing * 0.55
				a["vel"] = va + correction
				b["vel"] = vb - correction


func _constrain_walls() -> void:
	for gem in _gems:
		_constrain_one(gem)


func _constrain_one(gem: Dictionary) -> void:
	var pos: Vector2 = gem["pos"]
	var vel: Vector2 = gem["vel"]
	if pos.x < COLLIDE_R:
		pos.x = COLLIDE_R
		vel.x = 0.0
	elif pos.x > FIELD_W - COLLIDE_R:
		pos.x = FIELD_W - COLLIDE_R
		vel.x = 0.0
	if pos.y > FIELD_H - COLLIDE_R:
		pos.y = FIELD_H - COLLIDE_R
		if vel.y > 0.0:
			vel.y = 0.0
		vel.x *= 0.72
	gem["pos"] = pos
	gem["vel"] = vel


func _try_sleep(gem: Dictionary) -> void:
	var vel: Vector2 = gem["vel"]
	if vel.length() > 24.0:
		return
	var pos: Vector2 = gem["pos"]
	var supported := pos.y >= FIELD_H - COLLIDE_R - 0.8
	if not supported:
		var gem_id := int(gem["id"])
		for other in _gems:
			if int(other["id"]) == gem_id:
				continue
			var other_pos: Vector2 = other["pos"]
			if pos.distance_to(other_pos) > COLLIDE_R * 2.0 + 1.4:
				continue
			if other_pos.y >= pos.y - 3.0:
				supported = true
				break
	if supported:
		gem["vel"] = Vector2.ZERO


func _ceiling_blocked() -> bool:
	for gem in _gems:
		var pos: Vector2 = gem["pos"]
		var vel: Vector2 = gem["vel"]
		if pos.y > COLLIDE_R * 2.15:
			continue
		var still_entering := pos.y < COLLIDE_R and vel.y > 30.0
		if still_entering:
			continue
		if vel.length() < 80.0:
			return true
	return false


func _spawn_from_top() -> void:
	if _ceiling_blocked() or not roll_color.is_valid():
		return
	var x := _rng.randf_range(COLLIDE_R + 8.0, FIELD_W - COLLIDE_R - 8.0)
	var y := -GEM_RADIUS * 0.35
	if _overlaps(Vector2(x, y)):
		return
	_add_gem(int(roll_color.call()), x, y, _rng.randf_range(-16.0, 16.0), 34.0)


func _spawn_cluster() -> void:
	if _ceiling_blocked() or not roll_color.is_valid():
		return
	var color_index := int(roll_color.call())
	var gap := COLLIDE_R * 2.0
	var x := _rng.randf_range(COLLIDE_R + gap, FIELD_W - COLLIDE_R - gap)
	var layout: Array[Vector2] = [
		Vector2(0, 0),
		Vector2(gap, 4),
		Vector2(gap * 0.5, -gap * 0.88),
	]
	var base := Vector2(x, -COLLIDE_R * 0.2)
	for offset in layout:
		var pos := base + offset
		if _overlaps(pos):
			continue
		_add_gem(color_index, pos.x, pos.y, 0.0, 32.0)


func _seed_pile() -> void:
	if not roll_color.is_valid():
		return
	var gap := COLLIDE_R * 2.0
	var anchors: Array[Vector2] = [
		Vector2(130, 360),
		Vector2(310, 400),
		Vector2(470, 340),
		Vector2(200, 230),
		Vector2(400, 210),
	]
	var layout: Array[Vector2] = [
		Vector2(0, 0),
		Vector2(gap, 5),
		Vector2(gap * 0.5, -gap * 0.88),
	]
	for anchor in anchors:
		var color_index := int(roll_color.call())
		for offset in layout:
			var pos := anchor + offset
			pos.x = clampf(pos.x, COLLIDE_R, FIELD_W - COLLIDE_R)
			pos.y = clampf(pos.y, COLLIDE_R, FIELD_H - COLLIDE_R)
			if _overlaps(pos):
				continue
			_add_gem(color_index, pos.x, pos.y, 0.0, 36.0)


func _overlaps(point: Vector2) -> bool:
	for gem in _gems:
		var pos: Vector2 = gem["pos"]
		if point.distance_to(pos) < COLLIDE_R * 2.0 - 0.5:
			return true
	return false


func _add_gem(color_index: int, x: float, y: float, vx: float, vy: float) -> void:
	var pos := Vector2(x, y)
	var node := Node2D.new()
	node.position = pos
	node.z_index = 2
	add_child(node)
	if _line != null:
		move_child(node, _line.get_index())
	var gem := Polygon2D.new()
	gem.polygon = _gem_polygon()
	gem.color = Rules.GEM_COLORS[clampi(color_index, 0, Rules.GEM_COLORS.size() - 1)]
	node.add_child(gem)
	var facet := Polygon2D.new()
	facet.polygon = _facet_polygon()
	facet.color = Color(1, 1, 1, 0.42)
	node.add_child(facet)
	_gems.append({
		"id": _next_id,
		"color": color_index,
		"pos": pos,
		"vel": Vector2(vx, vy),
		"node": node,
		"gem": gem,
		"base": gem.color,
	})
	_next_id += 1


func _gem_by_id(id: int) -> Dictionary:
	for gem in _gems:
		if int(gem["id"]) == id:
			return gem
	return {}


func _paint_chain() -> void:
	var chosen := {}
	for id in _chain_ids:
		chosen[id] = true
	for gem in _gems:
		var poly: Polygon2D = gem["gem"]
		var node: Node2D = gem["node"]
		if not is_instance_valid(poly) or not is_instance_valid(node):
			continue
		if chosen.has(int(gem["id"])):
			poly.color = Color(gem["base"]).lightened(0.4)
			node.scale = Vector2(1.08, 1.08)
		else:
			poly.color = gem["base"]
			node.scale = Vector2.ONE


func _tint_stroke() -> void:
	if _chain_color < 0 or _line == null:
		return
	_line.default_color = Rules.GEM_COLORS[_chain_color]


func _consume_chain() -> void:
	var doomed := {}
	for id in _chain_ids:
		doomed[id] = true
	var kept: Array = []
	for gem in _gems:
		if doomed.has(int(gem["id"])):
			_pop_gem(gem)
		else:
			kept.append(gem)
	_gems = kept
	_clear_chain()


func _pop_gem(gem: Dictionary) -> void:
	var node: Node2D = gem["node"]
	if not is_instance_valid(node):
		return
	node.scale = Vector2.ONE
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(node, "scale", Vector2(0.05, 0.05), 0.12)
	tween.tween_property(node, "modulate:a", 0.0, 0.12)
	tween.chain().tween_callback(node.queue_free)


func _fade_stroke() -> void:
	if _line == null:
		return
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
	_clear_chain()
	if _line != null:
		_line.clear_points()


func _clear_chain() -> void:
	_chain_ids.clear()
	_chain_color = -1
	_paint_chain()


func _gem_polygon() -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 8:
		var angle := TAU * float(i) / 8.0 - PI * 0.5
		points.append(Vector2(cos(angle), sin(angle)) * GEM_RADIUS)
	return points


func _facet_polygon() -> PackedVector2Array:
	var radius := GEM_RADIUS * 0.42
	return PackedVector2Array([
		Vector2(0, -radius),
		Vector2(radius * 0.7, -radius * 0.15),
		Vector2(0, radius * 0.2),
		Vector2(-radius * 0.55, -radius * 0.1),
	])
