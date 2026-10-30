extends SceneTree

const Rules = preload("res://scripts/run_state.gd")

var errors: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_multiplier()
	_test_schools()
	_test_path_rules()
	_test_level_ups()
	_test_routes()
	_test_combo_and_white()
	_test_tank_and_kill()
	if errors.is_empty():
		print("SIM_OK")
		quit(0)
	for err in errors:
		print("FAIL ", err)
	quit(1)


func _test_multiplier() -> void:
	var state = Rules.new()
	state.start_run(7)
	var three := float(state.chain_damage(3, 1, false))
	var four := float(state.chain_damage(4, 1, false))
	var six := float(state.chain_damage(6, 1, false))
	_check(_near(four / three, Rules.STEP_MULT), "4th gem multiplies by 1.15, got %s" % str(four / three))
	_check(_near(six / three, pow(Rules.STEP_MULT, 3.0)), "two extra steps compound")
	_check(float(state.chain_damage(2, 1, false)) == 0.0, "short chain deals nothing")
	_check(six > four and four > three, "longer chains hit harder")
	var empowered := float(state.chain_damage(3, 1, true))
	_check(empowered > three * 1.5, "empower is a large bonus")


func _test_schools() -> void:
	var state = Rules.new()
	_check(state.spell_kind("fire", 3) == "fireball", "fire 3 is a fireball")
	_check(state.spell_kind("fire", 4) == "burn", "fire 4 burns")
	_check(state.spell_kind("fire", 6) == "explosion", "fire 6 explodes")
	_check(state.spell_kind("ice", 3) == "spike", "ice spike")
	_check(state.spell_kind("ice", 5) == "freeze", "ice freeze")
	_check(state.spell_kind("ice", 6) == "wall", "ice wall super")
	_check(state.spell_kind("vine", 3) == "lash", "vine lash")
	_check(state.spell_kind("vine", 4) == "entangle", "vine entangle")
	_check(state.spell_kind("vine", 8) == "summon", "vine summon super")
	_check(state.spell_kind("lightning", 3) == "bolt", "lightning bolt")
	_check(state.spell_kind("lightning", 4) == "chain", "lightning chains")
	_check(state.spell_kind("lightning", 6) == "stun", "lightning stun super")
	_check(state.spell_kind("white", 3) == "extra", "white 3 is extra chain")
	_check(state.spell_kind("white", 5) == "empower", "white 5 empowers")
	_check(state.spell_kind("white", 6) == "loot", "white 6 is a reward")
	_check(state.spell_kind("fire", 5) != "explosion", "5 is not yet a super")


func _test_path_rules() -> void:
	var touch := 50.0
	var diagonal: Dictionary = Rules.resolve_touch_chain([
		{"color": 0, "pos": Vector2(0, 0)},
		{"color": 0, "pos": Vector2(30, 30)},
		{"color": 0, "pos": Vector2(60, 60)},
	], touch)
	_check(int(diagonal["color"]) == 0 and int(diagonal["length"]) == 3, "a diagonal touch chain counts")
	var bend: Dictionary = Rules.resolve_touch_chain([
		{"color": 2, "pos": Vector2(0, 0)},
		{"color": 2, "pos": Vector2(40, 0)},
		{"color": 2, "pos": Vector2(40, 40)},
	], touch)
	_check(int(bend["color"]) == 2 and int(bend["length"]) == 3, "the stroke can turn any direction")
	var gap: Dictionary = Rules.resolve_touch_chain([
		{"color": 0, "pos": Vector2(0, 0)},
		{"color": 0, "pos": Vector2(100, 0)},
		{"color": 0, "pos": Vector2(200, 0)},
	], touch)
	_check(int(gap["length"]) == 1, "a gap does not extend the chain")
	var blocked: Dictionary = Rules.resolve_touch_chain([
		{"color": 0, "pos": Vector2(0, 0)},
		{"color": 1, "pos": Vector2(40, 0)},
		{"color": 0, "pos": Vector2(80, 0)},
	], touch)
	_check(int(blocked["color"]) == 0 and int(blocked["length"]) == 1, "a different color does not bridge a gap")
	var through: Dictionary = Rules.resolve_touch_chain([
		{"color": 0, "pos": Vector2(0, 0)},
		{"color": 1, "pos": Vector2(20, 20)},
		{"color": 0, "pos": Vector2(36, 0)},
	], touch)
	_check(int(through["length"]) == 2, "a different color is skipped when the next gem still touches")
	var short: Dictionary = Rules.resolve_touch_chain([
		{"color": 0, "pos": Vector2(0, 0)},
		{"color": 0, "pos": Vector2(40, 0)},
	], touch)
	_check(int(short["length"]) == 2 and int(short["color"]) == 0, "two touching gems are not a cast")
	var none: Dictionary = Rules.resolve_touch_chain([], touch)
	_check(int(none["length"]) == 0 and int(none["color"]) == -1, "an empty stroke has no color")
	var six_hits: Array = []
	for i in 6:
		six_hits.append({"color": 3, "pos": Vector2(float(i) * 40.0, 0)})
	var six: Dictionary = Rules.resolve_touch_chain(six_hits, touch)
	_check(int(six["color"]) == 3 and int(six["length"]) == 6, "six touching gems is the super length")
	_check(Rules.SUPER_AT == 6 and int(six["length"]) >= Rules.SUPER_AT, "length 6 reaches the super")


