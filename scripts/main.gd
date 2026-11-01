extends Control

const Rules = preload("res://scripts/run_state.gd")
const Field = preload("res://scripts/board_view.gd")

const START := "start"
const COMBAT := "combat"
const REST := "rest"
const RESULT := "result"
const PICK := "pick"

var state: Rules = Rules.new()
var mode: String = START
var result_kind: String = ""
var result_lines: PackedStringArray = PackedStringArray()
var caught_note: String = ""
var field: Field
var title_label: Label
var body_label: Label
var hud_label: Label
var panel: VBoxContainer
var bag_label: Label
var font: Font
var voice: AudioStreamPlayer


func _ready() -> void:
	_apply_font(_load_cjk_font())
	state.load_default()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("14181f")
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(column)
	title_label = _label("", 28)
	column.add_child(title_label)
	hud_label = _label("", 16)
	column.add_child(hud_label)
	body_label = _label("", 18)
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(body_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	field = Field.new()
	field.died.connect(_on_died)
	field.caught_ball.connect(_on_caught)
	field.looted.connect(_on_looted)
	field.needs_pick.connect(_on_pick)
	field.lane_event.connect(_on_lane)
	row.add_child(field)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(360, 0)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 8)
	row.add_child(side)
	bag_label = _label("", 16)
	bag_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(bag_label)
	panel = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 8)
	side.add_child(panel)
	voice = AudioStreamPlayer.new()
	add_child(voice)
	_show_start()


func _process(_delta: float) -> void:
	if state != null and (mode == COMBAT or mode == PICK or mode == REST):
		bag_label.text = _bag_text()
	if mode == COMBAT and state != null:
		var buff := ""
		if field._buff > 0.0:
			buff = "  ·  接住加成"
		var when := state.event_name()
		var soon := ""
		if state.beat == 2:
			soon = "首领在场上"
		else:
			soon = "距%s %d 秒" % [when, int(ceil(state.seconds_left()))]
		hud_label.text = "区域 %d  ·  %s  ·  生命 %d  ·  %s%s" % [
			state.area,
			state.weapon_name(),
			int(ceil(field._hp)),
			soon,
			buff,
		]
		bag_label.text = _bag_text()
		if state.run_damage > 0 or state.run_bounce > 0 or state.run_catch > 0 or state.run_rate > 0:
			hud_label.text += "  ·  局内 伤+%d 弹+%d 接+%d 速+%d" % [state.run_damage, state.run_bounce, state.run_catch, state.run_rate]
		if caught_note != "":
			hud_label.text += "  ·  " + caught_note


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if mode == START:
		if key.keycode == KEY_5:
			_upgrade_camp()
		elif key.keycode == KEY_6:
			_socket_camp()
		elif key.keycode == KEY_7:
			_talent_camp()
		elif key.keycode == KEY_8:
			_salvage_camp()
		elif key.keycode == KEY_ENTER or key.keycode == KEY_SPACE:
			_start_run()
		get_viewport().set_input_as_handled()
	elif mode == PICK:
		if key.keycode == KEY_1:
			_choose_index(0)
		elif key.keycode == KEY_2:
			_choose_index(1)
		elif key.keycode == KEY_3:
			_choose_index(2)
		get_viewport().set_input_as_handled()
	elif mode == REST:
		if key.keycode == KEY_1:
			_secure()
		elif key.keycode == KEY_2:
			_take("return")
		elif key.keycode == KEY_3:
			_take("hammer")
		elif key.keycode == KEY_4:
			_take("chain")
		elif key.keycode == KEY_E:
			_extract()
		elif key.keycode == KEY_ENTER:
			_continue_deeper()
		get_viewport().set_input_as_handled()
	elif mode == RESULT and key.keycode == KEY_ENTER:
		_show_start()
		get_viewport().set_input_as_handled()


func _show_start() -> void:
	mode = START
	caught_note = ""
	field.visible = false
	field.stop()
	panel.visible = true
	hud_label.text = ""
	title_label.text = "弹球搜刮"
	bag_label.text = _stash_line()
	body_label.text = "窄道一直往上卷，不会清场。开头怪很少，后面一直从顶上补。漏过你身边会扣血，扣光这一局就结束。经验球要走过去捡，装备直接进右边的背包。\n到点会休整，也能抽出。首领也是到点才来，打完窄道继续。保全背包仍然只能放一件。\n%s\n5 升级第一件   6 镶赤珠   7 点下一个天赋   8 拆解第一件" % _stash_line()
	_clear_panel()
	_button("5  升级第一件", _upgrade_camp)
	_button("6  给第一件镶赤珠", _socket_camp)
	_button("7  点下一个天赋", _talent_camp)
	_button("8  拆解第一件", _salvage_camp)
	_button("开始潜入", _start_run)


