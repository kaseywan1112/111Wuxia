extends Control

const Rules = preload("res://scripts/run_state.gd")
const BoardView = preload("res://scripts/board_view.gd")

enum Mode { START, COMBAT, LEVEL, LOSE }

const INK := Color("0e1116")
const PAPER := Color("e7e4dc")
const MUTED := Color("9aa3b5")
const GOLD := Color("f0d7a2")
const DANGER := Color("e07a72")

var state: Rules
var mode := Mode.START
var ui_lock := false
var level_pending := 0

var field
var combat_root: Control
var start_screen: Control
var level_screen: Control
var lose_screen: Control

var wave_label: Label
var pops_label: Label
var level_label: Label
var weapon_label: Label
var next_label: Label
var action_label: Label
var level_box: HBoxContainer
var level_title: Label
var lose_detail: Label

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
	_build_background()
	_build_combat()
	_build_start()
	_build_level()
	_build_lose()
	_build_flash()
	_build_audio()
	field.chained.connect(_on_chained)
	field.basics.connect(_on_basics)
	field.cleared.connect(_on_cleared)
	field.crushed.connect(_on_crushed)
	field.waved.connect(_on_waved)
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
		Mode.LEVEL:
			if key.keycode == KEY_1 or key.keycode == KEY_KP_1:
				_pick_level(0)
			elif key.keycode == KEY_2 or key.keycode == KEY_KP_2:
				_pick_level(1)
			elif key.keycode == KEY_3 or key.keycode == KEY_KP_3:
				_pick_level(2)


func _start_run() -> void:
	if ui_lock:
		return
	ui_lock = true
	state.start_run(_new_seed())
	level_pending = 0
	mode = Mode.COMBAT
	_show_only(combat_root)
	field.begin(state)
	action_label.text = "飞刀会自己发射。移动鼠标，或按左右键瞄准。"
	_refresh_hud()
	get_viewport().gui_release_focus()
	ui_lock = false


func _on_chained(color_index: int, length: int, positions: Array) -> void:
	if mode != Mode.COMBAT:
		return
	var big: bool = state.is_super(length)
	var title := Rules.SCHOOL_NAMES[color_index]
	if color_index == 4:
		var cut := state.white_cooldown_cut(length)
		field.cut_cooldowns(cut)
		action_label.text = "白宝石 · %d 连 · %s%s" % [
			length, state.apply_white(length), "  ·  大招" if big else "",
		]
		_flash(Rules.GEM_COLORS[4], 0.22 if big else 0.12)
		_play_tone(620.0, 0.08, 0.28)
		field.refill_if_empty()
		_refresh_hud()
		return
	var damage := state.chain_damage(length)
	field.hurt_color(color_index, damage)
	_apply_school(color_index, big, positions)
	action_label.text = "%s · %d 连 · 全体 %d%s" % [
		title, length, int(round(damage)), "  ·  大招" if big else "",
	]
	_flash(Rules.GEM_COLORS[color_index], 0.28 if big else 0.14)
	_play_tone(420.0 + float(length) * 28.0, 0.07, 0.3)
	field.refill_if_empty()
	_refresh_hud()


func _apply_school(color_index: int, big: bool, positions: Array) -> void:
	match color_index:
		0:
			var radius := 84.0 * (1.0 + state.fire_bonus)
			var extra := 24.0 * state.spell_power * (1.0 + state.fire_bonus)
			if big:
				radius *= 1.35
				extra *= 1.6
			field.burst_rings(positions, minf(radius, 130.0))
			field.hurt_near(positions, radius, extra)
		1:
			var hold := 3.6 if big else 2.2 as float
			field.freeze_for(hold + state.freeze_bonus)
		2:
			var hops := 2 if big else 1
			var info: Dictionary = field.neighbor_pairs(positions, hops)
			var vine := 20.0 * state.spell_power + state.vine_bonus
			if big:
				vine *= 1.7
			field.vine_marks(info["pairs"])
			field.hurt_ids(info["ids"], vine)
		3:
			var jumps := (3 if big else 1) + int(state.lightning_jumps)
			var ids: Array = field.nearest_ids(positions, jumps, [])
			var bolt := 28.0 * state.spell_power
			if big:
				bolt *= 1.5
			field.hurt_ids(ids, bolt)


