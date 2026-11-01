extends Control

const Rules = preload("res://scripts/run_state.gd")

const FIELD_W := 440.0
const FIELD_H := 560.0
const WALL := 22.0
const PLAYER_R := 16.0
const BALL_R := 9.0
const MONSTER_R := 20.0

signal cleared
signal died
signal caught_ball
signal looted(what: String)
signal needs_pick
signal lane_event(kind: String)

var running := false
var accept_input := false
var state: Rules = null

var _player := Vector2.ZERO
var _hp := 48.0
var _hp_max := 48.0
var _hurt_cd := 0.0
var _grace := 0.0
var _buff := 0.0
var _trail: Line2D
var _ball: Dictionary = {}
var _monsters: Array = []
var _drops: Array = []
var _paused := false
var _boss_alive := false
var _scroll_speed := 46.0
var _spawn_wait := 0.0
var _refire := 0.0
var _lanes: Array[ColorRect] = []
var pending_picks: Array[String] = []
var _player_node: Node2D
var _ball_node: Node2D
var _prompt: Label
var _next_id := 1


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
	_player_node = Node2D.new()
	_player_node.z_index = 6
	add_child(_player_node)
	_build_player()
	_ball_node = Node2D.new()
	_ball_node.z_index = 7
	_ball_node.visible = false
	add_child(_ball_node)
	_trail = Line2D.new()
	_trail.width = 4.0
	_trail.default_color = Color(0.96, 0.94, 0.9, 0.7)
	_trail.z_index = 6
	add_child(_trail)
	var ball_body := Polygon2D.new()
	ball_body.polygon = _circle(BALL_R, 10)
	ball_body.color = Color("f4f1ea")
	_ball_node.add_child(ball_body)
	_prompt = Label.new()
	_prompt.position = Vector2(28, 16)
	_prompt.add_theme_font_size_override("font_size", 18)
	_prompt.add_theme_color_override("font_color", Color("f0d7a2"))
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_prompt)
	_add_wall(Rect2(0, 0, WALL, FIELD_H))
	_add_wall(Rect2(FIELD_W - WALL, 0, WALL, FIELD_H))
	for i in 6:
		var lane := ColorRect.new()
		lane.color = Color(0.45, 0.55, 0.68, 0.28)
		lane.position = Vector2(WALL + 8.0, float(i) * (FIELD_H / 6.0))
		lane.size = Vector2(FIELD_W - WALL * 2.0 - 16.0, 3.0)
		lane.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lane.z_index = 1
		add_child(lane)
		_lanes.append(lane)


func begin(run_state: Rules) -> void:
	state = run_state
	running = true
	accept_input = true
	_boss_alive = false
	_buff = 0.0
	_hurt_cd = 0.0
	_grace = 1.2
	_paused = false
	_scroll_speed = 46.0 + float(state.area - 1) * 8.0
	_spawn_wait = 2.2
	_refire = 0.0
	pending_picks = []
	_clear_actors()
	_hp_max = 72.0 + float(state.bonus_hp())
	_hp = _hp_max
	_player = Vector2(FIELD_W * 0.5, FIELD_H - 70.0)
	_spawn_monster(false, Vector2(FIELD_W * 0.38, 70.0))
	_spawn_monster(false, Vector2(FIELD_W * 0.66, 150.0))
	_prompt.text = "窄道往上卷。漏下去会扣血。经验要走过去捡。"


func stop() -> void:
	running = false
	accept_input = false


func hp_ratio() -> float:
	return clampf(_hp / maxf(_hp_max, 1.0), 0.0, 1.0)


func ball_out() -> bool:
	return not _ball.is_empty()


func _process(delta: float) -> void:
	if not running or state == null:
		return
	delta = minf(delta, 0.05)
	_draw_player()
	if not accept_input:
		return
	if _paused:
		return
	if _buff > 0.0:
		_buff = maxf(_buff - delta, 0.0)
	if _refire > 0.0:
		_refire = maxf(_refire - delta, 0.0)
	var event := state.tick(delta)
	if event == "rest":
		_pause_for_event("rest")
		return
	if event == "boss":
		_spawn_monster(true, Vector2(FIELD_W * 0.5, -36.0))
		_boss_alive = true
		_prompt.text = "首领从上方来了。"
		lane_event.emit("boss")
	_scroll_lanes(delta)
	_move_player(delta)
	_move_monsters(delta)
	_spawn_more(delta)
	_move_ball(delta)
	_scroll_drops(delta)
	_collect()


