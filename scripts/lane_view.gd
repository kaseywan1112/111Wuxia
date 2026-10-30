extends Control

const Rules = preload("res://scripts/run_state.gd")

const LANE_W := 580.0
const LANE_H := 690.0
const STOP_Y := 132.0
const SPAWN_Y := 630.0
const WALL_Y := 390.0

signal player_damaged(amount: int)
signal foe_killed(gold: int)
signal fight_cleared
signal spell_hit(school: String)

var freeze_bonus := 0.0
var summon_bonus := 0.0
var fx_parent: Node = null

var _foes: Array = []
var _missiles: Array = []
var _schedule: Array = []
var _clock := 0.0
var _next_id := 1
var _spawn_slot := 0
var _wall_time := 0.0
var _summon_time := 0.0
var _summon_cd := 0.0
var _slow_time := 0.0
var _cleared := false
var _running := false
var _player_hp := 110
var _player_max := 110

var _wall: ColorRect
var _summon: Control
var _player_fill: ColorRect
var _player_label: Label
var _flash: ColorRect


func _ready() -> void:
	custom_minimum_size = Vector2(LANE_W, LANE_H)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_static()


func set_fx(node: Node) -> void:
	fx_parent = node


func begin_fight(kind: String, variant: int, current_hp: int, max_hp: int) -> void:
	_clear_dynamic()
	_clock = 0.0
	_spawn_slot = 0
	_wall_time = 0.0
	_summon_time = 0.0
	_summon_cd = 0.0
	_slow_time = 0.0
	_cleared = false
	_running = true
	_wall.visible = false
	_summon.visible = false
	set_player_hp(current_hp, max_hp)
	_queue_for(kind, variant)


func stop() -> void:
	_running = false


func set_player_hp(current_hp: int, max_hp: int) -> void:
	_player_hp = current_hp
	_player_max = maxi(max_hp, 1)
	_player_label.text = "你  %d / %d" % [_player_hp, _player_max]
	_player_fill.size.x = 150.0 * clampf(float(_player_hp) / float(_player_max), 0.0, 1.0)


func apply_global_slow(duration: float) -> void:
	_slow_time = maxf(_slow_time, duration)


func flash_school(school: String) -> void:
	_pulse_flash(_school_color(school))


func cast(school: String, kind: String, damage: float, from_global: Vector2, empowered: bool) -> void:
	# The lane reacts on this frame. The flying gem is only the streak.
	_pulse_flash(_school_color(school))
	var target: Dictionary = _front_foe()
	var dest := global_position + Vector2(LANE_W * 0.5, LANE_H * 0.45)
	var target_id := -1
	if target.is_empty():
		spell_hit.emit(school)
	else:
		dest = _foe_center(target)
		target_id = int(target["id"])
		_impact({"school": school, "kind": kind, "damage": damage}, target)
	_launch(from_global, dest, school, kind, 0.0, target_id, empowered, 1800.0, true)


func tick(delta: float) -> void:
	if not _running:
		return
	_clock += delta
	if _slow_time > 0.0:
		_slow_time = maxf(_slow_time - delta, 0.0)
	if _wall_time > 0.0:
		_wall_time = maxf(_wall_time - delta, 0.0)
		_wall.visible = _wall_time > 0.0
	_spawn_due()
	_tick_summon(delta)
	_tick_foes(delta)
	_tick_missiles(delta)
	_sweep()
	if not _cleared and _schedule.is_empty() and _foes.is_empty() and _missiles.is_empty() and _clock > 0.4:
		_cleared = true
		_running = false
		fight_cleared.emit()


func _queue_for(kind: String, variant: int) -> void:
	_schedule.clear()
	if kind == "boss":
		_schedule.append({"kind": "boss", "at": 0.35})
	elif kind == "elite":
		_schedule.append({"kind": "elite", "at": 0.4})
		_schedule.append({"kind": "runner", "at": 7.5})
	elif variant == 1:
		_schedule.append({"kind": "grunt", "at": 0.35})
		_schedule.append({"kind": "runner", "at": 5.2})
		_schedule.append({"kind": "grunt", "at": 10.4})
	else:
		_schedule.append({"kind": "grunt", "at": 0.35})
		_schedule.append({"kind": "grunt", "at": 6.0})
		_schedule.append({"kind": "grunt", "at": 11.5})


func _spawn_due() -> void:
	var pending: Array = []
	for item in _schedule:
		if float(item["at"]) <= _clock:
			_spawn_foe(str(item["kind"]))
		else:
			pending.append(item)
	_schedule = pending


