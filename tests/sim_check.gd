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
	_check(state.weapon == "red", "the turret starts on 直击")
	_check(state.weapon_style() == "hit", "直击 is a single hit")
	_check(state.weapon_style("blue") == "pierce", "贯穿 passes through")
	_check(state.weapon_style("green") == "splash", "溅射 splashes")
	_check(state.weapon_style("purple") == "slow", "迟滞 slows")
	_check(state.weapon_style("gold") == "guard", "护体 mends the wall")
	_check(state.burst_count(0) == 2, "直击 fires twice on a four-match")
	_check(state.burst_count(2) == 3, "溅射 fires three times on a four-match")
	_check(state.burst_count(4) == 3, "护体 mends three times on a four-match")
	state.set_main_from_color(3)
	_check(state.weapon == "purple", "the last match becomes the auto weapon")
	state.begin_run(4)
	_check(state.weapon == "red", "a new run starts on 直击 again")
	_check(state.owns_weapon("gold"), "all five weapons stay known")


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
	_check(state.guard_amount() == 12, "guard bonus grew")
	_check(state.auto_interval() < 1.25, "fire rate shortens the charge")
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
	var cols := 3
	var grid := [
		1, 4, 2,
		3, 7, 5,
		6, 7, 8,
		4, 7, 4,
	]
	var found := Gems.find_matches(grid, cols)
	_check(found.size() == 1 and int(found[0]["length"]) == 3, "three in a line clears")
	_check(Gems.kind_for_length(3) == "shot", "a three-match is one shot")
	var cleared := Gems.clear_cells(grid, cols, found[0]["cells"])
	var fallen := Gems.collapse(cleared, cols, 4, 9)
	var again := Gems.find_matches(fallen, cols)
	_check(not again.is_empty() and int(again[0]["color"]) == 4, "gems falling can cascade")
	var four := [0, 0, 0, 0, 1, 2, 3, 2, 3, 1]
	var fours := Gems.find_matches(four, 5)
	_check(int(fours[0]["length"]) == 4 and Gems.kind_for_length(4) == "burst", "four of a color is a burst")
	var five := [0, 0, 0, 0, 0, 1, 2, 1, 2, 1]
	var fives := Gems.find_matches(five, 5)
	_check(int(fives[0]["length"]) == 5 and Gems.kind_for_length(5) == "special", "five of a color is a special")


func _check(ok: bool, label: String) -> void:
	if not ok:
		push_error("FAIL " + label)
		quit(1)
