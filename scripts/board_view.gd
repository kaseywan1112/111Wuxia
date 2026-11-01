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
var _extra: Dictionary = {}
var _extra_node: Node2D
var _freeze := 0.0
var _charge := 0.0
var _shield := 0.0
var _shots: Array = []
var _shot_queue: Array = []
const WALL_TOP := 512.0
const SHOT_COLORS: Array[Color] = [
	Color("e85d4c"),
	Color("3d9ee0"),
	Color("5cbf6a"),
	Color("b07be0"),
	Color("f0d7a2"),
]
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
	_extra_node = Node2D.new()
	_extra_node.z_index = 7
	_extra_node.visible = false
	add_child(_extra_node)
	var extra_body := Polygon2D.new()
	extra_body.polygon = _circle(BALL_R, 10)
	extra_body.color = Color("ffb15a")
	_extra_node.add_child(extra_body)
	_prompt = Label.new()
	_prompt.position = Vector2(28, 16)
	_prompt.add_theme_font_size_override("font_size", 18)
	_prompt.add_theme_color_override("font_color", Color("f0d7a2"))
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_prompt)
	_add_wall(Rect2(0, 0, WALL, FIELD_H))
	_add_wall(Rect2(FIELD_W - WALL, 0, WALL, FIELD_H))
	_add_wall(Rect2(0, WALL_TOP, FIELD_W, FIELD_H - WALL_TOP))
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
	_freeze = 0.0
	_extra = {}
	if _extra_node != null:
		_extra_node.visible = false
	pending_picks = []
	_clear_actors()
	_hp_max = 72.0 + float(state.bonus_hp())
	_hp = _hp_max
	_shield = 0.0
	_charge = 0.15
	_shots = []
	_shot_queue = []
	_player = Vector2(FIELD_W * 0.5, WALL_TOP - 28.0)
	_spawn_monster(false, Vector2(FIELD_W * 0.38, 70.0))
	_spawn_monster(false, Vector2(FIELD_W * 0.66, 150.0))
	_prompt.text = "珠子在蓄力。右边交换同色宝石。"
	_draw_charge()


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
	_player = Vector2(FIELD_W * 0.5, WALL_TOP - 28.0)
	_draw_player()
	_charge_marble(delta)
	_drain_queue(delta)
	_move_shots(delta)
	_move_monsters(delta)
	_spawn_more(delta)
	_scroll_drops(delta)
	_collect()


func _unhandled_input(_event: InputEvent) -> void:
	return


func feed(color_index: int, length: int, kind: String) -> void:
	if not running or _paused or state == null:
		return
	var id := state.weapon_id_at(color_index)
	var name := state.weapon_name(id)
	if kind == "special" or length >= 5:
		_prompt.text = "%s · 特殊" % name
		_popup(_player, _prompt.text, SHOT_COLORS[color_index])
		_spawn_marble(color_index, "special")
		return
	var times := 1
	if kind == "burst" or length >= 4:
		times = state.burst_count(color_index)
		_prompt.text = "%s ×%d" % [name, times]
	else:
		_prompt.text = "%s · 满蓄" % name
	_popup(_player, _prompt.text, SHOT_COLORS[color_index])
	for i in times:
		_shot_queue.append({"t": float(i) * 0.18, "color": color_index, "mode": "full"})


func _charge_marble(delta: float) -> void:
	_charge += delta / state.auto_interval()
	_draw_charge()
	if _charge < 1.0:
		return
	_charge = 0.0
	_spawn_marble(state.color_index(), "full")
	_prompt.text = "%s · 蓄满射出" % state.weapon_name()


func _draw_charge() -> void:
	if _ball_node == null:
		return
	_ball_node.visible = true
	_ball_node.position = _player + Vector2(0, -20)
	var tint := _ball_node.get_child(0) as Polygon2D
	if tint != null:
		var index := state.color_index() if state != null else 0
		tint.color = SHOT_COLORS[index]
		tint.scale = Vector2.ONE * (0.35 + clampf(_charge, 0.0, 1.0) * 0.9)


func _drain_queue(delta: float) -> void:
	var kept: Array = []
	for item in _shot_queue:
		item["t"] = float(item["t"]) - delta
		if float(item["t"]) <= 0.0:
			_spawn_marble(int(item["color"]), str(item["mode"]))
		else:
			kept.append(item)
	_shot_queue = kept


func _spawn_marble(color_index: int, mode: String) -> void:
	var id := state.weapon_id_at(color_index)
	var style := state.weapon_style(id)
	if mode == "special":
		_cast_special(color_index, style)
		return
	if style == "guard":
		_heal_wall(float(state.guard_amount()))
		return
	var hits := 1
	if style == "pierce" or style == "slow":
		hits = 8
	var node := _make_shot(color_index, 1.0)
	_shots.append({
		"pos": _player + Vector2(0, -24),
		"vel": Vector2(0, -460),
		"style": style,
		"hits": hits,
		"power": 1.0,
		"amount": state.weapon_damage(id),
		"color": color_index,
		"seen": {},
		"node": node,
	})


