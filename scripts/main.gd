extends Control

const Rules = preload("res://scripts/run_state.gd")
const BoardView = preload("res://scripts/board_view.gd")

enum Mode { START, COMBAT, UPGRADES, WIN, LOSE }

const INK := Color("0e1116")
const PAPER := Color("e7e4dc")
const MUTED := Color("9aa3b5")
const GOLD := Color("f0d7a2")
const DANGER := Color("e07a72")

var state
var mode := Mode.START
var ui_lock := false
var resolving := false

var board
var start_screen: Control
var combat_screen: Control
var upgrade_screen: Control
var win_screen: Control
var lose_screen: Control

var floor_label: Label
var enemy_label: Label
var hp_value: Label
var hp_track: ColorRect
var hp_fill: ColorRect
var moves_value: Label
var action_label: Label
var upgrade_label: Label
var seed_label: Label
var legal_label: Label

var upgrade_heading: Label
var upgrade_owned: Label
var offer_titles: Array[Label] = []
var offer_descs: Array[Label] = []

var win_detail: Label
var lose_detail: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = _build_theme()
	state = Rules.new()
	_build_background()
	_build_start()
	_build_combat()
	_build_upgrades()
	_build_win()
	_build_lose()
	_show_start()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match mode:
		Mode.START, Mode.WIN, Mode.LOSE:
			if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER or key.keycode == KEY_SPACE:
				_start_run()
				get_viewport().set_input_as_handled()
		Mode.COMBAT:
			if board.handle_key(key.keycode):
				get_viewport().set_input_as_handled()
		Mode.UPGRADES:
			if key.keycode == KEY_1 or key.keycode == KEY_KP_1:
				_pick(0)
			elif key.keycode == KEY_2 or key.keycode == KEY_KP_2:
				_pick(1)
			elif key.keycode == KEY_3 or key.keycode == KEY_KP_3:
				_pick(2)


func _start_run() -> void:
	if ui_lock:
		return
	ui_lock = true
	var opened: Dictionary = state.start_run(_new_seed())
	await _enter_combat(opened)
	ui_lock = false


func _enter_combat(opened: Dictionary) -> void:
	mode = Mode.COMBAT
	_show_only(combat_screen)
	board.accept_input = false
	board.clear_selection()
	get_viewport().gui_release_focus()
	_refresh_hud()
	action_label.text = "准备战斗…"
	await _play(opened.get("steps", []))
	_refresh_hud()
	var outcome := str(opened.get("outcome", "continue"))
	var message := str(opened.get("message", ""))
	if outcome == "floor_clear":
		action_label.text = message if message != "" else "敌人被击败"
		_on_floor_clear()
		return
	action_label.text = message if message != "" else "交换相邻宝石，凑成三连。"
	board.accept_input = true


func _on_swap(a: Vector2i, b: Vector2i) -> void:
	if ui_lock or resolving or mode != Mode.COMBAT:
		return
	resolving = true
	board.accept_input = false
	var result: Dictionary = state.commit_swap(a, b)
	moves_value.text = str(state.moves_left)
	await _play(result.get("steps", []))
	action_label.text = str(result.get("message", ""))
	_refresh_hud()
	var outcome := str(result.get("outcome", "continue"))
	resolving = false
	if outcome == "floor_clear":
		_on_floor_clear()
	elif outcome == "lose":
		_show_lose()
	else:
		board.accept_input = true


func _on_floor_clear() -> void:
	board.accept_input = false
	if state.floor_index >= Rules.FLOORS:
		_show_win()
		return
	state.roll_offers()
	_show_upgrades()


func _pick(index: int) -> void:
	if ui_lock or mode != Mode.UPGRADES:
		return
	ui_lock = true
	if not state.choose_upgrade(index):
		ui_lock = false
		return
	var opened: Dictionary = state.begin_floor()
	await _enter_combat(opened)
	ui_lock = false


func _play(steps: Array) -> void:
	for step in steps:
		var kind := str(step.get("kind", ""))
		if kind == "clear" or kind == "bomb":
			board.highlight(step.get("matched", []))
			var dealt := int(step.get("damage", 0))
			var cascade := int(step.get("cascade", 0))
			if kind == "bomb":
				action_label.text = "开场爆弹造成 %d 点伤害" % dealt
			elif cascade > 0:
				action_label.text = "连锁 %d · 造成 %d 点伤害" % [cascade, dealt]
			else:
				action_label.text = "造成 %d 点伤害" % dealt
			_set_hp(int(step.get("enemy_hp", state.enemy_hp)))
			await get_tree().create_timer(0.2).timeout
		elif kind == "board":
			board.show_cells(step.get("board", []))
			if step.has("enemy_hp"):
				_set_hp(int(step["enemy_hp"]))
			var note := str(step.get("message", ""))
			if note != "":
				action_label.text = note
			var delay := float(step.get("delay", 0.12))
			await get_tree().create_timer(delay).timeout
		elif kind == "message":
			action_label.text = str(step.get("text", ""))
	board.clear_highlight()