func _spawn_foe(kind: String) -> void:
	var stats: Dictionary = Rules.FOES[kind]
	var foe := {
		"id": _next_id,
		"kind": kind,
		"hp": float(stats["hp"]),
		"max_hp": float(stats["hp"]),
		"y": SPAWN_Y,
		"x_off": float([-90, 0, 90][_spawn_slot % 3]),
		"speed": float(stats["speed"]),
		"touch": int(stats["touch"]),
		"gold": int(stats["gold"]),
		"name": str(stats["name"]),
		"attack": 0.45,
		"burn": 0.0,
		"burn_dps": 0.0,
		"burn_show": 0.0,
		"freeze": 0.0,
		"slow": 0.0,
		"stun": 0.0,
		"split": false,
		"dead": false,
		"root": null,
		"body": null,
		"fill": null,
		"status": null,
		"base": _foe_color(kind),
	}
	_next_id += 1
	_spawn_slot += 1
	if kind == "boss":
		foe["x_off"] = 0.0
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.size = Vector2(120, 120)
	add_child(root)
	var body := Polygon2D.new()
	body.polygon = _foe_polygon(kind)
	body.color = foe["base"]
	body.position = Vector2(60, 78)
	root.add_child(body)
	var track := ColorRect.new()
	track.color = Color("2a303c")
	track.position = Vector2(14, 8)
	track.size = Vector2(92, 8)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(track)
	var fill := ColorRect.new()
	fill.color = Color("d4544a")
	fill.position = Vector2(14, 8)
	fill.size = Vector2(92, 8)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fill)
	var name_label := Label.new()
	name_label.text = str(foe["name"])
	name_label.position = Vector2(8, 18)
	name_label.size = Vector2(104, 22)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color("f4f1ea"))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(name_label)
	var status := Label.new()
	status.position = Vector2(0, 96)
	status.size = Vector2(120, 20)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 12)
	status.add_theme_color_override("font_color", Color("f0d7a2"))
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(status)
	foe["root"] = root
	foe["body"] = body
	foe["fill"] = fill
	foe["status"] = status
	_foes.append(foe)
	_place(foe)


func _tick_foes(delta: float) -> void:
	for foe in _foes:
		if foe["dead"]:
			continue
		_decay_status(foe, delta)
		var speed: float = foe["speed"]
		if _slow_time > 0.0:
			speed *= 0.55
		if foe["slow"] > 0.0:
			speed *= 0.42
		if foe["freeze"] > 0.0 or foe["stun"] > 0.0:
			speed = 0.0
		var next_y: float = float(foe["y"]) - speed * delta
		if _wall_time > 0.0 and float(foe["y"]) > WALL_Y + 20.0 and next_y < WALL_Y + 34.0:
			next_y = WALL_Y + 34.0
			foe["hp"] = float(foe["hp"]) - 18.0 * delta
			foe["burn_show"] = float(foe["burn_show"]) + 18.0 * delta
		if next_y < STOP_Y:
			next_y = STOP_Y
			if foe["freeze"] <= 0.0 and foe["stun"] <= 0.0:
				foe["attack"] = float(foe["attack"]) - delta
				if foe["attack"] <= 0.0:
					foe["attack"] = 0.9
					player_damaged.emit(int(foe["touch"]))
					_flash_actor(foe["body"], Color("ffb0a8"))
		foe["y"] = next_y
		if foe["burn"] > 0.0:
			var dot := float(foe["burn_dps"]) * delta
			foe["hp"] = float(foe["hp"]) - dot
			foe["burn_show"] = float(foe["burn_show"]) + dot
		if float(foe["burn_show"]) >= 8.0:
			_popup(foe, float(foe["burn_show"]), Color("ffb15a"))
			foe["burn_show"] = 0.0
		if float(foe["hp"]) <= 0.0:
			_kill(foe)
		else:
			_place(foe)
			_sync_bars(foe)


func _decay_status(foe: Dictionary, delta: float) -> void:
	for key in ["burn", "freeze", "slow", "stun"]:
		if float(foe[key]) > 0.0:
			foe[key] = maxf(float(foe[key]) - delta, 0.0)


func _tick_summon(delta: float) -> void:
	if _summon_time <= 0.0:
		_summon.visible = false
		return
	_summon_time = maxf(_summon_time - delta, 0.0)
	_summon.visible = true
	_summon_cd -= delta
	if _summon_cd > 0.0:
		return
	var target := _front_foe()
	if target.is_empty():
		return
	_summon_cd = 0.55
	_launch(_summon.global_position + Vector2(28, 28), _foe_center(target), "vine", "boltlet", 18.0, int(target["id"]), false, 900.0)


