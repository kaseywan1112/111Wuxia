extends SceneTree

const Rules = preload("res://scripts/run_state.gd")
const Gems = preload("res://scripts/gem_board.gd")


func _init() -> void:
	_flow()
	_loot()
	_weapons()
	_later_area()
	_growth()
	_gems()
	print("SIM_OK")
	quit(0)


func _flow() -> void:
	var state: Rules = Rules.new()
	state.begin_run(3)
	_check(state.tick(1.0) == "", "the lane does not clear")
	_check(state.tick(7.0) == "rest", "rest arrives on a timer")
	_check(state.tick(8.0) == "boss", "a boss arrives on a timer")
	_check(state.tick(4.0) == "", "the boss does not end the lane")
	state.on_boss_killed()
	_check(state.area == 2, "a killed boss moves the lane on")
	_check(state.tick(5.0) == "", "the lane continues after the boss")
	_check(not state.add_xp(1) and not state.add_xp(1), "xp is gathered, not granted")
	_check(state.add_xp(1), "enough xp offers a pick")
	state.pickup_gear("ring")
	_check(state.carried.has("ring"), "gear goes straight into the backpack")
	_check(state.pass_damage(false) >= 14, "a monster that passes hurts")
	_check(state.pass_damage(true) > state.pass_damage(false), "a boss that passes hurts more")


func _loot() -> void:
	var state: Rules = Rules.new()
	state.begin_run(9)
	state.pickup_gear("hide")
	state.pickup_gear("ring")
	state.pickup_gold(20)
	var secured := state.secure_first()
	_check(secured == "hide", "secure first piece")
	_check(state.backpack == "hide", "backpack holds one")
	_check(state.carried.size() == 1, "other piece still carried")
	_check(state.secure_first() == "", "backpack is one slot")
	var failed: Dictionary = state.fail_run()
	_check(failed["lost"].size() == 1 and str(failed["lost"][0]) == "ring", "unsecured is lost")
	_check(int(failed["lost_gold"]) == 20, "unextracted gold is lost")
	_check(str(failed["kept"]) == "hide", "secured piece is kept")
	_check(state.stash.has("hide"), "secured piece reaches the stash")
	_check(state.run_gold == 0 and state.carried.is_empty(), "run loot is cleared")
	state.pickup_gear("jade")
	state.pickup_gold(11)
	var pulled: Dictionary = state.extract()
	_check(int(pulled["gold"]) == 11, "extract banks gold")
	_check(pulled["items"].has("jade"), "extract banks carried gear")
	_check(state.stash_gold == 11, "only extracted gold remains")
	_check(state.stash.has("jade"), "extracted gear remains")
	var path := "user://sim_extract.cfg"
	state.save_to(path)
	var loaded: Rules = Rules.new()
	_check(loaded.load_from(path), "load stash")
	_check(loaded.stash_gold == 11 and loaded.stash.has("hide"), "stash persists")
	loaded.begin_run(1)
	_check(loaded.stash_gold == 11 and loaded.run_gold == 0, "a new run keeps the stash")


func _weapons() -> void:
	var state: Rules = Rules.new()
	state.begin_run(1)
	_check(state.weapon == "chain", "start with 连弹")
	_check(state.weapon_bounces() < 0 and state.weapon_life() > 0.0, "连弹 bounces until it times out")
	_check(not state.weapon_needs_catch(), "连弹 does not need a catch")
	state.take_weapon("return")
	_check(state.weapon_needs_catch(), "回手 must be caught")
	_check(state.weapon_life() < 0.0, "回手 stays out until the catch")
	var chain_damage := float(Rules.WEAPONS["chain"]["damage"])
	var hammer_damage := float(Rules.WEAPONS["hammer"]["damage"])
	_check(hammer_damage > chain_damage * 2.0, "重锤 hits harder")
	_check(int(Rules.WEAPONS["hammer"]["bounces"]) >= 0, "重锤 runs out of bounces")
	_check(float(Rules.WEAPONS["hammer"]["speed"]) < float(Rules.WEAPONS["chain"]["speed"]), "重锤 is slower")
	_check(float(Rules.WEAPONS["hammer"]["damp"]) < 0.7, "重锤 bounces less")
	_check(state.take_weapon("return"), "回手 can be chosen")
	state.begin_run(4)
	_check(state.weapon == "chain", "a new run starts on 连弹")
	_check(state.owns_weapon("return"), "a chosen weapon stays known")


func _later_area() -> void:
	var state: Rules = Rules.new()
	state.begin_run(2)
	var first := state.monster_hp(false)
	var first_count := state.monster_count()
	state.area = 3
	_check(state.monster_hp(false) > first, "later areas hit harder")
	_check(state.monster_count() > first_count, "later areas have more monsters")
	_check(state.monster_hp(true) > state.monster_hp(false), "a boss is tougher than the room")