func _refresh_hud() -> void:
	floor_label.text = "第 %d / %d 层" % [state.floor_index, Rules.FLOORS]
	enemy_label.text = state.enemy_name
	moves_value.text = str(state.moves_left)
	upgrade_label.text = state.upgrade_summary()
	seed_label.text = "种子  %d" % state.seed_value
	legal_label.text = "可消除的交换  %d" % state.list_moves().size()
	_set_hp(state.enemy_hp)


func _set_hp(hp: int) -> void:
	var maximum := maxi(state.enemy_max_hp, 1)
	hp_value.text = "%d / %d" % [hp, state.enemy_max_hp]
	var width := hp_track.size.x
	if width < 2.0:
		width = hp_track.custom_minimum_size.x
	var height := hp_track.size.y
	if height < 2.0:
		height = hp_track.custom_minimum_size.y
	var ratio := clampf(float(hp) / float(maximum), 0.0, 1.0)
	hp_fill.size = Vector2(width * ratio, height)
	hp_fill.position = Vector2.ZERO
	hp_fill.color = Color("d4544a") if ratio > 0.35 else Color("e0a24a")


func _show_start() -> void:
	mode = Mode.START
	_show_only(start_screen)


func _show_upgrades() -> void:
	mode = Mode.UPGRADES
	upgrade_heading.text = "第 %d 层已清除" % state.floor_index
	upgrade_owned.text = "已有强化：%s" % state.upgrade_summary()
	for i in offer_titles.size():
		var info: Dictionary = state.offer[i]
		offer_titles[i].text = str(info["name"])
		offer_descs[i].text = str(info["desc"])
	_show_only(upgrade_screen)
	get_viewport().gui_release_focus()


func _show_win() -> void:
	mode = Mode.WIN
	win_detail.text = "五层守关人尽数倒下。\n种子  %d\n强化  %s" % [state.seed_value, state.upgrade_summary()]
	_show_only(win_screen)


func _show_lose() -> void:
	mode = Mode.LOSE
	lose_detail.text = "止步于第 %d 层 · %s\n还剩 %d 点气血\n种子  %d" % [
		state.floor_index,
		state.enemy_name,
		state.enemy_hp,
		state.seed_value,
	]
	_show_only(lose_screen)


func _show_only(which: Control) -> void:
	for screen in [start_screen, combat_screen, upgrade_screen, win_screen, lose_screen]:
		screen.visible = screen == which
	board.accept_input = false


func _build_background() -> void:
	var background := ColorRect.new()
	background.color = INK
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.offset_right = 0
	background.offset_bottom = 0
	add_child(background)