func _tick_missiles(delta: float) -> void:
	var alive: Array = []
	for missile in _missiles:
		var node: Node2D = missile["node"]
		if not is_instance_valid(node):
			continue
		var target: Dictionary = _foe_by_id(int(missile["target"]))
		var dest: Vector2 = missile["fallback"]
		if not target.is_empty() and not target["dead"]:
			dest = _foe_center(target)
		else:
			var fallback := _front_foe()
			if not fallback.is_empty():
				missile["target"] = int(fallback["id"])
				dest = _foe_center(fallback)
		var delta_v := dest - node.global_position
		var step := float(missile["speed"]) * delta
		if delta_v.length() <= step + 14.0:
			if not bool(missile.get("cosmetic", false)):
				_impact(missile, _foe_by_id(int(missile["target"])))
			node.queue_free()
		else:
			node.global_position += delta_v.normalized() * step
			alive.append(missile)
	_missiles = alive


func _impact(missile: Dictionary, foe: Dictionary) -> void:
	var kind := str(missile["kind"])
	var damage := float(missile["damage"])
	var school := str(missile["school"])
	if kind == "boltlet":
		if not foe.is_empty() and not foe["dead"]:
			_hurt(foe, damage, true)
		return
	if foe.is_empty() or foe["dead"]:
		spell_hit.emit(school)
		return
	_hurt(foe, damage, true)
	if foe["dead"]:
		spell_hit.emit(school)
		if kind == "explosion":
			for other in _foes:
				if int(other["id"]) == int(foe["id"]) or other["dead"]:
					continue
				_hurt(other, damage * 0.65, true)
			_pulse_flash(Color("ff7a3c"))
		return
	match kind:
		"burn", "explosion":
			foe["burn"] = 3.2
			foe["burn_dps"] = 16.0
		"freeze", "wall":
			foe["freeze"] = 1.35 + freeze_bonus
		"entangle", "summon":
			foe["slow"] = 2.5
		"chain":
			var behind := _behind(foe)
			if not behind.is_empty():
				_hurt(behind, damage * 0.7, true)
		"stun":
			foe["stun"] = 0.95
			var behind2 := _behind(foe)
			if not behind2.is_empty():
				_hurt(behind2, damage * 0.75, true)
				if not behind2["dead"]:
					behind2["stun"] = 0.95
	if kind == "explosion":
		for other in _foes:
			if int(other["id"]) == int(foe["id"]) or other["dead"]:
				continue
			_hurt(other, damage * 0.65, true)
		_pulse_flash(Color("ff7a3c"))
	if kind == "wall":
		_wall_time = 3.4
		_wall.visible = true
	if kind == "summon":
		_summon_time = 5.0 + summon_bonus
		_summon_cd = 0.15
		_summon.visible = true
	spell_hit.emit(school)


func _hurt(foe: Dictionary, amount: float, popup: bool) -> void:
	if foe["dead"]:
		return
	var before := float(foe["hp"]) / float(foe["max_hp"])
	foe["hp"] = float(foe["hp"]) - amount
	if popup and not foe["dead"]:
		_popup(foe, amount, Color("fff4e0"))
	if str(foe["kind"]) == "boss" and not foe["split"] and before > 0.5 and float(foe["hp"]) <= float(foe["max_hp"]) * 0.5 and float(foe["hp"]) > 0.0:
		foe["split"] = true
		_schedule.append({"kind": "runner", "at": _clock + 0.45})
	if float(foe["hp"]) <= 0.0:
		_kill(foe)
	else:
		_flash_actor(foe["body"], Color("ffffff"))
		_sync_bars(foe)


func _kill(foe: Dictionary) -> void:
	if foe["dead"]:
		return
	foe["dead"] = true
	foe["hp"] = 0.0
	foe_killed.emit(int(foe["gold"]))
	var root: Node = foe["root"]
	if is_instance_valid(root):
		root.queue_free()


func _sweep() -> void:
	var alive: Array = []
	for foe in _foes:
		if not foe["dead"]:
			alive.append(foe)
	_foes = alive