func _on_basics(_color_index: int, amount: float, _at: Vector2) -> void:
	action_label.text = "贴住了 · 基础伤害 %d" % int(round(amount))


func _on_cleared(count: int) -> void:
	var ups := state.note_pops(count)
	if ups > 0:
		level_pending += ups
		call_deferred("_open_level_if_needed")
	if mode == Mode.COMBAT:
		_refresh_hud()


func _on_crushed() -> void:
	if mode != Mode.COMBAT:
		return
	field.stop()
	_show_lose()


func _on_waved(wave_number: int) -> void:
	action_label.text = "这一团清掉了 · 第 %d 波" % wave_number
	_refresh_hud()


func _open_level_if_needed() -> void:
	if level_pending <= 0 or mode != Mode.COMBAT or field.dead:
		return
	_open_level()


func _open_level() -> void:
	if level_pending <= 0 or mode != Mode.COMBAT or field.dead:
		return
	level_pending -= 1
	mode = Mode.LEVEL
	field.accept_input = false
	state.roll_level()
	_rebuild_level()
	level_screen.visible = true
	get_viewport().gui_release_focus()


func _pick_level(index: int) -> void:
	if ui_lock or mode != Mode.LEVEL:
		return
	if index < 0 or index >= state.level_stock.size():
		return
	ui_lock = true
	var id := str(state.level_stock[index])
	state.apply_level(id)
	if id == "book":
		field.arm_book()
	level_screen.visible = false
	mode = Mode.COMBAT
	_refresh_hud()
	ui_lock = false
	if level_pending > 0 and not field.dead:
		_open_level()
		return
	field.accept_input = true


func _show_start() -> void:
	mode = Mode.START
	_show_only(start_screen)


func _show_lose() -> void:
	mode = Mode.LOSE
	field.stop()
	lose_detail.text = "气泡压到了你。\n第 %d 波\n消除  %d\n种子  %d" % [
		state.wave, state.pops, state.seed_value,
	]
	_show_only(lose_screen)


func _show_only(which: Control) -> void:
	for screen in [start_screen, combat_root, lose_screen]:
		screen.visible = screen == which
	if level_screen != null:
		level_screen.visible = false


func _refresh_hud() -> void:
	wave_label.text = "第 %d 波" % state.wave
	pops_label.text = "消除  %d" % state.pops
	level_label.text = state.level_text()
	var weapons := "飞刀"
	if state.has_book:
		weapons += "  ·  法术书"
	weapon_label.text = weapons
	next_label.text = "下一发  %s" % Rules.COLOR_NAMES[field.next_color()]


func _flash(color: Color, amount: float) -> void:
	flash_color = color
	flash_alpha = amount
	shake = maxf(shake, 4.0 if amount > 0.2 else 2.0)


func _tick_shake(delta: float) -> void:
	var kick := Vector2.ZERO
	if shake > 0.0:
		kick = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
		shake = maxf(shake - delta * 28.0, 0.0)
	world.offset_left = kick.x
	world.offset_right = kick.x
	world.offset_top = 96.0 + kick.y
	world.offset_bottom = kick.y