func _build_start() -> void:
	start_screen = _full_center()
	var panel := _card_panel(Color("161b24"))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(560, 0)
	panel.add_child(box)
	start_screen.add_child(panel)

	var title := _label("消消乐 Rogue", 42, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := _label("五层试炼 · 三消对决", 18, MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var rules := _label(
		"用三消击败每一层的敌人。步数耗尽之前打空气血，才能进入下一层。\n\n· 点击或拖拽，交换两颗相邻宝石\n· 只有形成 3 连及以上，交换才会生效并消耗 1 步\n· 宝石下落并补齐；若再次连成三消，连锁会继续造成伤害\n· 4 连和更长的消除伤害更高\n\n共 5 层。每通关一层，从 3 项强化里选 1 项，效果保留到本局结束。新的一局会重新抽取种子和强化。",
		16,
		PAPER,
		true
	)
	rules.custom_minimum_size = Vector2(520, 0)
	box.add_child(rules)
	var button := _button("开始试炼")
	button.custom_minimum_size = Vector2(220, 52)
	button.pressed.connect(_start_run)
	box.add_child(button)
	var hint := _label("回车或空格也可以开始", 14, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	add_child(start_screen)


func _build_combat() -> void:
	combat_screen = MarginContainer.new()
	_cover(combat_screen)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		combat_screen.add_theme_constant_override(side, 24)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	combat_screen.add_child(row)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)

	var side_panel := _card_panel(Color("161b24"))
	side_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(side_panel)

	var side_box := VBoxContainer.new()
	side_box.add_theme_constant_override("separation", 6)
	side_panel.add_child(side_box)

	var title := _label("消消乐 Rogue", 26, GOLD)
	side_box.add_child(title)
	seed_label = _label("种子", 14, MUTED)
	side_box.add_child(seed_label)
	side_box.add_child(_gap(8))

	floor_label = _label("第 1 / 5 层", 22, PAPER)
	side_box.add_child(floor_label)
	enemy_label = _label("山门小贼", 20, GOLD)
	side_box.add_child(enemy_label)
	side_box.add_child(_label("气血", 14, MUTED))
	hp_track = ColorRect.new()
	hp_track.custom_minimum_size = Vector2(260, 16)
	hp_track.color = Color("2a303c")
	hp_track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_fill = ColorRect.new()
	hp_fill.color = Color("d4544a")
	hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_fill.size = Vector2(260, 16)
	hp_track.add_child(hp_fill)
	hp_track.resized.connect(_refresh_hp_bar)
	side_box.add_child(hp_track)
	hp_value = _label("0 / 0", 16, PAPER)
	side_box.add_child(hp_value)
	side_box.add_child(_gap(8))

	side_box.add_child(_label("剩余步数", 14, MUTED))
	moves_value = _label("0", 40, PAPER)
	side_box.add_child(moves_value)
	legal_label = _label("可消除的交换  0", 14, MUTED)
	side_box.add_child(legal_label)
	side_box.add_child(_gap(8))

	side_box.add_child(_label("战报", 14, MUTED))
	action_label = _label("交换相邻宝石，凑成三连。", 16, PAPER, true)
	action_label.custom_minimum_size = Vector2(250, 0)
	side_box.add_child(action_label)
	side_box.add_child(_gap(8))

	side_box.add_child(_label("已获得强化", 14, MUTED))
	upgrade_label = _label("无", 16, GOLD, true)
	upgrade_label.custom_minimum_size = Vector2(250, 0)
	side_box.add_child(upgrade_label)
	side_box.add_child(_gap(10))
	var help := _label("鼠标点击两颗相邻宝石，或拖向相邻格。\n方向键移动光标，空格或回车确认。\n不能消除的交换会弹回，不扣步。", 14, MUTED, true)
	help.custom_minimum_size = Vector2(250, 0)
	side_box.add_child(help)

	var right := CenterContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	board = BoardView.new()
	board.swap_requested.connect(_on_swap)
	right.add_child(board)
	add_child(combat_screen)


func _build_upgrades() -> void:
	upgrade_screen = _full_center()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	upgrade_screen.add_child(box)

	upgrade_heading = _label("第 1 层已清除", 36, GOLD)
	upgrade_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(upgrade_heading)
	var sub := _label("选择一项强化，效果持续到本局结束", 18, PAPER)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	upgrade_owned = _label("已有强化：无", 15, MUTED)
	upgrade_owned.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(upgrade_owned)

	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 18)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(cards)
	for i in 3:
		cards.add_child(_offer_card(i))
	var hint := _label("按 1 / 2 / 3 选择", 14, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	add_child(upgrade_screen)


func _offer_card(index: int) -> PanelContainer:
	var tints: Array[Color] = [Color("243044"), Color("24362f"), Color("3a3224")]
	var panel := _card_panel(tints[index])
	panel.custom_minimum_size = Vector2(250, 250)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(box)
	var title := _label("强化", 22, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var desc := _label("", 15, PAPER, true)
	desc.custom_minimum_size = Vector2(210, 96)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(title)
	box.add_child(desc)
	var button := _button("选择")
	button.pressed.connect(_pick.bind(index))
	box.add_child(button)
	offer_titles.append(title)
	offer_descs.append(desc)
	return panel


func _build_win() -> void:
	win_screen = _full_center()
	var panel := _card_panel(Color("161b24"))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(460, 0)
	panel.add_child(box)
	var title := _label("试炼通关", 40, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	win_detail = _label("", 18, PAPER, true)
	win_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_detail.custom_minimum_size = Vector2(420, 0)
	box.add_child(win_detail)
	var button := _button("再来一局")
	button.pressed.connect(_start_run)
	box.add_child(button)
	var hint := _label("回车或空格再开一局", 14, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	win_screen.add_child(panel)
	add_child(win_screen)


func _build_lose() -> void:
	lose_screen = _full_center()
	var panel := _card_panel(Color("161b24"))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(460, 0)
	panel.add_child(box)
	var title := _label("步数耗尽", 40, DANGER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	lose_detail = _label("", 18, PAPER, true)
	lose_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lose_detail.custom_minimum_size = Vector2(420, 0)
	box.add_child(lose_detail)
	var button := _button("再来一局")
	button.pressed.connect(_start_run)
	box.add_child(button)
	var hint := _label("回车或空格再开一局", 14, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	lose_screen.add_child(panel)
	add_child(lose_screen)


func _refresh_hp_bar() -> void:
	if state == null or hp_value == null:
		return
	var parts := hp_value.text.split(" / ")
	if parts.size() != 2:
		return
	_set_hp(int(parts[0]))


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


func _card_panel(color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(16)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 18
	style.content_margin_bottom = 18
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
	button.add_theme_font_size_override("font_size", 18)
	button.custom_minimum_size = Vector2(0, 46)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("2c384c")
	normal.set_corner_radius_all(10)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
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


func _gap(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


func _build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = _make_font()
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", PAPER)
	theme.set_color("font_color", "Button", PAPER)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", PAPER)
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
	if value == 0:
		value = 1
	return value