func _launch(from_global: Vector2, dest: Vector2, school: String, kind: String, damage: float, target_id: int, empowered: bool, speed: float, cosmetic: bool = false) -> void:
	if fx_parent == null:
		return
	var holder := Node2D.new()
	var gem := Polygon2D.new()
	var radius := 16.0 if empowered else 11.0
	gem.polygon = PackedVector2Array([
		Vector2(0, -radius),
		Vector2(radius, 0),
		Vector2(0, radius),
		Vector2(-radius, 0),
	])
	gem.color = _school_color(school).lightened(0.2 if empowered else 0.0)
	holder.add_child(gem)
	fx_parent.add_child(holder)
	holder.global_position = from_global
	_missiles.append({
		"node": holder,
		"target": target_id,
		"fallback": dest,
		"school": school,
		"kind": kind,
		"damage": damage,
		"speed": speed,
		"cosmetic": cosmetic,
	})


func _popup(foe: Dictionary, amount: float, color: Color) -> void:
	if fx_parent == null or not is_instance_valid(foe["root"]):
		return
	var label := Label.new()
	label.text = str(int(round(amount)))
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_parent.add_child(label)
	label.global_position = _foe_center(foe) + Vector2(-10, -28)
	var tween := create_tween()
	tween.tween_property(label, "global_position", label.global_position + Vector2(0, -36), 0.45)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.45)
	tween.chain().tween_callback(label.queue_free)


func _front_foe() -> Dictionary:
	var best: Dictionary = {}
	var best_y := 99999.0
	for foe in _foes:
		if foe["dead"]:
			continue
		if float(foe["y"]) < best_y:
			best_y = float(foe["y"])
			best = foe
	return best