func _growth() -> void:
	var state: Rules = Rules.new()
	state.begin_run(5)
	_check(not state.note_kill(), "first kills do not offer yet")
	_check(not state.note_kill(), "second kill")
	_check(not state.note_kill(), "third kill")
	_check(state.note_kill(), "every fourth kill offers a pick")
	var picks := state.offer_picks()
	_check(picks.size() == 3, "three choices")
	_check(picks[0] != picks[1] and picks[1] != picks[2] and picks[0] != picks[2], "choices differ")
	state.apply_pick("damage")
	state.apply_pick("bounce")
	state.apply_pick("catch")
	state.apply_pick("rate")
	_check(state.run_damage == 4 and state.run_bounce == 1, "picks raise the run")
	_check(state.catch_gold() == 12, "catch bonus grew")
	_check(state.weapon_speed() > float(Rules.WEAPONS["chain"]["speed"]), "fire rate speeds the ball")
	state.take_weapon("hammer")
	_check(state.weapon_bounces() == int(Rules.WEAPONS["hammer"]["bounces"]) + 1, "extra bounce on 重锤")
	state.fail_run()
	_check(state.run_damage == 0 and state.run_catch == 0 and state.catch_gold() == 8, "run picks are lost on death")
	state.stash_gold = 40
	state._bank_gear("hide")
	_check(state.upgrade_first() == "hide", "extracted gold upgrades gear")
	_check(state.stash_gold == 28 and state.stash_level[0] == 1, "upgrade spends extracted gold")
	state.run_gold = 100
	var before := state.stash_gold
	_check(state.socket_first("red") == "hide", "one gem sockets")
	_check(state.stash_gem[0] == "red", "gem is stored")
	_check(state.socket_first("blue") == "", "a second gem does not fit")
	_check(state.run_gold == 100, "run gold is not spent")
	_check(state.buy_talent("steady"), "talent spends extracted gold")
	_check(not state.buy_talent("steady"), "a talent is bought once")
	state.begin_run(2)
	_check(state.talents.has("steady") and state.stash_level[0] == 1, "camp growth stays")
	_check(state.run_damage == 0, "a new run has no in-run picks")
	_check(state.bonus_hp() >= 8, "稳手 adds health")
	_check(state.salvage_first() == 8, "extracted gear can be broken into gold")
	_check(state.stash.is_empty(), "salvage removes the piece")
	_check(state.stash_gold == before - 10 - 18 + 8, "salvage returns extracted gold")


func _gems() -> void:
	var cols := 4
	var colors: Array = []
	var kinds: Array = []
	colors.resize(8)
	kinds.resize(8)
	colors.fill(0)
	kinds.fill(0)
	colors[2] = 1
	kinds[1] = 1
	var started: Dictionary = Gems.try_extend([], Vector2i(0, 0), colors, kinds, cols)
	_check(str(started["action"]) == "start", "a path can start on a gem")
	var straight: Dictionary = Gems.try_extend(started["path"], Vector2i(1, 0), colors, kinds, cols)
	_check(str(straight["action"]) == "add", "an adjacent gem extends the path")
	var turned: Dictionary = Gems.try_extend(straight["path"], Vector2i(1, 1), colors, kinds, cols)
	_check(str(turned["action"]) == "add", "the path can turn")
	var diagonal: Dictionary = Gems.try_extend(started["path"], Vector2i(1, 1), colors, kinds, cols)
	_check(str(diagonal["action"]) == "ignore", "a diagonal step is refused")
	var other: Dictionary = Gems.try_extend(straight["path"], Vector2i(2, 0), colors, kinds, cols)
	_check(str(other["action"]) == "ignore", "a different color does not join")
	var odd: Dictionary = Gems.try_extend(started["path"], Vector2i(3, 1), colors, kinds, cols)
	_check(str(odd["action"]) == "ignore", "a gem that is not adjacent stays out")
	kinds[5] = 2
	var special: Dictionary = Gems.try_extend(straight["path"], Vector2i(1, 1), colors, kinds, cols)
	_check(str(special["action"]) == "add", "a special gem can join any color")
	var effects := Gems.effects_of(special["path"], kinds, cols)
	_check(effects.has("reverse") and effects.has("split"), "the chain keeps both odd gems")
	var undone: Dictionary = Gems.try_extend(special["path"], Vector2i(1, 0), colors, kinds, cols)
	_check(str(undone["action"]) == "undo" and undone["path"].size() == 2, "dragging back undoes a step")
	_check(Gems.MIN_CHAIN == 3, "a chain needs three gems")


func _check(ok: bool, label: String) -> void:
	if not ok:
		push_error("FAIL " + label)
		quit(1)
