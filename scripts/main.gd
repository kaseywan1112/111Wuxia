extends Control

const Rules = preload("res://scripts/run_state.gd")
const Gear = preload("res://scripts/gear.gd")
const FieldView = preload("res://scripts/board_view.gd")

enum Mode { START, EQUIP, COMBAT, LEVEL, LOSE }

const INK := Color("0e1116")
const PAPER := Color("e7e4dc")
const MUTED := Color("9aa3b5")
const GOLD := Color("f0d7a2")
const DANGER := Color("e07a72")

var state: Rules
var gear: Gear
var mode := Mode.START
var ui_lock := false
var level_pending := 0
var drops_this_run := 0

var field: FieldView
var combat_root: Control
var start_screen: Control
var equip_screen: Control
var level_screen: Control
var lose_screen: Control

var kills_label: Label
var level_label: Label
var weapon_label: Label
var relic_label: Label
var action_label: Label
var level_box: HBoxContainer
var level_title: Label
var lose_detail: Label
var equip_body: VBoxContainer

var flash: ColorRect
var shake := 0.0
var flash_alpha := 0.0
var flash_color := Color.WHITE
var world: Control

var sfx: Array[AudioStreamPlayer] = []
var sfx_cursor := 0
var audio_ok := true


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = _build_theme()
	state = Rules.new()
	gear = Gear.new()
	gear.load_default()
	_build_background()
	_build_combat()
	_build_start()
	_build_equip()
	_build_level()
	_build_lose()
	_build_flash()
	_build_audio()
	field.struck_same.connect(_on_same)
	field.struck_basic.connect(_on_basic)
	field.killed.connect(_on_killed)
	field.crushed.connect(_on_crushed)
	_show_start()


func _process(delta: float) -> void:
	_tick_shake(delta)
	_tick_flash(delta)
	if mode != Mode.COMBAT:
		return
	_refresh_hud()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match mode:
		Mode.START, Mode.LOSE:
			if _is_accept(key.keycode):
				_start_run()
				get_viewport().set_input_as_handled()
			elif key.keycode == KEY_E:
				_show_equip()
				get_viewport().set_input_as_handled()
		Mode.EQUIP:
			if key.keycode == KEY_ESCAPE or key.keycode == KEY_E or _is_accept(key.keycode):
				_show_start()
				get_viewport().set_input_as_handled()
		Mode.LEVEL:
			if key.keycode == KEY_1 or key.keycode == KEY_KP_1:
				_pick_relic(0)
			elif key.keycode == KEY_2 or key.keycode == KEY_KP_2:
				_pick_relic(1)
			elif key.keycode == KEY_3 or key.keycode == KEY_KP_3:
				_pick_relic(2)


func _start_run() -> void:
	if ui_lock:
		return
	ui_lock = true
	drops_this_run = 0
	level_pending = 0
	state.begin_run(gear, _new_seed())
	mode = Mode.COMBAT
	_show_only(combat_root)
	field.begin(state)
	var kind := "挥砍" if state.attack_kind == "melee" else "射击"
	action_label.text = "%s正在自动%s。同色是重击，别的颜色只是基础伤害。" % [state.weapon_name, kind]
	_refresh_hud()
	get_viewport().gui_release_focus()
	ui_lock = false


func _on_same(color_index: int, victims: int, amount: float) -> void:
	if mode != Mode.COMBAT:
		return
	action_label.text = "同色 · %s · %d · 连锁 %d" % [
		Rules.COLOR_NAMES[color_index], int(round(amount)), victims,
	]
	_flash(Rules.GEM_COLORS[color_index], 0.18)
	_play_tone(420.0 + float(victims) * 24.0, 0.06, 0.28)
	_refresh_hud()


func _on_basic(amount: float) -> void:
	action_label.text = "基础伤害 %d" % int(round(amount))


func _on_killed() -> void:
	var ups := state.note_kills(1)
	if ups > 0:
		level_pending += ups
		field.accept_input = false
		call_deferred("_open_level_if_needed")
	_roll_loot()
	if mode == Mode.COMBAT:
		_refresh_hud()


func _roll_loot() -> void:
	var force := drops_this_run == 0 and state.kills >= 3
	var id := gear.try_drop(state.rng, force)
	if id == "":
		return
	gear.add_item(id)
	drops_this_run += 1
	gear.save()
	action_label.text = "掉落了 %s" % gear.item_name(id)
	_play_tone(640.0, 0.08, 0.24)