func _start_run() -> void:
	state.begin_run(randi())
	mode = COMBAT
	caught_note = ""
	panel.visible = false
	field.visible = true
	title_label.text = "弹球搜刮"
	body_label.text = "左边是窄道。右边是背包。漏过扣血，经验要捡，装备直接进包。"
	field.begin(state)
	_tone(520.0, 0.05)


func _on_lane(kind: String) -> void:
	if kind == "boss":
		body_label.text = "首领从上方来了。打掉它就能休整，窄道不会清掉。"
		return
	if mode != COMBAT and mode != PICK:
		return
	_show_rest()
	if kind == "boss_down":
		body_label.text = "首领倒了。可以抽出，也可以继续这条窄道。\n" + body_label.text


func _on_died() -> void:
	if mode != COMBAT:
		return
	var outcome: Dictionary = state.fail_run()
	state.save()
	var lost_names := _names(outcome["lost"])
	if lost_names == "":
		lost_names = "没有装备"
	var kept := "没有"
	if str(outcome["kept"]) != "":
		kept = state.gear_name(str(outcome["kept"]))
	result_kind = "lose"
	result_lines = PackedStringArray([
		"你倒下了。没保全、没抽出的都留在里面。",
		"失去装备：%s" % lost_names,
		"失去金币：%d" % int(outcome["lost_gold"]),
		"保全带回：%s" % kept,
		"营地里已抽出的还在。",
	])
	_show_result()
	_tone(140.0, 0.18)


func _on_caught() -> void:
	caught_note = "接住了，金币 +%d，伤害提升" % state.catch_gold()
	_tone(740.0, 0.06)


func _on_looted(what: String) -> void:
	if what == "gear":
		_tone(440.0, 0.05)


func _on_pick() -> void:
	if mode != COMBAT:
		return
	mode = PICK
	panel.visible = true
	title_label.text = "击杀之后"
	body_label.text = "选一个。只在这一局里有效，倒下就丢掉。"
	_clear_panel()
	for i in field.pending_picks.size():
		var pick_id := str(field.pending_picks[i])
		_button("%d  %s" % [i + 1, state.pick_name(pick_id)], _choose.bind(pick_id))


func _choose_index(index: int) -> void:
	if index < 0 or index >= field.pending_picks.size():
		return
	_choose(str(field.pending_picks[index]))


func _choose(id: String) -> void:
	if mode != PICK:
		return
	state.apply_pick(id)
	field.resume_after_pick()
	mode = COMBAT
	panel.visible = false
	title_label.text = "弹球搜刮"
	body_label.text = "选了%s。这一局有效。" % state.pick_name(id)


func _show_rest() -> void:
	mode = REST
	field.visible = true
	panel.visible = true
	hud_label.text = "区域 %d" % state.area
	bag_label.text = _bag_text()
	title_label.text = "休整"
	var carried := _names(state.carried)
	if carried == "":
		carried = "空"
	var bag := "空"
	if state.backpack != "":
		bag = state.gear_name(state.backpack)
	body_label.text = "可以抽出，离开时带走身上的金币和装备。保全背包里的那一件，就算倒下也会留下。\n身上：%s\n保全背包：%s\n本局金币：%d\n当前武器：%s" % [
		carried, bag, state.run_gold, state.weapon_name(),
	]
	_clear_panel()
	_button("1  把身上第一件放进背包", _secure)
	_button("2  拿起回手", func() -> void: _take("return"))
	_button("3  拿起重锤", func() -> void: _take("hammer"))
	_button("4  换回连弹", func() -> void: _take("chain"))
	_button("E  抽出", _extract)
	_button("回车  继续深入", _continue_deeper)


func _secure() -> void:
	var id := state.secure_first()
	if id == "":
		body_label.text = "背包已满，或身上没有可放的东西。\n" + body_label.text
		return
	_show_rest()
	body_label.text = "已放进保全背包：%s\n%s" % [state.gear_name(id), body_label.text]
	_tone(620.0, 0.05)


func _take(id: String) -> void:
	state.take_weapon(id)
	state.save()
	_show_rest()
	body_label.text = "现在用的是%s。\n%s" % [state.weapon_name(), body_label.text]


func _extract() -> void:
	var outcome: Dictionary = state.extract()
	state.save()
	var names := _names(outcome["items"])
	if names == "":
		names = "没有装备"
	result_kind = "extract"
	result_lines = PackedStringArray([
		"你抽出来了。这些留下来了。",
		"带回装备：%s" % names,
		"带回金币：%d" % int(outcome["gold"]),
		"营地里现在有金币 %d。" % state.stash_gold,
	])
	_show_result()
	_tone(660.0, 0.08)


func _continue_deeper() -> void:
	mode = COMBAT
	panel.visible = false
	field.visible = true
	title_label.text = "弹球搜刮"
	body_label.text = "窄道继续。怪还会从顶上出来。"
	field.resume_lane()