func _tick_flash(delta: float) -> void:
	if flash_alpha > 0.0:
		flash_alpha = maxf(flash_alpha - delta * 1.4, 0.0)
	flash.color = flash_color
	flash.modulate.a = flash_alpha


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
	wave_label = _label("第 1 波", 16, GOLD)
	pops_label = _label("消除  0", 16, PAPER)
	level_label = _label("等级  1", 16, PAPER)
	weapon_label = _label("飞刀", 16, GOLD)
	next_label = _label("下一发  红", 16, PAPER)
	row.add_child(wave_label)
	row.add_child(pops_label)
	row.add_child(level_label)
	row.add_child(weapon_label)
	row.add_child(next_label)
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
	field = BoardView.new()
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
	var sub := _label("顶上是一团彩色怪物，你在底下瞄准", 18, MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var rules := _label(
		"怪物像泡泡挂在天花板上，会慢慢往下压。你站在底部，移动鼠标或按左右键瞄准，武器会按时间自己往上射。\n\n飞刀每 2 秒连射三发：红、红、紫。打中不同颜色只会造成一点基础伤害，子弹会粘在上面。同色连上 3 颗就会炸掉那一团，并且这一色的每只怪物都吃到连锁伤害，再附加流派效果：红是火焰爆发，蓝是冰冻，绿是藤蔓，紫是闪电，白是奖励。6 颗及以上是大招。\n\n消除一段之后会升级，从 3 项强化里选 1 个，只留到这局结束。法术书也在这些选择里：每 5 秒连射蓝、蓝、蓝、白、白、紫、紫。气泡压到你身上，这局就结束。",
		16,
		PAPER,
		true
	)
	rules.custom_minimum_size = Vector2(600, 0)
	box.add_child(rules)
	var button := _button("开始游戏")
	button.pressed.connect(_start_run)
	box.add_child(button)
	var hint := _label("回车或空格也可以开始", 14, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	start_screen.add_child(panel)
	add_child(start_screen)


func _build_level() -> void:
	level_screen = Control.new()
	_cover(level_screen)
	level_screen.visible = false
	level_screen.z_index = 40
	level_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.34)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_cover(dim)
	level_screen.add_child(dim)
	var center := CenterContainer.new()
	_cover(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_screen.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	level_title = _label("升级", 36, GOLD)
	level_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(level_title)
	var sub := _label("选一个强化，留到这局结束", 16, MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	level_box = HBoxContainer.new()
	level_box.add_theme_constant_override("separation", 16)
	level_box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(level_box)
	var hint := _label("按 1 / 2 / 3 选择", 14, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	add_child(level_screen)


func _rebuild_level() -> void:
	level_title.text = "升到 %d 级" % (state.level - level_pending)
	for child in level_box.get_children():
		child.queue_free()
	var tints: Array[Color] = [Color("243044"), Color("24362f"), Color("3a3224")]
	for i in state.level_stock.size():
		var id := str(state.level_stock[i])
		var info: Dictionary = Rules.LEVEL_UPS[id]
		var panel := _card(tints[i % tints.size()])
		panel.custom_minimum_size = Vector2(250, 230)
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 8)
		panel.add_child(inner)
		var name := _label(str(info["name"]), 22, GOLD)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(name)
		var desc := _label(str(info["desc"]), 15, PAPER, true)
		desc.custom_minimum_size = Vector2(210, 84)
		inner.add_child(desc)
		var button := _button("拿下")
		button.pressed.connect(_pick_level.bind(i))
		inner.add_child(button)
		level_box.add_child(panel)


func _build_lose() -> void:
	lose_screen = _full_center()
	var panel := _card(Color("161b24"))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(460, 0)
	panel.add_child(box)
	var title := _label("气泡压到了你", 40, DANGER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	lose_detail = _label("", 18, PAPER, true)
	lose_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lose_detail.custom_minimum_size = Vector2(420, 0)
	box.add_child(lose_detail)
	var button := _button("再来一局")
	button.pressed.connect(_start_run)
	box.add_child(button)
	lose_screen.add_child(panel)
	add_child(lose_screen)


func _build_flash() -> void:
	flash = ColorRect.new()
	_cover(flash)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.color = Color.WHITE
	flash.modulate.a = 0.0
	add_child(flash)


func _build_audio() -> void:
	for _i in 6:
		var player := AudioStreamPlayer.new()
		player.volume_db = -6.0
		add_child(player)
		sfx.append(player)


func _play_tone(freq: float, duration: float, volume: float) -> void:
	if not audio_ok or sfx.is_empty():
		return
	var stream := _beep(freq, duration, volume)
	if stream == null:
		audio_ok = false
		return
	var player := sfx[sfx_cursor % sfx.size()]
	sfx_cursor += 1
	player.stream = stream
	player.play()


func _beep(freq: float, duration: float, volume: float) -> AudioStreamWAV:
	var rate := 22050
	var count := int(float(rate) * duration)
	if count < 1:
		return null
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / float(rate)
		var env := 1.0 - float(i) / float(count)
		var sample := int(sin(t * freq * TAU) * env * volume * 32000.0)
		data[i * 2] = sample & 255
		data[i * 2 + 1] = (sample >> 8) & 255
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
	button.custom_minimum_size = Vector2(0, 44)
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
