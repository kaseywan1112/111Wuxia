extends SceneTree

const Rules = preload("res://scripts/run_state.gd")
const Gear = preload("res://scripts/gear.gd")

var errors: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_hits()
	_test_relics()
	_test_sets()
	_test_save()
	if errors.is_empty():
		print("SIM_OK")
		quit(0)
	for err in errors:
		print("FAIL ", err)
	quit(1)


func _test_hits() -> void:
	var gear := Gear.new()
	gear.reset_new()
	var state := Rules.new()
	state.begin_run(gear, 3)
	var same := state.same_damage()
	var chain := state.chain_damage()
	var basic := state.basic_damage()
	_check(same == Rules.SAME_BASE, "a same-color hit is the big hit")
	_check(chain == Rules.CHAIN_BASE, "other monsters of that color take the chain hit")
	_check(basic == Rules.BASIC_BASE, "a different color is only basic damage")
	_check(basic < same * 0.5, "basic damage stays well under the same-color hit")
	_check(same < Rules.MONSTER_HP and same * 2.0 > Rules.MONSTER_HP, "two same-color hits fell a fresh monster")
	_check(chain < Rules.MONSTER_HP, "one chain hit does not erase a fresh monster")
	_check(state.attack_kind == "melee" and state.attack_color == 0, "a new fighter starts with the red knife")
	_check(state.projectile_count() == 1, "the knife does not throw extra shots")


func _test_relics() -> void:
	var gear := Gear.new()
	gear.reset_new()
	var state := Rules.new()
	state.begin_run(gear, 4)
	_check(state.note_kills(7) == 0, "seven kills are not yet a level")
	_check(state.note_kills(1) == 1, "the eighth kill levels up")
	_check(state.kills_needed == 12 and state.kills_toward == 0, "the next stretch asks for four more kills")
	state.roll_level()
	_check(state.level_stock.size() == 3, "three relic choices")
	var seen := {}
	for id in state.level_stock:
		_check(Rules.RELICS.has(str(id)), "relic exists")
		_check(not seen.has(str(id)), "relics are distinct")
		seen[str(id)] = true
	var before := state.same_damage()
	state.apply_relic("power")
	_check(_near(state.same_damage() / before, 1.15), "猛击 raises damage for the run")
	_check(_near(state.basic_damage(), Rules.BASIC_BASE * 1.15), "猛击 also raises basic damage")
	var gap := state.attack_interval()
	state.apply_relic("haste")
	_check(_near(state.attack_interval() / gap, 0.85), "疾射 shortens the attack interval")
	var chain_before := state.chain_damage()
	state.apply_relic("chain")
	_check(_near(state.chain_damage() / chain_before, 1.25), "连锁 raises chain damage")
	state.apply_relic("extra")
	_check(state.melee_arc() > 1.05, "双发 widens a melee swing")
	var reach := state.melee_reach()
	state.apply_relic("reach")
	_check(_near(state.melee_reach() / reach, 1.4), "长刃 extends melee reach")
	state.begin_run(gear, 4)
	_check(state.relic_power == 0 and state.kills == 0 and state.level == 1, "a new run clears relics")


func _test_sets() -> void:
	var gear := Gear.new()
	gear.reset_new()
	_check(not gear.set_active("flame"), "one piece is not a set")
	gear.add_item("flame_bow")
	gear.add_item("flame_armor")
	gear.equip("flame_bow")
	_check(gear.set_count("flame") == 1 and not gear.set_active("flame"), "the bow alone does not light the set")
	gear.equip("flame_armor")
	_check(gear.set_active("flame"), "two 赤焰 pieces grant the bonus")
	_check(_near(gear.same_factor(), 1.30), "赤焰 raises same-color damage")
	_check(_near(gear.damage_factor(), 1.10), "赤焰甲 adds its own damage")
	var state := Rules.new()
	state.begin_run(gear, 1)
	_check(state.attack_kind == "ranged" and state.attack_color == 0, "the flame bow fires red shots")
	_check(state.projectile_count() == 1, "the flame set does not add a side shot")
	_check(_near(state.same_damage(), Rules.SAME_BASE * 1.10 * 1.30), "equipped 赤焰 stacks the armor and the set")
	gear.add_item("frost_sword")
	gear.add_item("frost_charm")
	gear.equip("frost_sword")
	gear.equip("frost_charm")
	_check(gear.set_active("frost") and not gear.set_active("flame"), "equipping another weapon drops the old set")
	_check(_near(gear.rate_factor(), 0.90 * 0.80), "寒铁 charm and set both speed attacks")
	_check(gear.attack_kind() == "melee" and gear.attack_color() == 1, "the frost sword is a blue melee weapon")
	gear.add_item("vine_bow")
	gear.add_item("vine_armor")
	gear.equip("vine_bow")
	gear.equip("vine_armor")
	_check(gear.set_active("vine") and gear.extra_projectiles() == 1, "two 青藤 pieces add a side shot")
	_check(gear.attack_color() == 2 and gear.attack_kind() == "ranged", "the vine bow fires green shots")


func _test_save() -> void:
	var path := "user://xiaochu_gear_test.cfg"
	var gear := Gear.new()
	gear.reset_new()
	gear.add_item("vine_bow")
	gear.add_item("vine_armor")
	gear.equip("vine_bow")
	gear.equip("vine_armor")
	gear.save_to(path)
	var loaded := Gear.new()
	loaded.reset_new()
	_check(loaded.load_from(path), "gear file loads")
	_check(loaded.weapon_id == "vine_bow" and loaded.armor_id == "vine_armor", "equipped pieces come back")
	_check(loaded.set_active("vine") and loaded.owns("plain"), "the set and the starter both persist")
	var state := Rules.new()
	state.begin_run(loaded, 8)
	state.apply_relic("power")
	_check(loaded.set_active("vine") and loaded.weapon_id == "vine_bow", "a finished run does not strip the gear")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.02


func _check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)
		print("FAIL ", message)
