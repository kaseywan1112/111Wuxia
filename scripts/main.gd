extends Control

const Rules = preload("res://scripts/run_state.gd")
const BoardView = preload("res://scripts/board_view.gd")
const LaneView = preload("res://scripts/lane_view.gd")

enum Mode { START, ROUTE, COMBAT, SHOP, REWARD, WIN, LOSE }

const INK := Color("0e1116")
const PAPER := Color("e7e4dc")
const MUTED := Color("9aa3b5")
const GOLD := Color("f0d7a2")
const DANGER := Color("e07a72")

var state
var mode := Mode.START
var ui_lock := false
var closing_fight := false

var board
var lane: Control
var world: Control
var world_base := Vector2(0, 78)
var fx: Control
var flash: ColorRect
var shake := 0.0
var flash_alpha := 0.0
var flash_color := Color.WHITE

var combat_root: Control
var start_screen: Control
var route_screen: Control
var shop_screen: Control
var reward_screen: Control
var win_screen: Control
var lose_screen: Control

var progress_label: Label
var hp_label: Label
var gold_label: Label
var combo_label: Label
var preview_label: Label
var action_label: Label
var empower_label: Label
var seed_label: Label
var combo_fill: ColorRect
var lamps: Array[ColorRect] = []
var shop_gold: Label
var shop_hint: Label
var shop_box: VBoxContainer
var reward_box: HBoxContainer
var win_detail: Label
var lose_detail: Label

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
	_build_route()
	_build_shop()
	_build_reward()
	_build_win()
	_build_lose()
	_build_flash()
	_build_audio()
	board.setup(Callable(state, "roll_color"))
	lane.set_fx(fx)
	board.chain_resolved.connect(_on_chain)
	board.chain_broken.connect(_on_broken)
	board.path_changed.connect(_on_path)
	board.board_note.connect(_on_board_note)
	lane.player_damaged.connect(_on_player_damaged)
	lane.foe_killed.connect(_on_killed)
	lane.fight_cleared.connect(_on_fight_cleared)
	lane.spell_hit.connect(_on_spell_hit)
	_show_start()