func _show_result() -> void:
	mode = RESULT
	field.visible = false
	field.stop()
	panel.visible = true
	hud_label.text = ""
	if result_kind == "extract":
		title_label.text = "抽出"
	else:
		title_label.text = "没能带出来"
	body_label.text = "\n".join(result_lines)
	_clear_panel()
	_button("回到营地", _show_start)


func _upgrade_camp() -> void:
	var id := state.upgrade_first()
	state.save()
	_show_start()
	if id == "":
		body_label.text = "没能升级。要有抽出的装备，并且抽出的金币够。\n" + body_label.text
	else:
		body_label.text = "升级了%s。花的是抽出的金币。\n" % state.gear_name(id) + body_label.text


func _socket_camp() -> void:
	var id := state.socket_first("red")
	state.save()
	_show_start()
	if id == "":
		body_label.text = "没能镶嵌。一件装备只能镶一颗珠，而且要花抽出的金币。\n" + body_label.text
	else:
		body_label.text = "给%s镶了赤珠。\n" % state.gear_name(id) + body_label.text


func _talent_camp() -> void:
	var id := state.buy_next_talent()
	state.save()
	_show_start()
	if id == "":
		body_label.text = "没有能点的天赋，或抽出的金币不够。\n" + body_label.text
	else:
		body_label.text = "点了%s。\n" % state.talent_name(id) + body_label.text


func _salvage_camp() -> void:
	var gained := state.salvage_first()
	state.save()
	_show_start()
	if gained == 0:
		body_label.text = "没有可拆的抽出装备。\n" + body_label.text
	else:
		body_label.text = "拆了一件，得到 %d 抽出金币。\n" % gained + body_label.text


func _bag_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("背包")
	if state.carried.is_empty():
		lines.append("还没有装备")
	else:
		for id in state.carried:
			lines.append(state.gear_name(str(id)))
	var secure := "空"
	if state.backpack != "":
		secure = state.gear_name(state.backpack)
	lines.append("保全：%s" % secure)
	lines.append("经验 %d/3" % state.run_xp)
	lines.append("本局金币 %d" % state.run_gold)
	lines.append("漏过会扣血。装备直接进包。经验要走过去捡。")
	return "\n".join(lines)


func _stash_line() -> String:
	if state.stash.is_empty() and state.stash_gold == 0 and state.talents.is_empty():
		return "还没有抽出的东西"
	var parts: PackedStringArray = PackedStringArray()
	parts.append("已抽出金币 %d" % state.stash_gold)
	for i in state.stash.size():
		var bit := state.gear_name(str(state.stash[i]))
		if i < state.stash_level.size() and state.stash_level[i] > 0:
			bit += "+%d" % state.stash_level[i]
		if i < state.stash_gem.size() and state.stash_gem[i] != "":
			bit += "·珠"
		parts.append(bit)
	if not state.talents.is_empty():
		var names: PackedStringArray = PackedStringArray()
		for id in state.talents:
			names.append(state.talent_name(str(id)))
		parts.append("天赋 " + "、".join(names))
	return "  ".join(parts)


func _names(ids) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for id in ids:
		parts.append(state.gear_name(str(id)))
	return "、".join(parts)


func _clear_panel() -> void:
	for child in panel.get_children():
		panel.remove_child(child)
		child.free()


func _button(text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(360, 42)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	panel.add_child(button)


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("f3efe6"))
	return label


func _load_cjk_font() -> Font:
	var path := "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
	if not FileAccess.file_exists(path):
		path = "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc"
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			var face := FontFile.new()
			face.data = file.get_buffer(file.get_length())
			if face.get_font_name() != "":
				return face
	return ThemeDB.fallback_font


func _apply_font(loaded: Font) -> void:
	font = loaded
	var theme := Theme.new()
	theme.default_font = font
	theme.set_font_size("font_size", "Label", 18)
	theme.set_font_size("font_size", "Button", 18)
	theme.set_color("font_color", "Label", Color("f3efe6"))
	theme.set_color("font_color", "Button", Color("f3efe6"))
	var box := StyleBoxFlat.new()
	box.bg_color = Color("2a3342")
	box.border_color = Color("f0d7a2")
	box.set_border_width_all(1)
	box.set_content_margin_all(8)
	theme.set_stylebox("normal", "Button", box)
	theme.set_stylebox("hover", "Button", box)
	theme.set_stylebox("pressed", "Button", box)
	set_theme(theme)


func _tone(freq: float, seconds: float) -> void:
	var rate := 22050
	var count := int(float(rate) * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / float(rate)
		var env := 1.0 - t / seconds
		var sample := int(sin(TAU * freq * t) * 0.2 * env * 32767.0)
		data[i * 2] = sample & 255
		data[i * 2 + 1] = (sample >> 8) & 255
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	voice.stream = stream
	voice.play()