func _unhandled_input(event: InputEvent) -> void:
	if not running or not accept_input or state == null:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			_try_shoot()
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_SPACE:
		_try_shoot()
		get_viewport().set_input_as_handled()


func _try_shoot() -> void:
	if _paused or _refire > 0.0 or not _ball.is_empty():
		return
	var speed := state.weapon_speed()
	var aim := _aim_angle()
	var vel := Vector2(sin(aim), -cos(aim)) * speed
	_ball = {
		"pos": _player + Vector2(0, -56),
		"vel": vel,
		"life": state.weapon_life(),
		"bounces": state.weapon_bounces(),
		"damp": state.weapon_damp(),
		"catch": state.weapon_needs_catch(),
		"heavy": state.weapon == "hammer",
		"arm": 0.35,
	}
	_ball_node.visible = true
	_ball_node.position = _ball["pos"]
	_trail.clear_points()
	var tint := _ball_node.get_child(0) as Polygon2D
	if state.weapon == "hammer":
		tint.color = Color("e07a3a")
		tint.scale = Vector2(1.7, 1.7)
	elif state.weapon == "return":
		tint.color = Color("f0d7a2")
		tint.scale = Vector2.ONE
	else:
		tint.color = Color("f7f4ee")
		tint.scale = Vector2.ONE


func _aim_angle() -> float:
	var mouse := get_local_mouse_position()
	var dx := mouse.x - _player.x
	var dy := _player.y - mouse.y
	if dy < 24.0:
		dy = 24.0
	return clampf(atan2(dx, dy), -1.05, 1.05)