func _test_level_ups() -> void:
	var state = Rules.new()
	state.start_run(9)
	_check(state.note_kill() == false, "the first kill does not level")
	_check(state.note_kill() == false, "the second kill does not level")
	_check(state.note_kill(), "the third kill levels up")
	_check(state.level == 2 and state.kills_needed == 4 and state.kills_toward == 0, "the next stretch asks for one more kill")
	state.roll_level()
	_check(state.level_stock.size() == 3, "a level offers three choices")
	var seen := {}
	for id in state.level_stock:
		_check(Rules.LEVEL_UPS.has(str(id)), "level choice exists")
		_check(not seen.has(str(id)), "level choices are distinct")
		seen[str(id)] = true
	var power_before := float(state.spell_power)
	state.apply_level("power")
	_check(state.spell_power == power_before + 0.12, "level power lasts on the run")
	var gold_before := int(state.gold)
	state.apply_level("purse")
	_check(state.gold == gold_before + 20, "level gold does not spend gold")
	state.start_run(9)
	_check(state.level == 1 and state.spell_power == 1.0 and state.gold == 0, "a new run clears level picks")


func _test_routes() -> void:
	_check(Rules.ROUTES.size() == 3, "three route sets")
	for i in Rules.ROUTES.size():
		var nodes: Array = Rules.ROUTES[i]["nodes"]
		for kind in ["trash", "elite", "shop", "reward", "boss"]:
			_check(nodes.has(kind), "%s missing %s" % [Rules.ROUTES[i]["name"], kind])
		_check(str(nodes[nodes.size() - 1]) == "boss", "route ends on the boss")
	var state = Rules.new()
	state.start_run(3)
	state.choose_route(1)
	_check(state.current_kind() == "trash", "steep route starts with trash")
	state.advance()
	_check(state.current_kind() == "elite", "then the elite")


func _test_combo_and_white() -> void:
	var state = Rules.new()
	state.start_run(11)
	state.note_chain_success()
	state.note_chain_success()
	_check(state.combo == 2, "chains raise combo")
	_check(state.combo_multiplier(2) > 1.0, "combo grants a damage buff")
	state.break_combo()
	_check(state.combo == 0, "a broken chain drops combo")
	state.note_chain_success()
	var text := str(state.apply_white("extra"))
	_check(state.combo == 2 and text.contains("额外"), "white extra chain adds combo")
	_check(state.apply_white("empower") != "" and state.empower_next, "white empowers the next spell")
	var gold_before := int(state.gold)
	var hp_before := int(state.hp)
	state.hp = 40
	state.apply_white("loot")
	_check(state.gold == gold_before + 25, "white loot pays gold")
	_check(state.hp == hp_before - 0 + 18 or state.hp == 58, "white loot heals")
	_check(state.hp == 58, "heal landed, hp %d" % state.hp)


func _test_tank_and_kill() -> void:
	var state = Rules.new()
	state.start_run(5)
	var grunt := float(Rules.FOES["grunt"]["hp"])
	var one := float(state.chain_damage(6, 1, false))
	_check(one < grunt * 0.5, "one super does not erase a grunt, %s vs %s" % [str(one), str(grunt)])
	var eight := float(state.chain_damage(8, 6, true))
	_check(eight < grunt, "even a long empowered chain leaves a grunt standing")
	var hp := grunt
	var combo := 0
	for _i in 16:
		combo += 1
		hp -= float(state.chain_damage(4, combo, false))
	_check(hp <= 0.0, "a run of chains can still drop a grunt")
	for school in ["fire", "ice", "vine", "lightning"]:
		_check(state.spell_kind(school, 6) != state.spell_kind("white", 6), "white is not a spell school")


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.02


func _check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)
		print("FAIL ", message)