func _process(delta: float) -> void:
	_tick_shake(delta)
	_tick_flash(delta)
	if mode != Mode.COMBAT or closing_fight:
		return
	if state.combo > 0:
		state.combo_time = maxf(state.combo_time - delta, 0.0)
		if state.combo_time <= 0.0:
			state.break_combo()
			_break_juice()
		_paint_combo()
	lane.tick(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match mode:
		Mode.START, Mode.WIN, Mode.LOSE:
			if _is_accept(key.keycode):
				_start_run()
				get_viewport().set_input_as_handled()
		Mode.ROUTE:
			if key.keycode == KEY_1 or key.keycode == KEY_KP_1:
				_pick_route(0)
			elif key.keycode == KEY_2 or key.keycode == KEY_KP_2:
				_pick_route(1)
			elif key.keycode == KEY_3 or key.keycode == KEY_KP_3:
				_pick_route(2)
		Mode.REWARD:
			if key.keycode == KEY_1 or key.keycode == KEY_KP_1:
				_pick_reward(0)
			elif key.keycode == KEY_2 or key.keycode == KEY_KP_2:
				_pick_reward(1)
			elif key.keycode == KEY_3 or key.keycode == KEY_KP_3:
				_pick_reward(2)
		Mode.SHOP:
			if key.keycode == KEY_1 or key.keycode == KEY_KP_1:
				_buy(0)
			elif key.keycode == KEY_2 or key.keycode == KEY_KP_2:
				_buy(1)
			elif key.keycode == KEY_3 or key.keycode == KEY_KP_3:
				_buy(2)
			elif _is_accept(key.keycode):
				_leave_shop()


func _start_run() -> void:
	if ui_lock:
		return
	ui_lock = true
	state.start_run(_new_seed())
	closing_fight = false
	_show_route()
	ui_lock = false


func _pick_route(index: int) -> void:
	if ui_lock or mode != Mode.ROUTE:
		return
	ui_lock = true
	state.choose_route(index)
	_enter_node()
	ui_lock = false


func _enter_node() -> void:
	if state.route_done():
		_show_win()
		return
	match state.current_kind():
		"trash", "elite", "boss":
			_start_fight()
		"shop":
			_open_shop()
		"reward":
			_open_reward()
		_:
			_show_win()


func _start_fight() -> void:
	mode = Mode.COMBAT
	closing_fight = false
	state.break_combo()
	_show_only(combat_root)
	board.refill()
	board.accept_input = true
	lane.freeze_bonus = state.freeze_bonus
	lane.summon_bonus = state.summon_bonus
	lane.begin_fight(state.current_kind(), state.trash_variant(), state.hp, state.max_hp)
	action_label.text = "敌人从下方走上来。划同色宝石来施法。"
	preview_label.text = "按住同色宝石划线，上下左右，至少 3 颗"
	_refresh_hud()
	get_viewport().gui_release_focus()


func _on_chain(color_index: int, length: int, origin: Vector2) -> void:
	if mode != Mode.COMBAT:
		return
	var school := str(state.school_of(color_index))
	var empowered := bool(state.empower_next) and school != "white"
	state.note_chain_success()
	var kind := str(state.spell_kind(school, length))
	var title := str(state.spell_title(school, length))
	if school == "white":
		var text := str(state.apply_white(kind))
		if kind == "extra":
			lane.apply_global_slow(1.6)
		action_label.text = text
		_spark(origin, Rules.GEM_COLORS[4])
	else:
		var damage := float(state.chain_damage(length, state.combo, empowered))
		if empowered:
			state.empower_next = false
		lane.cast(school, kind, damage, origin, empowered)
		action_label.text = "%s  ·  %d" % [title, int(round(damage))]
		if length >= Rules.SUPER_AT:
			action_label.text += "  ·  大招"
	_success_juice(color_index)
	_refresh_hud()


func _on_broken() -> void:
	if state.combo > 0:
		state.break_combo()
		_break_juice()
	preview_label.text = "不足 3 颗，连击中断"
	_refresh_hud()


func _on_path(color_index: int, length: int) -> void:
	if length <= 0 or color_index < 0:
		return
	var school := str(state.school_of(color_index))
	if length < Rules.MIN_CHAIN:
		preview_label.text = "%s  %d / 3" % [state.school_name(color_index), length]
		return
	if school == "white":
		preview_label.text = "白宝石  ·  %d 连  ·  %s" % [length, state.spell_title(school, length)]
		return
	var empowered := bool(state.empower_next)
	var damage := float(state.chain_damage(length, state.combo + 1, empowered))
	preview_label.text = "%s  ·  %d 连  ·  ×%.2f  ·  预计 %d%s" % [
		state.spell_title(school, length),
		length,
		state.length_multiplier(length),
		int(round(damage)),
		"  ·  已强化" if empowered else "",
	]


func _on_board_note(text: String) -> void:
	action_label.text = text


func _on_player_damaged(amount: int) -> void:
	if mode != Mode.COMBAT or state.hp <= 0:
		return
	state.hp = maxi(state.hp - amount, 0)
	lane.set_player_hp(state.hp, state.max_hp)
	shake = maxf(shake, 6.0)
	_refresh_hud()
	if state.hp <= 0:
		board.accept_input = false
		lane.stop()
		_show_lose()


func _on_killed(gold: int) -> void:
	state.gold += gold
	_refresh_hud()
	_play_tone(660.0, 0.07, 0.22)


func _on_fight_cleared() -> void:
	if mode != Mode.COMBAT or state.hp <= 0 or closing_fight:
		return
	closing_fight = true
	board.accept_input = false
	action_label.text = "这一关清完了"
	await get_tree().create_timer(0.7).timeout
	closing_fight = false
	if mode != Mode.COMBAT or state.hp <= 0:
		return
	if state.current_kind() == "boss":
		_show_win()
		return
	state.advance()
	_enter_node()


func _on_spell_hit(_school: String) -> void:
	shake = maxf(shake, 2.5)
	_play_tone(210.0, 0.04, 0.16)


func _open_shop() -> void:
	mode = Mode.SHOP
	state.roll_shop()
	_rebuild_shop()
	_show_only(shop_screen)


func _buy(index: int) -> void:
	if mode != Mode.SHOP or index < 0 or index >= state.shop_stock.size():
		return
	var id := str(state.shop_stock[index])
	if id == "":
		return
	if not state.apply_shop(id):
		shop_hint.text = "金币不足"
		return
	state.shop_stock[index] = ""
	_rebuild_shop()
	lane.set_player_hp(state.hp, state.max_hp)


func _leave_shop() -> void:
	if mode != Mode.SHOP:
		return
	state.advance()
	_enter_node()


func _open_reward() -> void:
	mode = Mode.REWARD
	state.roll_reward()
	_rebuild_reward()
	_show_only(reward_screen)


func _pick_reward(index: int) -> void:
	if ui_lock or mode != Mode.REWARD or index < 0 or index >= state.reward_stock.size():
		return
	ui_lock = true
	state.apply_reward(str(state.reward_stock[index]))
	state.advance()
	_enter_node()
	ui_lock = false


func _show_start() -> void:
	mode = Mode.START
	_show_only(start_screen)


func _show_route() -> void:
	mode = Mode.ROUTE
	_show_only(route_screen)


func _show_win() -> void:
	mode = Mode.WIN
	board.accept_input = false
	lane.stop()
	win_detail.text = "你走完了%s。\n种子  %d\n剩余生命  %d\n金币  %d" % [
		state.route_name(), state.seed_value, state.hp, state.gold,
	]
	_show_only(win_screen)


func _show_lose() -> void:
	mode = Mode.LOSE
	board.accept_input = false
	lane.stop()
	lose_detail.text = "倒在%s的%s。\n种子  %d\n金币  %d" % [
		state.route_name(), Rules.node_title(state.current_kind()), state.seed_value, state.gold,
	]
	_show_only(lose_screen)


func _show_only(which: Control) -> void:
	for screen in [start_screen, route_screen, combat_root, shop_screen, reward_screen, win_screen, lose_screen]:
		screen.visible = screen == which


func _refresh_hud() -> void:
	progress_label.text = state.progress_text()
	hp_label.text = "生命  %d / %d" % [state.hp, state.max_hp]
	gold_label.text = "金币  %d" % state.gold
	seed_label.text = "种子 %d" % state.seed_value
	empower_label.text = "下一发已强化" if state.empower_next else ""
	_paint_combo()


func _paint_combo() -> void:
	if state.combo <= 0:
		combo_label.text = "连击  0"
		combo_fill.size.x = 0
	else:
		var bonus := int(round((state.combo_multiplier(state.combo) - 1.0) * 100.0))
		combo_label.text = "连击  x%d    伤害 +%d%%" % [state.combo, bonus]
		var window := maxf(state.combo_window(), 0.1)
		combo_fill.size.x = 220.0 * clampf(state.combo_time / window, 0.0, 1.0)
	for i in lamps.size():
		var on: bool = i < state.combo
		lamps[i].color = Color("f0d7a2") if on else Color("2a303c")
		if on and state.combo >= 5:
			lamps[i].modulate = Color(1.2, 1.05, 0.7)
		else:
			lamps[i].modulate = Color.WHITE


func _success_juice(color_index: int) -> void:
	var level := int(state.combo)
	shake = 3.0 + float(mini(level, 10)) * 1.15
	flash_alpha = 0.14 + float(mini(level, 8)) * 0.04
	flash_color = Rules.GEM_COLORS[clampi(color_index, 0, Rules.GEM_COLORS.size() - 1)]
	var pitch := 480.0 + float(level) * 42.0
	_play_tone(pitch, 0.07, 0.34)
	_play_tone(pitch * 1.25, 0.08, 0.26)
	if level >= 3:
		_play_tone(pitch * 1.5, 0.1, 0.28)
	if level >= 5:
		_play_tone(pitch * 1.9, 0.14, 0.24)
	if level >= 8:
		shake += 6.0
		flash_alpha += 0.12


func _break_juice() -> void:
	shake = maxf(shake, 2.0)
	flash_alpha = maxf(flash_alpha, 0.12)
	flash_color = Color("6e3030")
	_play_tone(130.0, 0.11, 0.28)


func _spark(origin: Vector2, color: Color) -> void:
	var gem := Polygon2D.new()
	gem.polygon = PackedVector2Array([
		Vector2(0, -12), Vector2(12, 0), Vector2(0, 12), Vector2(-12, 0),
	])
	gem.color = color
	var holder := Node2D.new()
	holder.add_child(gem)
	fx.add_child(holder)
	holder.global_position = origin
	var dest := lane.global_position + Vector2(LaneView.LANE_W * 0.5, 58)
	var tween := create_tween()
	tween.tween_property(holder, "global_position", dest, 0.28)
	tween.tween_callback(holder.queue_free)


func _tick_shake(delta: float) -> void:
	if shake > 0.0:
		world.position = world_base + Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
		shake = maxf(shake - delta * 28.0, 0.0)
	else:
		world.position = world_base


func _tick_flash(delta: float) -> void:
	if flash_alpha > 0.0:
		flash_alpha = maxf(flash_alpha - delta * 1.35, 0.0)
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
	hud.size = Vector2(1248, 64)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hud_style := StyleBoxFlat.new()
	hud_style.bg_color = Color("161b24")
	hud_style.set_corner_radius_all(12)
	hud_style.content_margin_left = 14
	hud_style.content_margin_right = 14
	hud_style.content_margin_top = 6
	hud_style.content_margin_bottom = 6
	hud.add_theme_stylebox_override("panel", hud_style)
	combat_root.add_child(hud)
	var hud_box := VBoxContainer.new()
	hud_box.add_theme_constant_override("separation", 2)
	hud.add_child(hud_box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	hud_box.add_child(top)
	progress_label = _label("路线", 16, GOLD)
	hp_label = _label("生命", 16, PAPER)
	gold_label = _label("金币", 16, PAPER)
	seed_label = _label("种子", 14, MUTED)
	top.add_child(progress_label)
	top.add_child(hp_label)
	top.add_child(gold_label)
	top.add_child(seed_label)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	hud_box.add_child(bottom)
	combo_label = _label("连击  0", 15, GOLD)
	bottom.add_child(combo_label)
	var timer_track := ColorRect.new()
	timer_track.custom_minimum_size = Vector2(220, 8)
	timer_track.color = Color("2a303c")
	timer_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combo_fill = ColorRect.new()
	combo_fill.color = Color("f0d7a2")
	combo_fill.size = Vector2(0, 8)
	combo_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_track.add_child(combo_fill)
	bottom.add_child(timer_track)
	for _i in 8:
		var lamp := ColorRect.new()
		lamp.custom_minimum_size = Vector2(14, 14)
		lamp.color = Color("2a303c")
		lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bottom.add_child(lamp)
		lamps.append(lamp)
	empower_label = _label("", 15, Color("fff1b8"))
	bottom.add_child(empower_label)

	world = Control.new()
	world.position = world_base
	world.size = Vector2(1280, 710)
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combat_root.add_child(world)

	board = BoardView.new()
	board.position = Vector2(50, 8)
	world.add_child(board)
	lane = LaneView.new()
	lane.position = Vector2(660, 4)
	world.add_child(lane)

	preview_label = _label("按住同色宝石划线，上下左右，至少 3 颗", 16, PAPER, true)
	preview_label.position = Vector2(50, 530)
	preview_label.size = Vector2(520, 48)
	world.add_child(preview_label)
	action_label = _label("", 18, GOLD, true)
	action_label.position = Vector2(50, 578)
	action_label.size = Vector2(520, 48)
	world.add_child(action_label)
	var legend := _label("红 火焰    蓝 寒冰    绿 藤蔓    紫 雷电    白 奖励", 14, MUTED)
	legend.position = Vector2(50, 632)
	world.add_child(legend)

	fx = Control.new()
	_cover(fx)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combat_root.add_child(fx)


func _build_start() -> void:
	start_screen = _full_center()
	var panel := _card(Color("161b24"))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(620, 0)
	panel.add_child(box)
	var title := _label("消消乐 Rogue", 40, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := _label("左边划宝石，右边打一条路", 18, MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var rules := _label(
		"按住鼠标，在相邻的同色宝石上划线。只能上下左右，可以转弯，不能斜着连。至少 3 颗才算成功。第 4 颗起，每多 1 颗伤害 ×1.15。连到 6 颗会施放该颜色的大招。\n\n红是火焰，蓝是寒冰，绿是藤蔓，紫是雷电。白宝石不攻击，而是额外连锁、强化下一发，或一份战利品。\n\n敌人从右边赛道的底部往上走，你站在顶端。法术会从划线飞到赛道上。连击越高，增伤、闪屏和声音越猛；划断或停太久，连击就掉。",
		16,
		PAPER,
		true
	)
	rules.custom_minimum_size = Vector2(580, 0)
	box.add_child(rules)
	var button := _button("选择路线")
	button.pressed.connect(_start_run)
	box.add_child(button)
	var hint := _label("回车或空格也可以开始", 14, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	start_screen.add_child(panel)
	add_child(start_screen)


func _build_route() -> void:
	route_screen = _full_center()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	route_screen.add_child(box)
	var title := _label("选择一条路线", 36, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := _label("三条路都按顺序走完，没有地图。", 16, MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var tints: Array[Color] = [Color("243044"), Color("3a3224"), Color("24362f")]
	for i in Rules.ROUTES.size():
		var info: Dictionary = Rules.ROUTES[i]
		var panel := _card(tints[i])
		panel.custom_minimum_size = Vector2(280, 280)
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 8)
		panel.add_child(inner)
		var name := _label(str(info["name"]), 24, GOLD)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(name)
		var blurb := _label(str(info["blurb"]), 15, PAPER, true)
		blurb.custom_minimum_size = Vector2(240, 48)
		inner.add_child(blurb)
		var steps := _label(Rules.route_steps_text(i), 14, MUTED, true)
		steps.custom_minimum_size = Vector2(240, 72)
		inner.add_child(steps)
		var button := _button("走这条")
		button.pressed.connect(_pick_route.bind(i))
		inner.add_child(button)
		row.add_child(panel)
	var hint := _label("按 1 / 2 / 3 选择", 14, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	add_child(route_screen)


func _build_shop() -> void:
	shop_screen = _full_center()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	shop_screen.add_child(box)
	var title := _label("商店", 36, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	shop_gold = _label("金币  0", 18, PAPER)
	shop_gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(shop_gold)
	shop_box = VBoxContainer.new()
	shop_box.add_theme_constant_override("separation", 8)
	shop_box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(shop_box)
	shop_hint = _label("", 15, DANGER)
	shop_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(shop_hint)
	var leave := _button("离开商店")
	leave.pressed.connect(_leave_shop)
	box.add_child(leave)
	var hint := _label("1 / 2 / 3 购买，回车离开", 14, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	add_child(shop_screen)


func _rebuild_shop() -> void:
	shop_gold.text = "金币  %d    生命  %d / %d" % [state.gold, state.hp, state.max_hp]
	shop_hint.text = ""
	for child in shop_box.get_children():
		child.queue_free()
	for i in state.shop_stock.size():
		var id := str(state.shop_stock[i])
		var button := _button("")
		button.custom_minimum_size = Vector2(520, 52)
		if id == "" or not Rules.SHOP.has(id):
			button.text = "已购买"
			button.disabled = true
		else:
			var info: Dictionary = Rules.SHOP[id]
			button.text = "%s    %d 金    %s" % [info["name"], int(info["price"]), info["desc"]]
			button.pressed.connect(_buy.bind(i))
		shop_box.add_child(button)


func _build_reward() -> void:
	reward_screen = _full_center()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	reward_screen.add_child(box)
	var title := _label("选择一项奖赏", 36, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := _label("效果保留到这局结束", 16, MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	reward_box = HBoxContainer.new()
	reward_box.add_theme_constant_override("separation", 16)
	reward_box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(reward_box)
	var hint := _label("按 1 / 2 / 3 选择", 14, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	add_child(reward_screen)


func _rebuild_reward() -> void:
	for child in reward_box.get_children():
		child.queue_free()
	var tints: Array[Color] = [Color("243044"), Color("24362f"), Color("3a3224")]
	for i in state.reward_stock.size():
		var id := str(state.reward_stock[i])
		var info: Dictionary = Rules.REWARDS[id]
		var panel := _card(tints[i % tints.size()])
		panel.custom_minimum_size = Vector2(250, 220)
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 8)
		panel.add_child(inner)
		var name := _label(str(info["name"]), 22, GOLD)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(name)
		var desc := _label(str(info["desc"]), 15, PAPER, true)
		desc.custom_minimum_size = Vector2(210, 72)
		inner.add_child(desc)
		var button := _button("拿走")
		button.pressed.connect(_pick_reward.bind(i))
		inner.add_child(button)
		reward_box.add_child(panel)


func _build_win() -> void:
	win_screen = _full_center()
	var panel := _card(Color("161b24"))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(460, 0)
	panel.add_child(box)
	var title := _label("路线清空", 40, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	win_detail = _label("", 18, PAPER, true)
	win_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_detail.custom_minimum_size = Vector2(420, 0)
	box.add_child(win_detail)
	var button := _button("再来一局")
	button.pressed.connect(_start_run)
	box.add_child(button)
	win_screen.add_child(panel)
	add_child(win_screen)


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