func _move_player(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if dir.length() > 0.0:
		dir = dir.normalized()
	_player += dir * 250.0 * delta
	_player.x = clampf(_player.x, WALL + PLAYER_R, FIELD_W - WALL - PLAYER_R)
	_player.y = clampf(_player.y, 10.0 + PLAYER_R, FIELD_H - 10.0 - PLAYER_R)
	_player_node.position = _player


func _move_monsters(delta: float) -> void:
	var leaked: Array = []
	for monster in _monsters:
		var pos: Vector2 = monster["pos"]
		var vel: Vector2 = monster["vel"]
		vel.x = clampf(vel.x + randf_range(-40.0, 40.0) * delta, -50.0, 50.0)
		vel.y = clampf(vel.y + randf_range(-20.0, 20.0) * delta, -16.0, 24.0)
		var drift := _scroll_speed
		if bool(monster["boss"]):
			drift *= 0.35
		pos += vel * delta
		pos.y += drift * delta
		var radius := float(monster["r"])
		if pos.x < WALL + radius:
			pos.x = WALL + radius
			vel.x = absf(vel.x)
		elif pos.x > FIELD_W - WALL - radius:
			pos.x = FIELD_W - WALL - radius
			vel.x = -absf(vel.x)
		monster["pos"] = pos
		monster["vel"] = vel
		monster["hit_cd"] = maxf(float(monster["hit_cd"]) - delta, 0.0)
		var node: Node2D = monster["node"]
		if is_instance_valid(node):
			node.position = pos
		if pos.y > _player.y + 6.0:
			leaked.append(monster)
	for monster in leaked:
		_monster_passed(monster)


func _touch_player(delta: float) -> void:
	_grace = maxf(_grace - delta, 0.0)
	_hurt_cd = maxf(_hurt_cd - delta, 0.0)
	if _grace > 0.0 or _hurt_cd > 0.0:
		return
	for monster in _monsters:
		var pos: Vector2 = monster["pos"]
		if pos.distance_to(_player) > float(monster["r"]) + PLAYER_R:
			continue
		var damage := 10.0
		if bool(monster["boss"]):
			damage = 16.0
		damage = maxf(damage - float(state.armor_reduction()), 4.0)
		_hp -= damage
		_hurt_cd = 0.55
		_popup(_player, "-%d" % int(damage), Color("e07a72"))
		if _hp <= 0.0:
			_hp = 0.0
			running = false
			accept_input = false
			died.emit()
		return


func _move_ball(delta: float) -> void:
	if _ball.is_empty():
		_ball_node.visible = false
		return
	var left := delta
	var guard := 0
	while left > 0.0 and not _ball.is_empty() and guard < 24:
		guard += 1
		var vel_now: Vector2 = _ball["vel"]
		var speed := maxf(vel_now.length(), 1.0)
		var step := minf(left, 6.0 / speed)
		if not _step_ball(step):
			return
		left -= step
	if _ball.is_empty():
		return
	var pos: Vector2 = _ball["pos"]
	_ball_node.visible = true
	_ball_node.position = pos
	_ball_node.rotation = Vector2(_ball["vel"]).angle() + PI / 2.0
	if _trail.get_point_count() == 0 or _trail.get_point_position(_trail.get_point_count() - 1).distance_to(pos) > 16.0:
		_trail.add_point(pos)
	if _trail.get_point_count() > 14:
		_trail.remove_point(0)


func _step_ball(delta: float) -> bool:
	var pos: Vector2 = _ball["pos"]
	var vel: Vector2 = _ball["vel"]
	var nxt := pos + vel * delta
	var damp := float(_ball["damp"])
	var bounced := false
	if nxt.x < WALL + BALL_R:
		nxt.x = WALL + BALL_R
		vel.x = absf(vel.x) * damp
		bounced = true
	elif nxt.x > FIELD_W - WALL - BALL_R:
		nxt.x = FIELD_W - WALL - BALL_R
		vel.x = -absf(vel.x) * damp
		bounced = true
	if nxt.y < 6.0 + BALL_R:
		nxt.y = 6.0 + BALL_R
		vel.y = absf(vel.y) * damp
		bounced = true
	elif nxt.y > FIELD_H - 6.0 - BALL_R:
		nxt.y = FIELD_H - 6.0 - BALL_R
		vel.y = -absf(vel.y) * damp
		bounced = true
	if bounced:
		vel = vel.rotated(randf_range(-0.22, 0.22))
		if int(_ball["bounces"]) >= 0:
			_ball["bounces"] = int(_ball["bounces"]) - 1
	var hit := _monster_hit_sweep(pos, nxt)
	if not hit.is_empty():
		var at: Vector2 = hit["pos"]
		var touch: Vector2 = hit["hit_at"]
		var normal := touch - at
		if normal.length() < 1.0:
			normal = Vector2.UP
		normal = normal.normalized()
		var speed := maxf(vel.length(), 80.0)
		vel = normal * speed * damp
		nxt = at + normal * (float(hit["r"]) + BALL_R + 2.0)
		_hurt_monster(hit)
		if _ball.is_empty():
			return false
		if bool(_ball["heavy"]):
			_ball["bounces"] = int(_ball["bounces"]) - 1
	_ball["arm"] = maxf(float(_ball["arm"]) - delta, 0.0)
	if bool(_ball["catch"]) and float(_ball["arm"]) <= 0.0 and nxt.distance_to(_player) < PLAYER_R + BALL_R + 18.0:
		_catch()
		return false
	if not bool(_ball["heavy"]) and vel.length() < state.weapon_speed() * 0.72:
		vel = vel.normalized() * state.weapon_speed() * 0.85
	_ball["pos"] = nxt
	_ball["vel"] = vel
	if state.weapon_life() > 0.0:
		_ball["life"] = float(_ball["life"]) - delta
	if state.weapon_life() > 0.0 and float(_ball["life"]) <= 0.0:
		_drop_ball()
		return false
	if int(_ball["bounces"]) < 0 and state.weapon_bounces() >= 0:
		_drop_ball()
		return false
	if bool(_ball["heavy"]) and vel.length() < 90.0:
		_drop_ball()
		return false
	return true


func _monster_hit_sweep(a: Vector2, b: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 9999.0
	for monster in _monsters:
		if float(monster["hit_cd"]) > 0.0:
			continue
		var at: Vector2 = monster["pos"]
		var touch := _closest_on_segment(a, b, at)
		var dist := touch.distance_to(at)
		var limit := float(monster["r"]) + BALL_R + 8.0
		if dist <= limit and dist < best_d:
			best_d = dist
			best = monster
			best["hit_at"] = touch
	return best


func _closest_on_segment(a: Vector2, b: Vector2, point: Vector2) -> Vector2:
	var span := b - a
	var length_sq := span.length_squared()
	if length_sq < 0.001:
		return b
	var t := clampf((point - a).dot(span) / length_sq, 0.0, 1.0)
	return a + span * t


func _hurt_monster(monster: Dictionary) -> void:
	var amount := state.weapon_damage()
	if _buff > 0.0:
		amount *= 1.5
	monster["hp"] = float(monster["hp"]) - amount
	monster["hit_cd"] = 0.16
	_popup(monster["pos"], str(int(round(amount))), Color("f0d7a2"))
	_refresh_bar(monster)
	if float(monster["hp"]) > 0.0:
		return
	_kill_monster(monster)


func _kill_monster(monster: Dictionary) -> void:
	var pos: Vector2 = monster["pos"]
	var node: Node = monster["node"]
	if is_instance_valid(node):
		node.queue_free()
	_monsters.erase(monster)
	_spawn_drop("xp", "", state.gold_per_kill(), pos)
	var force := state.note_forced_drop() or bool(monster["boss"])
	var gear_id := state.roll_gear(force)
	if gear_id != "":
		state.pickup_gear(gear_id)
		_popup(pos, "入包 " + state.gear_name(gear_id), Color("7ec8e3"))
		looted.emit("gear")
	state.note_kill()
	if bool(monster["boss"]):
		_boss_alive = false
		state.on_boss_killed()
		_pause_for_event("boss_down")


func _catch() -> void:
	var bonus := state.catch_gold()
	_drop_ball()
	state.pickup_gold(bonus)
	_buff = 4.0
	_popup(_player + Vector2(0, -24), "接住了 +%d" % bonus, Color("f0d7a2"))
	looted.emit("gold")
	caught_ball.emit()


func resume_after_pick() -> void:
	pending_picks = []
	_paused = false
	if running:
		accept_input = true
		_prompt.text = "窄道还在往上卷。"


func resume_lane() -> void:
	_paused = false
	if running:
		accept_input = true
		_prompt.text = "窄道还在往上卷。"


func _drop_ball() -> void:
	if not _ball.is_empty() and state != null:
		_refire = state.refire_delay()
	_ball = {}
	_ball_node.visible = false
	if _trail != null:
		_trail.clear_points()


func _scroll_lanes(delta: float) -> void:
	var step := _scroll_speed * delta
	for lane in _lanes:
		lane.position.y += step
		if lane.position.y > FIELD_H:
			lane.position.y -= FIELD_H


func _scroll_drops(delta: float) -> void:
	var kept: Array = []
	for drop in _drops:
		var pos: Vector2 = drop["pos"]
		pos.y += _scroll_speed * delta
		if pos.y > FIELD_H + 20.0:
			var node: Node = drop["node"]
			if is_instance_valid(node):
				node.queue_free()
			continue
		drop["pos"] = pos
		var node: Node2D = drop["node"]
		if is_instance_valid(node):
			node.position = pos
		kept.append(drop)
	_drops = kept


func _monster_passed(monster: Dictionary) -> void:
	if not running:
		return
	var boss := bool(monster["boss"])
	var damage := float(state.pass_damage(boss) - state.armor_reduction())
	damage = maxf(damage, 4.0)
	_hp -= damage
	_popup(_player, "漏过 -%d" % int(damage), Color("e07a72"))
	var node: Node = monster["node"]
	if is_instance_valid(node):
		node.queue_free()
	_monsters.erase(monster)
	if boss:
		_boss_alive = false
		state.boss_leaked()
	if _hp <= 0.0:
		_hp = 0.0
		running = false
		accept_input = false
		died.emit()


func _spawn_more(delta: float) -> void:
	_spawn_wait -= delta
	if _spawn_wait > 0.0:
		return
	_spawn_wait = maxf(1.3, 2.6 - float(state.area - 1) * 0.3)
	var cap := 3 + mini(state.area, 4)
	if _monsters.size() >= cap:
		return
	var x := randf_range(WALL + 36.0, FIELD_W - WALL - 36.0)
	_spawn_monster(false, Vector2(x, -28.0))


func _pause_for_event(kind: String) -> void:
	_paused = true
	accept_input = false
	lane_event.emit(kind)


func _dismiss_monsters() -> void:
	for monster in _monsters:
		var node: Node = monster["node"]
		if is_instance_valid(node):
			node.queue_free()
	_monsters.clear()


func _collect() -> void:
	var kept: Array = []
	for drop in _drops:
		var pos: Vector2 = drop["pos"]
		if pos.distance_to(_player) <= 36.0 and str(drop["kind"]) == "xp":
			state.pickup_gold(int(drop["amount"]))
			var leveled := state.add_xp(1)
			_popup(pos, "经验", Color("9be7a8"))
			looted.emit("xp")
			if leveled:
				pending_picks = state.offer_picks()
				_paused = true
				accept_input = false
				_prompt.text = "经验够了。选一个，只在这一局。"
				needs_pick.emit()
			var node: Node = drop["node"]
			if is_instance_valid(node):
				node.queue_free()
			continue
		kept.append(drop)
	_drops = kept


func _spawn_pack(boss: bool) -> void:
	var count := state.monster_count()
	if boss:
		_spawn_monster(true, Vector2(FIELD_W * 0.5, 150.0))
		count = 4
	for i in count:
		var x := randf_range(FIELD_W * 0.22, FIELD_W * 0.78)
		var y := randf_range(28.0, FIELD_H * 0.42)
		_spawn_monster(false, Vector2(x, y))


func _spawn_monster(boss: bool, pos: Vector2) -> void:
	var radius := 34.0 if boss else MONSTER_R
	var node := _make_monster(boss, radius)
	node.position = pos
	node.z_index = 3
	add_child(node)
	var hp := state.monster_hp(boss)
	_monsters.append({
		"id": _next_id,
		"hp": hp,
		"max_hp": hp,
		"pos": pos,
		"vel": Vector2(randf_range(-28.0, 28.0), randf_range(-8.0, 16.0)),
		"r": radius,
		"boss": boss,
		"hit_cd": 0.0,
		"node": node,
	})
	_next_id += 1


func _spawn_drop(kind: String, id: String, amount: int, pos: Vector2) -> void:
	var node := Node2D.new()
	node.z_index = 4
	node.position = pos
	var body := Polygon2D.new()
	body.polygon = _circle(8.0, 6)
	body.color = Color("9be7a8")
	node.add_child(body)
	var label := Label.new()
	label.text = "经验"
	label.position = Vector2(-16, 8)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color("9be7a8"))
	node.add_child(label)
	add_child(node)
	_drops.append({
		"kind": kind,
		"id": id,
		"amount": amount,
		"pos": pos,
		"node": node,
	})


func _clear_actors() -> void:
	for monster in _monsters:
		var node: Node = monster["node"]
		if is_instance_valid(node):
			node.queue_free()
	for drop in _drops:
		var node: Node = drop["node"]
		if is_instance_valid(node):
			node.queue_free()
	_monsters.clear()
	_drops.clear()
	_drop_ball()


func _build_player() -> void:
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-14, 12), Vector2(14, 12), Vector2(10, -8), Vector2(0, -16), Vector2(-10, -8),
	])
	body.color = Color("d9c7a2")
	_player_node.add_child(body)


