extends Control

const Rules = preload("res://scripts/run_state.gd")

const FIELD_W := 760.0
const FIELD_H := 690.0
const MONSTER_R := 22.0
const DEATH_Y := 612.0

signal struck_same(color_index: int, victims: int, amount: float)
signal struck_basic(amount: float)
signal killed
signal crushed

var accept_input := false
var running := false
var state: Rules = null

var _monsters: Array = []
var _shots: Array = []
var _next_id := 1
var _spawn_wait := 0.4
var _attack_wait := 0.35
var _swing := 0.0
var _player: Node2D
var _swing_arc: Polygon2D


func _ready() -> void:
	custom_minimum_size = Vector2(FIELD_W, FIELD_H)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	var background := ColorRect.new()
	background.color = Color("10151d")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_swing_arc = Polygon2D.new()
	_swing_arc.color = Color(1, 1, 1, 0.16)
	_swing_arc.z_index = 3
	add_child(_swing_arc)
	_player = Node2D.new()
	_player.z_index = 6
	add_child(_player)
	_build_player()


func _build_player() -> void:
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-18, 16), Vector2(18, 16), Vector2(14, -10), Vector2(0, -22), Vector2(-14, -10),
	])
	body.color = Color("d9c7a2")
	_player.add_child(body)
	var head := Polygon2D.new()
	head.polygon = _hex(8.0)
	head.color = Color("f0e2c4")
	head.position = Vector2(0, -16)
	_player.add_child(head)


func begin(run_state: Rules) -> void:
	state = run_state
	running = true
	accept_input = true
	_clear()
	_spawn_wait = 0.15
	_attack_wait = 0.32
	_swing = 0.0
	_place_player()


func stop() -> void:
	running = false
	accept_input = false


func _process(delta: float) -> void:
	if not running or state == null:
		return
	_place_player()
	_draw_swing()
	if not accept_input:
		return
	_tick_monsters(delta)
	_tick_spawn(delta)
	_tick_attack(delta)
	_tick_shots(delta)
	_check_crush()


func _player_pos() -> Vector2:
	return Vector2(FIELD_W * 0.5, FIELD_H - 64.0)


func _place_player() -> void:
	_player.position = _player_pos()


func _tick_monsters(delta: float) -> void:
	var home := _player_pos()
	for monster in _monsters:
		var pos: Vector2 = monster["pos"]
		var speed := float(monster["speed"])
		pos.y += speed * delta
		var drift := clampf(home.x - pos.x, -1.0, 1.0) * 36.0 * delta
		pos.x = clampf(pos.x + drift, MONSTER_R + 8.0, FIELD_W - MONSTER_R - 8.0)
		monster["pos"] = pos
		var node: Node2D = monster["node"]
		if is_instance_valid(node):
			node.position = pos


func _tick_spawn(delta: float) -> void:
	_spawn_wait -= delta
	if _spawn_wait > 0.0 or _monsters.size() >= 8:
		return
	_spawn_wait = 0.8
	_spawn_monster()


func _spawn_monster() -> void:
	var color_index := state.rng.randi() % 5
	if state.rng.randi() % 8 < 3:
		color_index = state.attack_color
	var x := state.rng.randf_range(70.0, FIELD_W - 70.0)
	var node := _make_monster(color_index)
	var pos := Vector2(x, -16.0)
	node.position = pos
	node.z_index = 2
	add_child(node)
	var monster := {
		"id": _next_id,
		"color": color_index,
		"hp": Rules.MONSTER_HP,
		"speed": state.rng.randf_range(34.0, 46.0),
		"pos": pos,
		"node": node,
	}
	_next_id += 1
	_monsters.append(monster)


func _tick_attack(delta: float) -> void:
	if _swing > 0.0:
		_swing = maxf(_swing - delta, 0.0)
	_attack_wait -= delta
	if _attack_wait > 0.0:
		return
	_attack_wait = state.attack_interval()
	if state.attack_kind == "melee":
		_swing_once()
	else:
		_fire_burst()


func _swing_once() -> void:
	_swing = 0.16
	var hit: Array = []
	for monster in _monsters:
		var pos: Vector2 = monster["pos"]
		if _in_swing(pos):
			hit.append(monster)
	for monster in hit:
		_resolve_hit(monster)


func _in_swing(pos: Vector2) -> bool:
	var delta := pos - _player_pos()
	if delta.length() > state.melee_reach():
		return false
	if delta.y > -6.0:
		return false
	var ang := absf(atan2(delta.x, -delta.y))
	return ang <= state.melee_arc()


func _fire_burst() -> void:
	var count := state.projectile_count()
	var mid := (count - 1) * 0.5
	for i in count:
		var ang := (float(i) - mid) * 0.2
		_fire_one(ang)


func _fire_one(ang: float) -> void:
	var dir := Vector2(sin(ang), -cos(ang))
	var node := _make_shot(state.attack_color)
	var pos := _player_pos() + dir * 36.0
	node.position = pos
	node.rotation = dir.angle() + PI / 2.0
	node.z_index = 4
	add_child(node)
	_shots.append({
		"pos": pos,
		"dir": dir,
		"node": node,
		"life": 0.0,
	})


func _tick_shots(delta: float) -> void:
	var kept: Array = []
	for shot in _shots:
		var pos: Vector2 = shot["pos"]
		var dir: Vector2 = shot["dir"]
		pos += dir * 720.0 * delta
		shot["life"] = float(shot["life"]) + delta
		shot["pos"] = pos
		var node: Node2D = shot["node"]
		if is_instance_valid(node):
			node.position = pos
		var hit := _monster_at(pos, MONSTER_R + 10.0)
		if not hit.is_empty():
			if is_instance_valid(node):
				node.queue_free()
			_resolve_hit(hit)
			continue
		if pos.y < -30.0 or pos.x < -20.0 or pos.x > FIELD_W + 20.0 or float(shot["life"]) > 2.4:
			if is_instance_valid(node):
				node.queue_free()
			continue
		kept.append(shot)
	_shots = kept