func _on_crushed() -> void:
	if mode != Mode.COMBAT:
		return
	field.stop()
	_show_lose()


func _open_level_if_needed() -> void:
	if level_pending <= 0 or mode != Mode.COMBAT or not field.running:
		return
	_open_level()


func _open_level() -> void:
	if level_pending <= 0 or mode != Mode.COMBAT:
		return
	level_pending -= 1
	mode = Mode.LEVEL
	field.accept_input = false
	state.roll_level()
	_rebuild_level()
	level_screen.visible = true
	get_viewport().gui_release_focus()


func _pick_relic(index: int) -> void:
	if ui_lock or mode != Mode.LEVEL:
		return
	if index < 0 or index >= state.level_stock.size():
		return
	ui_lock = true
	var id := str(state.level_stock[index])
	state.apply_relic(id)
	level_screen.visible = false
	mode = Mode.COMBAT
	_refresh_hud()
	ui_lock = false
	if level_pending > 0:
		_open_level()
		return
	field.accept_input = true


func _show_start() -> void:
	mode = Mode.START
	_refresh_start()
	_show_only(start_screen)


func _show_equip() -> void:
	mode = Mode.EQUIP
	_rebuild_equip()
	_show_only(equip_screen)


func _show_lose() -> void:
	mode = Mode.LOSE
	field.stop()
	lose_detail.text = "怪物走到了你身边。\n击杀  %d\n掉落  %d\n种子  %d" % [
		state.kills, drops_this_run, state.seed_value,
	]
	_show_only(lose_screen)


func _show_only(which: Control) -> void:
	for screen in [start_screen, equip_screen, combat_root, lose_screen]:
		if screen == null:
			continue
		screen.visible = screen == which
	if level_screen != null:
		level_screen.visible = false


func _refresh_hud() -> void:
	kills_label.text = "击杀  %d" % state.kills
	level_label.text = state.level_text()
	var kind := "近战" if state.attack_kind == "melee" else "远程"
	weapon_label.text = "%s  ·  %s  ·  %s" % [
		state.weapon_name, kind, Rules.COLOR_NAMES[state.attack_color],
	]
	relic_label.text = state.relic_line()


func _refresh_start() -> void:
	pass


func _flash(color: Color, amount: float) -> void:
	flash_color = color
	flash_alpha = amount
	shake = maxf(shake, 3.0)


func _tick_shake(delta: float) -> void:
	var kick := Vector2.ZERO
	if shake > 0.0:
		kick = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
		shake = maxf(shake - delta * 28.0, 0.0)
	if world == null:
		return
	world.offset_left = kick.x
	world.offset_right = kick.x
	world.offset_top = 96.0 + kick.y
	world.offset_bottom = kick.y


func _tick_flash(delta: float) -> void:
	if flash_alpha > 0.0:
		flash_alpha = maxf(flash_alpha - delta * 1.4, 0.0)
	if flash == null:
		return
	flash.color = flash_color
	flash.color.a = flash_alpha


func _build_background() -> void:
	var background := ColorRect.new()
	background.color = INK
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)


func _build_combat() -> void:
	combat_root = Control.new()
	_cover(combat_root)
	combat_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(combat_root)
	var hud := PanelContainer.new()
	hud.position = Vector2(16, 10)
	hud.size = Vector2(1248, 78)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hud_style := StyleBoxFlat.new()
	hud_style.bg_color = Color("161b24")
	hud_style.set_corner_radius_all(12)
	hud_style.content_margin_left = 14
	hud_style.content_margin_right = 14
	hud_style.content_margin_top = 8
	hud_style.content_margin_bottom = 8
	hud.add_theme_stylebox_override("panel", hud_style)
	combat_root.add_child(hud)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 2)
	hud.add_child(stack)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	stack.add_child(row)
	kills_label = _label("击杀  0", 16, PAPER)
	level_label = _label("等级  1", 16, PAPER)
	weapon_label = _label("朴刀", 16, GOLD)
	relic_label = _label("遗物  无", 16, MUTED)
	row.add_child(kills_label)
	row.add_child(level_label)
	row.add_child(weapon_label)
	row.add_child(relic_label)
	action_label = _label("", 16, GOLD, false)
	stack.add_child(action_label)
	world = Control.new()
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.set_anchors_preset(Control.PRESET_FULL_RECT)
	world.offset_top = 96
	combat_root.add_child(world)
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(holder)
	field = FieldView.new()
	holder.add_child(field)