func _cast_special(color_index: int, style: String) -> void:
	var amount := state.weapon_damage(state.weapon_id_at(color_index))
	if style == "hit":
		var node := _make_shot(color_index, 1.7)
		_shots.append({
			"pos": _player + Vector2(0, -24),
			"vel": Vector2(0, -420),
			"style": "hit",
			"hits": 1,
			"power": 3.0,
			"amount": amount,
			"color": color_index,
			"seen": {},
			"node": node,
		})
	elif style == "pierce" or style == "splash":
		_damage_all(amount * 1.3, "全中")
	elif style == "slow":
		for monster in _monsters:
			monster["slow"] = 3.2
		_popup(_player, "全场迟滞", SHOT_COLORS[color_index])
	else:
		_heal_wall(float(state.guard_amount()) * 2.0)
		_shield += float(state.guard_amount())
		_popup(_player, "大盾 +%d" % state.guard_amount(), SHOT_COLORS[color_index])


func _heal_wall(amount: float) -> void:
	_hp = minf(_hp + amount, _hp_max)
	_popup(Vector2(FIELD_W * 0.5, WALL_TOP - 8.0), "城墙 +%d" % int(amount), Color("9be7a8"))


func _damage_all(amount: float, text: String) -> void:
	var victims: Array = []
	for monster in _monsters:
		victims.append(monster)
	for monster in victims:
		_damage_monster(monster, amount, text)


func _make_shot(color_index: int, scale: float) -> Node2D:
	var node := Node2D.new()
	node.z_index = 7
	var body := Polygon2D.new()
	body.polygon = _circle(BALL_R * scale, 10)
	body.color = SHOT_COLORS[color_index]
	node.add_child(body)
	node.position = _player + Vector2(0, -24)
	add_child(node)
	return node


func _move_shots(delta: float) -> void:
	var kept: Array = []
	for shot in _shots:
		var pos: Vector2 = shot["pos"]
		var vel: Vector2 = shot["vel"]
		var nxt := pos + vel * delta
		var alive := true
		for monster in _monsters:
			var id := int(monster["id"])
			if shot["seen"].has(id):
				continue
			if nxt.distance_to(monster["pos"]) > float(monster["r"]) + BALL_R + 6.0:
				continue
			shot["seen"][id] = true
			var style := str(shot["style"])
			var amount := float(shot["amount"]) * float(shot["power"])
			if style == "slow":
				monster["slow"] = 2.2
				_damage_monster(monster, amount * 0.5, "慢")
			elif style == "splash":
				_damage_monster(monster, amount, str(int(amount)))
				_splash_around(monster, amount * 0.7)
				alive = false
				break
			else:
				_damage_monster(monster, amount, str(int(amount)))
			shot["hits"] = int(shot["hits"]) - 1
			if style == "hit" or int(shot["hits"]) <= 0:
				alive = false
				break
		if nxt.y < -20.0:
			alive = false
		shot["pos"] = nxt
		var node: Node2D = shot["node"]
		if is_instance_valid(node):
			node.position = nxt
			if not alive:
				node.queue_free()
		if alive:
			kept.append(shot)
	_shots = kept


func _splash_around(origin: Dictionary, amount: float) -> void:
	var victims: Array = []
	for monster in _monsters:
		if monster == origin:
			continue
		if monster["pos"].distance_to(origin["pos"]) <= 78.0:
			victims.append(monster)
	for monster in victims:
		_damage_monster(monster, amount, "溅")


func _damage_monster(monster: Dictionary, amount: float, text: String) -> void:
	if not _monsters.has(monster):
		return
	monster["hp"] = float(monster["hp"]) - amount
	monster["hit_cd"] = 0.12
	_popup(monster["pos"], text, Color("f0d7a2"))
	_refresh_bar(monster)
	if float(monster["hp"]) > 0.0:
		return
	_kill_monster(monster)


func _move_monsters(delta: float) -> void:
	var reached: Array = []
	for monster in _monsters:
		var pos: Vector2 = monster["pos"]
		var vel: Vector2 = monster["vel"]
		vel.x = clampf(vel.x + randf_range(-40.0, 40.0) * delta, -50.0, 50.0)
		vel.y = clampf(vel.y + randf_range(-20.0, 20.0) * delta, -16.0, 24.0)
		var slow := float(monster.get("slow", 0.0))
		if slow > 0.0:
			monster["slow"] = maxf(slow - delta, 0.0)
		var pace := 0.4 if slow > 0.0 else 1.0
		var drift := _scroll_speed
		if bool(monster["boss"]):
			drift *= 0.45
		pos.x += vel.x * delta * pace
		pos.y += drift * delta * pace
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
			node.modulate = Color(0.72, 0.7, 1.0) if slow > 0.0 else Color.WHITE
		if pos.y > WALL_TOP - float(monster["r"]):
			reached.append(monster)
	for monster in reached:
		_monster_passed(monster)


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


func resume_after_pick() -> void:
	pending_picks = []
	_paused = false
	if running:
		accept_input = true
		_prompt.text = "接着守城。"


func resume_lane() -> void:
	_paused = false
	if running:
		accept_input = true
		_prompt.text = "接着守城。"


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
	if _shield > 0.0:
		var used := minf(_shield, damage)
		_shield -= used
		damage -= used
	_hp -= damage
	_popup(Vector2(FIELD_W * 0.5, WALL_TOP - 8.0), "城墙 -%d" % int(ceil(damage)), Color("e07a72"))
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
	_ball = {}
	_extra = {}
	if _extra_node != null:
		_extra_node.visible = false
	_freeze = 0.0
	if _trail != null:
		_trail.clear_points()


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