func _behind(foe: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_y := 99999.0
	for other in _foes:
		if int(other["id"]) == int(foe["id"]) or other["dead"]:
			continue
		var y := float(other["y"])
		if y > float(foe["y"]) and y < best_y:
			best_y = y
			best = other
	return best


func _foe_by_id(id: int) -> Dictionary:
	for foe in _foes:
		if int(foe["id"]) == id and not foe["dead"]:
			return foe
	return {}


func _foe_center(foe: Dictionary) -> Vector2:
	var root: Control = foe["root"]
	return root.global_position + Vector2(60, 70)


func _place(foe: Dictionary) -> void:
	var root: Control = foe["root"]
	if not is_instance_valid(root):
		return
	var bob := sin(_clock * 5.0 + float(foe["id"])) * 2.0
	root.position = Vector2(LANE_W * 0.5 + float(foe["x_off"]) - 60.0, float(foe["y"]) - 96.0 + bob)


func _sync_bars(foe: Dictionary) -> void:
	var fill: ColorRect = foe["fill"]
	if is_instance_valid(fill):
		fill.size.x = 92.0 * clampf(float(foe["hp"]) / float(foe["max_hp"]), 0.0, 1.0)
	var status: Label = foe["status"]
	if is_instance_valid(status):
		status.text = _status_text(foe)
	var body: Polygon2D = foe["body"]
	if is_instance_valid(body):
		var tint: Color = foe["base"]
		if foe["freeze"] > 0.0:
			tint = tint.lerp(Color("9fd7ff"), 0.65)
		elif foe["stun"] > 0.0:
			tint = tint.lerp(Color("ffe38a"), 0.55)
		elif foe["burn"] > 0.0:
			tint = tint.lerp(Color("ff8a3d"), 0.45)
		elif foe["slow"] > 0.0:
			tint = tint.lerp(Color("8dcea0"), 0.45)
		body.color = tint


func _status_text(foe: Dictionary) -> String:
	var parts := PackedStringArray()
	if foe["burn"] > 0.0:
		parts.append("燃烧")
	if foe["freeze"] > 0.0:
		parts.append("冻结")
	if foe["slow"] > 0.0:
		parts.append("缠绕")
	if foe["stun"] > 0.0:
		parts.append("眩晕")
	if _wall_time > 0.0 and float(foe["y"]) > WALL_Y and float(foe["y"]) < WALL_Y + 70.0:
		parts.append("冰墙")
	return " ".join(parts)


func _flash_actor(body: Polygon2D, color: Color) -> void:
	if not is_instance_valid(body):
		return
	body.modulate = color
	var tween := create_tween()
	tween.tween_property(body, "modulate", Color.WHITE, 0.18)


func _pulse_flash(color: Color) -> void:
	_flash.color = color
	_flash.modulate.a = 0.62
	var tween := create_tween()
	tween.tween_property(_flash, "modulate:a", 0.0, 0.42)


func _clear_dynamic() -> void:
	for foe in _foes:
		var root: Node = foe["root"]
		if is_instance_valid(root):
			root.queue_free()
	_foes.clear()
	for missile in _missiles:
		var node: Node = missile["node"]
		if is_instance_valid(node):
			node.queue_free()
	_missiles.clear()
	_schedule.clear()


func _build_static() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color("10151d")
	backdrop.size = Vector2(LANE_W, LANE_H)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var road := ColorRect.new()
	road.color = Color("1c2633")
	road.position = Vector2(LANE_W * 0.5 - 78.0, 8)
	road.size = Vector2(156, LANE_H - 16)
	road.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(road)
	var line := ColorRect.new()
	line.color = Color("e07a72")
	line.position = Vector2(LANE_W * 0.5 - 78.0, STOP_Y - 8.0)
	line.size = Vector2(156, 3)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)
	var spawn_label := Label.new()
	spawn_label.text = "敌人从下方出现，向上推进"
	spawn_label.position = Vector2(40, LANE_H - 36)
	spawn_label.size = Vector2(LANE_W - 80, 24)
	spawn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spawn_label.add_theme_font_size_override("font_size", 14)
	spawn_label.add_theme_color_override("font_color", Color("9aa3b5"))
	spawn_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(spawn_label)

	var player := Polygon2D.new()
	player.polygon = PackedVector2Array([
		Vector2(0, -26), Vector2(22, 0), Vector2(0, 26), Vector2(-22, 0),
	])
	player.color = Color("f0d7a2")
	player.position = Vector2(LANE_W * 0.5, 58)
	add_child(player)
	var track := ColorRect.new()
	track.color = Color("2a303c")
	track.position = Vector2(LANE_W * 0.5 - 75.0, 86)
	track.size = Vector2(150, 10)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(track)
	_player_fill = ColorRect.new()
	_player_fill.color = Color("7bc67e")
	_player_fill.position = track.position
	_player_fill.size = Vector2(150, 10)
	_player_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_player_fill)
	_player_label = Label.new()
	_player_label.position = Vector2(LANE_W * 0.5 - 80.0, 98)
	_player_label.size = Vector2(160, 22)
	_player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_label.add_theme_font_size_override("font_size", 14)
	_player_label.add_theme_color_override("font_color", Color("f4f1ea"))
	_player_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_label.text = "你"
	add_child(_player_label)

	_wall = ColorRect.new()
	_wall.color = Color(0.55, 0.82, 1.0, 0.55)
	_wall.position = Vector2(LANE_W * 0.5 - 90.0, WALL_Y)
	_wall.size = Vector2(180, 18)
	_wall.visible = false
	_wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wall)

	_summon = Control.new()
	_summon.position = Vector2(LANE_W * 0.5 + 110.0, 70)
	_summon.size = Vector2(70, 70)
	_summon.visible = false
	_summon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var summon_gem := Polygon2D.new()
	summon_gem.polygon = PackedVector2Array([
		Vector2(28, 4), Vector2(52, 28), Vector2(28, 52), Vector2(4, 28),
	])
	summon_gem.color = Color("5cbf6a")
	_summon.add_child(summon_gem)
	var summon_label := Label.new()
	summon_label.text = "藤灵"
	summon_label.position = Vector2(0, 50)
	summon_label.size = Vector2(70, 20)
	summon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summon_label.add_theme_font_size_override("font_size", 13)
	summon_label.add_theme_color_override("font_color", Color("d4f5d4"))
	summon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summon.add_child(summon_label)
	add_child(_summon)

	_flash = ColorRect.new()
	_flash.color = Color("ffffff")
	_flash.size = Vector2(LANE_W, LANE_H)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.modulate.a = 0.0
	add_child(_flash)


func _foe_color(kind: String) -> Color:
	match kind:
		"runner":
			return Color("3cb8a0")
		"elite":
			return Color("d4a017")
		"boss":
			return Color("7a5cbf")
		_:
			return Color("c46a4a")


func _foe_polygon(kind: String) -> PackedVector2Array:
	var s := 26.0
	if kind == "elite":
		s = 32.0
	elif kind == "boss":
		s = 40.0
	elif kind == "runner":
		s = 22.0
	return PackedVector2Array([
		Vector2(0, -s),
		Vector2(s * 0.86, -s * 0.2),
		Vector2(s * 0.55, s),
		Vector2(-s * 0.55, s),
		Vector2(-s * 0.86, -s * 0.2),
	])


func _school_color(school: String) -> Color:
	match school:
		"fire":
			return Rules.GEM_COLORS[0]
		"ice":
			return Rules.GEM_COLORS[1]
		"vine":
			return Rules.GEM_COLORS[2]
		"lightning":
			return Rules.GEM_COLORS[3]
		_:
			return Rules.GEM_COLORS[4]
