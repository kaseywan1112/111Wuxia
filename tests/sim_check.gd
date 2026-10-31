extends SceneTree

const Rules = preload("res://scripts/run_state.gd")

var errors: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_damage()
	_test_weapons()
	_test_cluster()
	_test_levels()
	if errors.is_empty():
		print("SIM_OK")
		quit(0)
	for err in errors:
		print("FAIL ", err)
	quit(1)


func _test_damage() -> void:
	var state = Rules.new()
	state.start_run(3)
	var three := float(state.chain_damage(3))
	var four := float(state.chain_damage(4))
	var six := float(state.chain_damage(6))
	_check(three == Rules.CHAIN_BASE, "a 3-chain is the base hit")
	_check(_near(four / three, Rules.STEP_MULT), "each extra bubble multiplies by 1.15")
	_check(_near(six / three, pow(Rules.STEP_MULT, 3.0)), "three extra steps compound")
	_check(float(state.chain_damage(2)) == 0.0, "fewer than 3 is not a chain")
	_check(Rules.BASIC_DAMAGE < three * 0.5, "a different color only deals small basic damage")
	_check(state.is_super(6) and not state.is_super(5), "6+ is the super")
	_check(six < Rules.MONSTER_HP, "one chain hit does not erase a fresh monster")
	_check(Rules.BASIC_DAMAGE * 3 < Rules.MONSTER_HP, "a few basic hits do not pop a monster")


func _test_weapons() -> void:
	_check(Rules.KNIFE_INTERVAL == 2.0, "the knife fires every 2 seconds")
	_check(Rules.BOOK_INTERVAL == 5.0, "the spellbook fires every 5 seconds")
	_check(Rules.BOW_INTERVAL == 3.5, "the vine bow fires every 3.5 seconds")
	_check(Rules.TALISMAN_INTERVAL == 4.0, "the talisman fires every 4 seconds")
	_check(Rules.KNIFE_SEQUENCE == [0, 0, 3], "knife sequence is red red purple")
	_check(Rules.BOOK_SEQUENCE == [1, 1, 1, 4, 4, 3, 3], "book sequence is three blue, two white, two purple")
	_check(Rules.BOW_SEQUENCE == [2, 2, 2, 4], "bow sequence is green green green white")
	_check(Rules.TALISMAN_SEQUENCE == [3, 3, 0, 4], "talisman sequence is purple purple red white")
	var state = Rules.new()
	state.start_run(1)
	_check(state.owned_ids() == ["knife"], "a run starts with the knife only")
	state.apply_level("book")
	state.apply_level("bow")
	_check(state.owns("book") and state.owns("bow") and state.owns("knife"), "a run can hold more than one weapon")
	_check(_near(state.weapon_interval("bow"), 3.5), "the bow keeps its own interval")
	state.apply_level("rapid")
	_check(_near(state.weapon_interval("knife"), 2.0 * 0.85), "rapid fire shortens every weapon")
	_check(not state.owns("talisman"), "the talisman is still a level-up pickup")
	state.apply_level("talisman")
	_check(state.owns("talisman") and state.owned_ids().size() == 4, "all four weapons can be held together")
	_check(_near(state.weapon_interval("talisman"), 4.0 * 0.85), "the talisman uses the shared fire rate once owned")


func _test_cluster() -> void:
	var reds: Array = [
		{"col": 5, "row": 0, "color": 0},
		{"col": 6, "row": 0, "color": 0},
		{"col": 5, "row": 1, "color": 0},
	]
	var group: Array = Rules.same_color_component(reds, 0)
	_check(group.size() == 3, "three touching bubbles of one color connect, including diagonally on the hex")
	var bent: Array = [
		{"col": 4, "row": 2, "color": 2},
		{"col": 5, "row": 2, "color": 2},
		{"col": 5, "row": 3, "color": 2},
	]
	_check(Rules.same_color_component(bent, 0).size() == 3, "the link can turn")
	var gap: Array = [
		{"col": 1, "row": 0, "color": 0},
		{"col": 2, "row": 0, "color": 1},
		{"col": 3, "row": 0, "color": 0},
	]
	_check(Rules.same_color_component(gap, 0).size() == 1, "a different color does not bridge a chain")
	var apart: Array = [
		{"col": 0, "row": 0, "color": 3},
		{"col": 2, "row": 0, "color": 3},
	]
	_check(Rules.same_color_component(apart, 0).size() == 1, "a gap does not connect")
	var ceiling: Array = [
		{"col": 0, "row": 0, "color": 1},
		{"col": 0, "row": 1, "color": 2},
		{"col": 4, "row": 3, "color": 0},
	]
	var floating: Array = Rules.floating_indices(ceiling)
	_check(floating.size() == 1 and int(floating[0]) == 2, "a bubble that lost the ceiling falls")
	var hung: Array = [
		{"col": 1, "row": 0, "color": 0},
		{"col": 1, "row": 1, "color": 3},
	]
	_check(Rules.floating_indices(hung).is_empty(), "anything still touching the ceiling stays")


func _test_levels() -> void:
	var state = Rules.new()
	state.start_run(9)
	_check(state.note_pops(11) == 0, "eleven pops are not yet a level")
	_check(state.note_pops(1) == 1, "the twelfth pop levels up")
	_check(state.level == 2 and state.pops_needed == 16 and state.pops_toward == 0, "the next stretch asks for four more pops")
	state.roll_level()
	_check(state.level_stock.size() == 3, "three choices")
	_check(str(state.level_stock[0]) == "book", "an unowned weapon is offered until taken")
	var seen := {}
	for id in state.level_stock:
		_check(Rules.LEVEL_UPS.has(str(id)), "choice exists")
		_check(not seen.has(str(id)), "choices are distinct")
		seen[str(id)] = true
	state.apply_level("power")
	_check(_near(state.spell_power, 1.15), "power lasts the run")
	state.apply_level("heavy")
	_check(_near(state.basic_amount(), Rules.BASIC_DAMAGE + 10.0), "heavy raises basic damage")
	_check(_near(state.spell_power, 1.25), "heavy also raises chain damage")
	state.apply_level("wide")
	_check(state.chain_need == 2, "wide lowers the chain size")
	_check(_near(float(state.chain_damage(2)), state.spell_power * Rules.CHAIN_BASE), "a 2-chain counts after wide")
	_check(float(state.chain_damage(1)) == 0.0, "one bubble is still not a chain")
	state.apply_level("book")
	state.roll_level()
	_check(str(state.level_stock[0]) == "bow", "the next unowned weapon is offered next")
	_check(not state.level_stock.has("book"), "the book is not offered twice")
	state.apply_level("bow")
	state.apply_level("talisman")
	state.roll_level()
	for id in state.level_stock:
		_check(not state.is_weapon(str(id)), "owned weapons leave the offer")
	state.start_run(9)
	_check(state.level == 1 and state.owned_ids() == ["knife"] and state.spell_power == 1.0 and state.chain_need == 3 and state.pops == 0, "a new run clears the picks")


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.02


func _check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)
		print("FAIL ", message)