func _build_start() -> void:
	start_screen = _full_center()
	var panel := _card(Color("161b24"))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(640, 0)
	panel.add_child(box)
	var title := _label("消消乐 Rogue", 40, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := _label("怪物从上方走下来，你在底下自动攻击", 18, MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var rules := _label(
		"颜色要对上。打中武器的颜色是重击，屏幕上别的同色怪物也会吃到连锁。别的颜色只造成基础伤害。没有泡泡，子弹和挥砍都不会粘在怪物身上。\n\n局内击杀一段之后升级，从 3 件遗物里选 1 件，只留到这局结束：猛击、疾射、连锁、双发、长刃。\n\n局外是装备。怪物会掉武器、护甲和饰品。同一套装两件一起穿上才有套装效果，装备会留到下一局。",
		16,
		PAPER,
		true
	)
	rules.custom_minimum_size = Vector2(600, 0)
	box.add_child(rules)
	var button := _button("开始游戏")
	button.pressed.connect(_start_run)
	box.add_child(button)
	var gear_button := _button("整理装备")
	gear_button.pressed.connect(_show_equip)
	box.add_child(gear_button)
	var hint := _label("回车开始，E 打开装备", 14, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	start_screen.add_child(panel)
	add_child(start_screen)


func _build_equip() -> void:
	equip_screen = _full_center()
	var panel := _card(Color("161b24"))
	equip_body = VBoxContainer.new()
	equip_body.add_theme_constant_override("separation", 8)
	equip_body.custom_minimum_size = Vector2(680, 0)
	panel.add_child(equip_body)
	equip_screen.add_child(panel)
	add_child(equip_screen)


func _rebuild_equip() -> void:
	for child in equip_body.get_children():
		child.queue_free()
	var title := _label("装备", 32, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	equip_body.add_child(title)
	var sub := _label("点一件穿上。同一套装凑齐两件就生效，下一局还在。", 15, MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	equip_body.add_child(sub)
	for slot in Gear.SLOT_ORDER:
		var worn := gear.equipped_id(slot)
		var worn_name := "空" if worn == "" else gear.item_name(worn)
		equip_body.add_child(_label("%s    %s" % [Gear.SLOT_NAMES[slot], worn_name], 18, GOLD))
	equip_body.add_child(_label("背包", 16, MUTED))
	for id in gear.owned:
		var info: Dictionary = Gear.ITEMS[id]
		var set_name := "无套装"
		if str(info["set"]) != "" and Gear.SETS.has(str(info["set"])):
			set_name = str(Gear.SETS[str(info["set"])]["name"])
		var button := _button("%s  ·  %s  ·  %s" % [str(info["name"]), Gear.SLOT_NAMES[str(info["slot"])], set_name])
		button.pressed.connect(_equip_item.bind(id))
		equip_body.add_child(button)
	for set_id in Gear.SET_ORDER:
		var count := gear.set_count(set_id)
		var bonus := str(Gear.SETS[set_id]["bonus"])
		var name := str(Gear.SETS[set_id]["name"])
		var color := GOLD if count >= 2 else MUTED
		var mark := "已生效" if count >= 2 else "未生效"
		equip_body.add_child(_label("%s  %d/2  %s  ·  %s" % [name, count, bonus, mark], 15, color))
	var back := _button("返回")
	back.pressed.connect(_show_start)
	equip_body.add_child(back)


func _equip_item(id: String) -> void:
	gear.equip(id)
	gear.save()
	_rebuild_equip()


func _build_level() -> void:
	level_screen = Control.new()
	_cover(level_screen)
	level_screen.visible = false
	level_screen.z_index = 40
	level_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	level_screen.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	level_screen.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	level_title = _label("选择遗物", 32, GOLD)
	level_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(level_title)
	var hint := _label("选一件，留到这局结束。按 1 / 2 / 3", 15, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	level_box = HBoxContainer.new()
	level_box.add_theme_constant_override("separation", 16)
	box.add_child(level_box)
	add_child(level_screen)


func _rebuild_level() -> void:
	level_title.text = "升到 %d 级" % (state.level - level_pending)
	for child in level_box.get_children():
		child.queue_free()
	var tints: Array[Color] = [Color("243044"), Color("24362f"), Color("3a3224")]
	for i in state.level_stock.size():
		var id := str(state.level_stock[i])
		var info: Dictionary = Rules.RELICS[id]
		var panel := _card(tints[i % tints.size()])
		panel.custom_minimum_size = Vector2(220, 180)
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 8)
		panel.add_child(inner)
		var name := _label(str(info["name"]), 22, GOLD)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(name)
		var desc := _label(str(info["desc"]), 15, PAPER, true)
		desc.custom_minimum_size = Vector2(190, 70)
		inner.add_child(desc)
		var button := _button("拿下")
		button.pressed.connect(_pick_relic.bind(i))
		inner.add_child(button)
		level_box.add_child(panel)


func _build_lose() -> void:
	lose_screen = _full_center()
	var panel := _card(Color("161b24"))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(460, 0)
	panel.add_child(box)
	var title := _label("你倒下了", 40, DANGER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	lose_detail = _label("", 18, PAPER)
	lose_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lose_detail)
	var again := _button("再来一局")
	again.pressed.connect(_start_run)
	box.add_child(again)
	var gear_button := _button("整理装备")
	gear_button.pressed.connect(_show_equip)
	box.add_child(gear_button)
	var hint := _label("回车再来，E 整理装备", 14, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	lose_screen.add_child(panel)
	add_child(lose_screen)


func _build_flash() -> void:
	flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.z_index = 30
	add_child(flash)


func _build_audio() -> void:
	for _i in 4:
		var player := AudioStreamPlayer.new()
		add_child(player)
		sfx.append(player)


func _play_tone(freq: float, duration: float, volume: float) -> void:
	if not audio_ok or sfx.is_empty():
		return
	var stream := _beep(freq, duration, volume)
	var player := sfx[sfx_cursor % sfx.size()]
	sfx_cursor += 1
	player.stream = stream
	player.play()


func _beep(freq: float, duration: float, volume: float) -> AudioStreamWAV:
	var rate := 22050
	var count := int(float(rate) * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / float(rate)
		var env := 1.0 - float(i) / float(count)
		var sample := int(sin(t * freq * TAU) * env * volume * 32000.0)
		data.encode_s16(i * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	return stream


func _full_center() -> CenterContainer:
	var center := CenterContainer.new()
	_cover(center)
	return center


func _cover(node: Control) -> void:
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	node.offset_left = 0
	node.offset_top = 0
	node.offset_right = 0
	node.offset_bottom = 0
	node.grow_horizontal = Control.GROW_DIRECTION_BOTH
	node.grow_vertical = Control.GROW_DIRECTION_BOTH


func _card(color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(16)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _label(text: String, size: int, color: Color, wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 16)
	button.custom_minimum_size = Vector2(0, 42)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("2c384c")
	normal.set_corner_radius_all(10)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("3d4e68")
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("1c2636")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_color_override("font_color", PAPER)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", PAPER)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	return button


func _build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = _make_font()
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", PAPER)
	theme.set_color("font_color", "Button", PAPER)
	return theme


func _make_font() -> Font:
	var system := SystemFont.new()
	system.font_names = PackedStringArray([
		"WenQuanYi Micro Hei",
		"Noto Sans CJK SC",
		"Noto Sans SC",
		"Source Han Sans SC",
		"Droid Sans Fallback",
		"Microsoft YaHei",
		"PingFang SC",
		"Heiti SC",
		"SimHei",
		"Noto Sans",
		"sans-serif",
	])
	if system.has_char("消".unicode_at(0)):
		return system
	var candidates := [
		"/usr/share/fonts/truetype/wqy/wqy-microhei.ttc",
		"/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf",
	]
	for path in candidates:
		if FileAccess.file_exists(path):
			var file := FontFile.new()
			if file.load_dynamic_font(path) == OK:
				return file
	return system


func _new_seed() -> int:
	var roller := RandomNumberGenerator.new()
	roller.randomize()
	var value := int(roller.randi() & 0x7fffffff)
	return value if value != 0 else 1


func _is_accept(code: Key) -> bool:
	return code == KEY_ENTER or code == KEY_KP_ENTER or code == KEY_SPACE