func _draw_player() -> void:
	_player_node.position = _player


func _make_monster(boss: bool, radius: float) -> Node2D:
	var node := Node2D.new()
	var body := Polygon2D.new()
	body.polygon = _circle(radius, 8)
	body.color = Color("c4554a") if boss else Color("5cbf6a")
	if not boss and randi() % 2 == 0:
		body.color = Color("3d9ee0")
	node.add_child(body)
	var eye := Polygon2D.new()
	eye.polygon = _circle(3.2, 6)
	eye.color = Color("1a1d24")
	eye.position = Vector2(-6, -4)
	node.add_child(eye)
	var eye_r := Polygon2D.new()
	eye_r.polygon = _circle(3.2, 6)
	eye_r.color = Color("1a1d24")
	eye_r.position = Vector2(6, -4)
	node.add_child(eye_r)
	var bar := Polygon2D.new()
	bar.name = "hp"
	bar.color = Color("f0d7a2")
	bar.polygon = PackedVector2Array([
		Vector2(-12, radius - 2.0), Vector2(12, radius - 2.0),
		Vector2(12, radius + 2.0), Vector2(-12, radius + 2.0),
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
	var ratio := clampf(float(monster["hp"]) / float(monster["max_hp"]), 0.0, 1.0)
	var width := 24.0 * ratio
	var y := float(monster["r"]) - 2.0
	bar.polygon = PackedVector2Array([
		Vector2(-12, y), Vector2(-12 + width, y),
		Vector2(-12 + width, y + 4.0), Vector2(-12, y + 4.0),
	])


func _popup(at: Vector2, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = at + Vector2(-20, -26)
	label.z_index = 8
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "position", label.position + Vector2(0, -22), 0.45)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.45)
	tween.finished.connect(label.queue_free)


func _circle(radius: float, sides: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in sides:
		var angle := TAU * float(i) / float(sides)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


func _add_wall(rect: Rect2) -> void:
	var wall := ColorRect.new()
	wall.color = Color("8aa0b8")
	wall.position = rect.position
	wall.size = rect.size
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wall.z_index = 5
	add_child(wall)