func _monster_at(pos: Vector2, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := radius
	for monster in _monsters:
		var at: Vector2 = monster["pos"]
		var dist := pos.distance_to(at)
		if dist < best_d:
			best_d = dist
			best = monster
	return best


func _resolve_hit(monster: Dictionary) -> void:
	if not _alive(monster):
		return
	var color_index := int(monster["color"])
	if color_index == state.attack_color:
		var big := state.same_damage()
		var chain := state.chain_damage()
		_hurt(monster, big)
		var victims := 1
		var others: Array = []
		for other in _monsters:
			if other == monster:
				continue
			if int(other["color"]) != color_index:
				continue
			if not _alive(other):
				continue
			others.append(other)
		for other in others:
			_hurt(other, chain)
			victims += 1
		struck_same.emit(color_index, victims, big)
		_reap()
		return
	_hurt(monster, state.basic_damage())
	struck_basic.emit(state.basic_damage())
	_reap()


func _hurt(monster: Dictionary, amount: float) -> void:
	monster["hp"] = float(monster["hp"]) - amount
	_popup(monster["pos"], str(int(round(amount))), Rules.GEM_COLORS[int(monster["color"])])
	_refresh_bar(monster)


func _reap() -> void:
	var kept: Array = []
	for monster in _monsters:
		if float(monster["hp"]) <= 0.0:
			var node: Node = monster["node"]
			if is_instance_valid(node):
				node.queue_free()
			killed.emit()
		else:
			kept.append(monster)
	_monsters = kept


func _alive(monster: Dictionary) -> bool:
	return float(monster["hp"]) > 0.0


func _check_crush() -> void:
	for monster in _monsters:
		var pos: Vector2 = monster["pos"]
		if pos.y + MONSTER_R >= DEATH_Y:
			running = false
			accept_input = false
			crushed.emit()
			return


func _draw_swing() -> void:
	_swing_arc.polygon = PackedVector2Array()
	if state == null or _swing <= 0.0 or state.attack_kind != "melee":
		return
	var origin := _player_pos()
	var reach := state.melee_reach()
	var arc := state.melee_arc()
	var points := PackedVector2Array()
	points.append(origin)
	for i in 9:
		var ang := -arc + (arc * 2.0) * float(i) / 8.0
		points.append(origin + Vector2(sin(ang), -cos(ang)) * reach)
	_swing_arc.polygon = points
	_swing_arc.color = Rules.GEM_COLORS[state.attack_color]
	_swing_arc.color.a = 0.38


func _clear() -> void:
	for monster in _monsters:
		var node: Node = monster["node"]
		if is_instance_valid(node):
			node.queue_free()
	for shot in _shots:
		var node: Node = shot["node"]
		if is_instance_valid(node):
			node.queue_free()
	_monsters.clear()
	_shots.clear()


func _make_monster(color_index: int) -> Node2D:
	var node := Node2D.new()
	var body := Polygon2D.new()
	body.polygon = _hex(MONSTER_R)
	body.color = Rules.GEM_COLORS[color_index]
	node.add_child(body)
	var eye_l := Polygon2D.new()
	eye_l.polygon = _hex(3.4)
	eye_l.color = Color("1a1d24")
	eye_l.position = Vector2(-7, -5)
	node.add_child(eye_l)
	var eye_r := Polygon2D.new()
	eye_r.polygon = _hex(3.4)
	eye_r.color = Color("1a1d24")
	eye_r.position = Vector2(7, -5)
	node.add_child(eye_r)
	var bar := Polygon2D.new()
	bar.name = "hp"
	bar.color = Color("f0d7a2")
	bar.polygon = PackedVector2Array([
		Vector2(-14, 14), Vector2(14, 14), Vector2(14, 17), Vector2(-14, 17),
	])
	node.add_child(bar)
	return node


func _refresh_bar(monster: Dictionary) -> void:
	var node: Node2D = monster["node"]
	if not is_instance_valid(node):
		return
	var bar := node.get_node_or_null("hp") as Polygon2D
	if bar == null:
		return
	var ratio := clampf(float(monster["hp"]) / Rules.MONSTER_HP, 0.0, 1.0)
	var width := 28.0 * ratio
	bar.polygon = PackedVector2Array([
		Vector2(-14, 14), Vector2(-14 + width, 14), Vector2(-14 + width, 17), Vector2(-14, 17),
	])
	bar.color = Color("f0d7a2") if ratio > 0.35 else Color("e07a72")


func _make_shot(color_index: int) -> Node2D:
	var node := Node2D.new()
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(0, -14), Vector2(4, 7), Vector2(0, 3), Vector2(-4, 7),
	])
	body.color = Rules.GEM_COLORS[color_index]
	node.add_child(body)
	return node


func _popup(at: Vector2, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = at + Vector2(-18, -28)
	label.z_index = 8
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "position", label.position + Vector2(0, -24), 0.45)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.45)
	tween.finished.connect(label.queue_free)


func _hex(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 6:
		var angle := TAU * float(i) / 6.0 - PI / 6.0
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


func _draw() -> void:
	draw_line(Vector2(28, DEATH_Y), Vector2(FIELD_W - 28, DEATH_Y), Color(0.85, 0.35, 0.32, 0.45), 2.0)
