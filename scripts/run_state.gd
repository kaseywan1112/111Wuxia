extends RefCounted

## Extraction run. Carried gear and gold are not kept until secured or extracted.

const SAVE_PATH := "user://extract_stash.cfg"

const WEAPONS := {
	"red": {"name": "直击", "color": "赤", "style": "hit", "damage": 18.0},
	"blue": {"name": "贯穿", "color": "青", "style": "pierce", "damage": 14.0},
	"green": {"name": "溅射", "color": "翠", "style": "splash", "damage": 12.0},
	"purple": {"name": "迟滞", "color": "紫", "style": "slow", "damage": 8.0},
	"gold": {"name": "护体", "color": "金", "style": "guard", "damage": 10.0},
}

const WEAPON_ORDER: Array[String] = ["red", "blue", "green", "purple", "gold"]

const GEAR := {
	"hide": {"name": "皮甲", "slot": "护甲", "desc": "挨打时少掉 2 点生命。"},
	"ring": {"name": "铜戒", "slot": "饰品", "desc": "武器伤害 +4。"},
	"jade": {"name": "玉佩", "slot": "饰品", "desc": "每个金币堆再多 2 枚。"},
	"helm": {"name": "铁盔", "slot": "头盔", "desc": "生命上限 +12。"},
}

const GEAR_ORDER: Array[String] = ["hide", "ring", "jade", "helm"]

var rng := RandomNumberGenerator.new()
var seed_value: int = 1
var weapon: String = "red"
var owned_weapons: Array[String] = ["red", "blue", "green", "purple", "gold"]
var carried: Array[String] = []
var carried_rarity: Array[int] = []
var backpack: String = ""
var backpack_rarity: int = 0
var run_gold: int = 0
var stash: Array[String] = []
var stash_rarity: Array[int] = []
var stash_gold: int = 0
var area: int = 1
var step: int = 0
var clock: float = 0.0
var beat: int = 0
var gear_forced: int = 0
var run_kills: int = 0
var run_xp: int = 0
var run_level: int = 0
var run_damage: int = 0
var run_bounce: int = 0
var run_catch: int = 0
var run_rate: int = 0
var stash_level: Array[int] = []
var stash_gem: Array[String] = []
var talents: Array[String] = []

const PICKS: Array[String] = ["damage", "bounce", "catch", "rate"]
const TALENTS: Array[String] = ["steady", "eye", "scar"]


func begin_run(new_seed: int) -> void:
	seed_value = new_seed if new_seed != 0 else 1
	rng.seed = seed_value
	weapon = "red"
	_ensure_weapons()
	carried = []
	carried_rarity = []
	backpack = ""
	backpack_rarity = 0
	run_gold = 0
	area = 1
	step = 0
	clock = 0.0
	beat = 0
	gear_forced = 0
	_clear_run_growth()


func weapon_name(id: String = "") -> String:
	var key := id if id != "" else weapon
	if not WEAPONS.has(key):
		return "直击"
	return "%s·%s" % [str(WEAPONS[key]["color"]), str(WEAPONS[key]["name"])]


func weapon_style(id: String = "") -> String:
	var key := id if id != "" else weapon
	if not WEAPONS.has(key):
		return "hit"
	return str(WEAPONS[key]["style"])


func weapon_damage(id: String = "") -> float:
	var key := id if id != "" else weapon
	var base := 18.0
	if WEAPONS.has(key):
		base = float(WEAPONS[key]["damage"])
	return base + _ring_bonus() + float(run_damage) + _stash_damage()


func weapon_id_at(color_index: int) -> String:
	var index := clampi(color_index, 0, WEAPON_ORDER.size() - 1)
	return WEAPON_ORDER[index]


func set_main_from_color(color_index: int) -> void:
	weapon = weapon_id_at(color_index)
	if not owned_weapons.has(weapon):
		owned_weapons.append(weapon)


func color_index() -> int:
	var found := WEAPON_ORDER.find(weapon)
	if found < 0:
		return 0
	return found


func burst_count(color_index: int) -> int:
	var style := weapon_style(weapon_id_at(color_index))
	if style == "splash" or style == "guard":
		return 3
	return 2


func auto_interval() -> float:
	return maxf(0.45, 1.25 - float(run_rate) * 0.18)


func extra_targets() -> int:
	return run_bounce


func guard_amount() -> int:
	return 8 + run_catch * 4


func catch_gold() -> int:
	return guard_amount()


func owns_weapon(id: String) -> bool:
	return owned_weapons.has(id)


func take_weapon(id: String) -> bool:
	if not WEAPONS.has(id):
		return false
	if not owned_weapons.has(id):
		owned_weapons.append(id)
	weapon = id
	return true


func gear_name(id: String) -> String:
	if not GEAR.has(id):
		return id
	return str(GEAR[id]["name"])


func gear_line(id: String) -> String:
	if not GEAR.has(id):
		return id
	return "%s · %s · %s" % [str(GEAR[id]["name"]), str(GEAR[id]["slot"]), str(GEAR[id]["desc"])]


const RARITY_NAMES: Array[String] = ["普通", "魔法", "稀有", "传说"]


func rarity_name(rarity: int) -> String:
	return RARITY_NAMES[clampi(rarity, 0, RARITY_NAMES.size() - 1)]


func rarity_multiplier(rarity: int) -> int:
	var scale: Array[int] = [1, 2, 3, 5]
	return scale[clampi(rarity, 0, scale.size() - 1)]


func gear_label(id: String, rarity: int = 0) -> String:
	return "%s%s" % [rarity_name(rarity), gear_name(id)]


func try_drop(boss: bool) -> bool:
	var chance := 0.2 if boss else 0.06
	return rng.randf() < chance


func roll_piece() -> String:
	return GEAR_ORDER[rng.randi() % GEAR_ORDER.size()]


func roll_rarity() -> int:
	var roll := rng.randf()
	if roll < 0.03:
		return 3
	if roll < 0.12:
		return 2
	if roll < 0.34:
		return 1
	return 0


func roll_gear(force: bool) -> String:
	if not force and not try_drop(false):
		return ""
	return roll_piece()


func note_forced_drop() -> bool:
	if gear_forced >= 2:
		return false
	gear_forced += 1
	return true


func pickup_gear(id: String, rarity: int = 0) -> void:
	if not GEAR.has(id):
		return
	carried.append(id)
	carried_rarity.append(clampi(rarity, 0, 3))


func pickup_gold(amount: int) -> void:
	run_gold += amount


func secure_first() -> String:
	_sync_carried()
	if backpack != "" or carried.is_empty():
		return ""
	var id := str(carried[0])
	backpack = id
	backpack_rarity = carried_rarity[0]
	carried.remove_at(0)
	carried_rarity.remove_at(0)
	return id


func extract() -> Dictionary:
	_sync_carried()
	var items: Array[String] = []
	for i in carried.size():
		var kept := str(carried[i])
		items.append(kept)
		_bank_gear(kept, carried_rarity[i])
	if backpack != "":
		items.append(backpack)
		_bank_gear(backpack, backpack_rarity)
	var gold := run_gold
	stash_gold += run_gold
	carried = []
	carried_rarity = []
	backpack = ""
	backpack_rarity = 0
	run_gold = 0
	_clear_run_growth()
	return {"items": items, "gold": gold}


func fail_run() -> Dictionary:
	_sync_carried()
	var lost: Array[String] = []
	for id in carried:
		lost.append(str(id))
	var lost_gold := run_gold
	var kept := backpack
	if backpack != "":
		_bank_gear(backpack, backpack_rarity)
	carried = []
	carried_rarity = []
	backpack = ""
	backpack_rarity = 0
	run_gold = 0
	_clear_run_growth()
	return {"lost": lost, "lost_gold": lost_gold, "kept": kept}


func tick(delta: float) -> String:
	if beat == 2:
		return ""
	clock += delta
	if clock < _event_limit():
		return ""
	clock = 0.0
	if beat == 0:
		beat = 1
		return "rest"
	beat = 2
	return "boss"


func seconds_left() -> float:
	if beat == 2:
		return 0.0
	return maxf(_event_limit() - clock, 0.0)


func event_name() -> String:
	if beat == 1:
		return "首领"
	if beat == 2:
		return "首领在场"
	return "休整"


func on_boss_killed() -> void:
	beat = 0
	clock = 0.0
	area += 1


func boss_leaked() -> void:
	beat = 0
	clock = 0.0


func pass_damage(boss: bool) -> int:
	var amount := 14 + (area - 1) * 4
	if boss:
		amount += 10
	return amount


func xp_to_level() -> int:
	return mini(2 + run_level, 6)


func add_xp(amount: int) -> bool:
	run_xp += amount
	if run_xp < xp_to_level():
		return false
	run_xp -= xp_to_level()
	run_level += 1
	return true


func monster_hp(boss: bool) -> float:
	var base := 20.0 + float(area - 1) * 16.0
	if boss:
		return base * 5.0
	return base


func monster_count() -> int:
	return 8 + (area - 1) * 4


func gold_per_kill() -> int:
	return 6 + (area - 1) * 2 + _jade_bonus() + _stash_gold_bonus()


func kill_quota(boss: bool) -> int:
	if boss:
		return 1
	return 6


func note_kill() -> bool:
	run_kills += 1
	return run_kills % 4 == 0


func offer_picks() -> Array[String]:
	var bag: Array[String] = []
	for id in PICKS:
		bag.append(id)
	for i in bag.size():
		var swap := rng.randi() % bag.size()
		var held := bag[i]
		bag[i] = bag[swap]
		bag[swap] = held
	var offered: Array[String] = []
	offered.append(bag[0])
	offered.append(bag[1])
	offered.append(bag[2])
	return offered


func pick_name(id: String) -> String:
	if id == "damage":
		return "伤害 +4"
	if id == "bounce":
		return "多打一个"
	if id == "catch":
		return "护体 +4"
	if id == "rate":
		return "射得更快"
	return id


func apply_pick(id: String) -> void:
	if id == "damage":
		run_damage += 4
	elif id == "bounce":
		run_bounce += 1
	elif id == "catch":
		run_catch += 1
	elif id == "rate":
		run_rate += 1


func upgrade_cost(index: int) -> int:
	_sync_stash()
	if index < 0 or index >= stash.size():
		return 0
	return 12 + stash_level[index] * 8


func upgrade_first() -> String:
	_sync_stash()
	if stash.is_empty():
		return ""
	var cost := upgrade_cost(0)
	if stash_gold < cost:
		return ""
	stash_gold -= cost
	stash_level[0] += 1
	return str(stash[0])


func socket_first(gem: String = "red") -> String:
	_sync_stash()
	if stash.is_empty() or stash_gem[0] != "":
		return ""
	if gem != "red" and gem != "blue" and gem != "gold":
		return ""
	if stash_gold < 10:
		return ""
	stash_gold -= 10
	stash_gem[0] = gem
	return str(stash[0])


func talent_cost(id: String) -> int:
	if id == "scar":
		return 24
	return 18


func talent_name(id: String) -> String:
	if id == "steady":
		return "稳手"
	if id == "eye":
		return "眼尖"
	if id == "scar":
		return "旧伤"
	return id


func buy_talent(id: String) -> bool:
	if not TALENTS.has(id) or talents.has(id):
		return false
	var cost := talent_cost(id)
	if stash_gold < cost:
		return false
	stash_gold -= cost
	talents.append(id)
	return true


func buy_next_talent() -> String:
	for id in TALENTS:
		if not talents.has(id) and buy_talent(id):
			return id
	return ""


func salvage_first() -> int:
	_sync_stash()
	if stash.is_empty():
		return 0
	stash.remove_at(0)
	stash_level.remove_at(0)
	stash_gem.remove_at(0)
	if not stash_rarity.is_empty():
		stash_rarity.remove_at(0)
	stash_gold += 8
	return 8


func _event_limit() -> float:
	if beat == 0:
		return 8.0 if area <= 1 else 16.0
	return 8.0


func _ring_bonus() -> float:
	return 4.0 * float(_carried_power("ring"))


func _jade_bonus() -> int:
	return 2 * _carried_power("jade")


func armor_reduction() -> int:
	var reduction := 2 * _carried_power("hide")
	_sync_stash()
	for i in stash.size():
		if str(stash[i]) == "hide":
			reduction += (1 + stash_level[i]) * rarity_multiplier(stash_rarity[i])
	return reduction


func bonus_hp() -> int:
	var extra := 12 * _carried_power("helm")
	_sync_stash()
	for i in stash.size():
		if str(stash[i]) == "helm":
			extra += (4 + stash_level[i] * 4) * rarity_multiplier(stash_rarity[i])
		if stash_gem[i] == "blue":
			extra += 6
	if talents.has("steady"):
		extra += 8
	return extra


func _holding(id: String) -> bool:
	if backpack == id:
		return true
	return carried.has(id)


func save() -> void:
	save_to(SAVE_PATH)


func load_default() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		load_from(SAVE_PATH)


func save_to(path: String) -> void:
	var file := ConfigFile.new()
	_sync_stash()
	var gear_names := PackedStringArray()
	for i in stash.size():
		var rarity := 0
		if i < stash_rarity.size():
			rarity = stash_rarity[i]
		gear_names.append("%s:%d:%s:%d" % [str(stash[i]), stash_level[i], stash_gem[i], rarity])
	var weapon_names := PackedStringArray()
	for id in owned_weapons:
		weapon_names.append(id)
	var talent_names := PackedStringArray()
	for id in talents:
		talent_names.append(id)
	file.set_value("stash", "gear", ",".join(gear_names))
	file.set_value("stash", "gold", stash_gold)
	file.set_value("stash", "weapons", ",".join(weapon_names))
	file.set_value("stash", "talents", ",".join(talent_names))
	file.save(path)


func load_from(path: String) -> bool:
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return false
	stash = []
	stash_level = []
	stash_gem = []
	stash_rarity = []
	var gear_text := str(file.get_value("stash", "gear", ""))
	if gear_text != "":
		for part in gear_text.split(",", false):
			var bits: PackedStringArray = str(part).split(":")
			var id := str(bits[0])
			if not GEAR.has(id):
				continue
			stash.append(id)
			var level := 0
			var gem := ""
			if bits.size() > 1:
				level = int(bits[1])
			if bits.size() > 2:
				gem = str(bits[2])
			var rarity := 0
			if bits.size() > 3:
				rarity = clampi(int(bits[3]), 0, 3)
			stash_level.append(level)
			stash_gem.append(gem)
			stash_rarity.append(rarity)
	stash_gold = int(file.get_value("stash", "gold", 0))
	owned_weapons = []
	var weapon_text := str(file.get_value("stash", "weapons", ""))
	for part in weapon_text.split(",", false):
		var id := str(part)
		if WEAPONS.has(id) and not owned_weapons.has(id):
			owned_weapons.append(id)
	_ensure_weapons()
	talents = []
	var talent_text := str(file.get_value("stash", "talents", ""))
	if talent_text != "":
		for part in talent_text.split(",", false):
			var id := str(part)
			if TALENTS.has(id) and not talents.has(id):
				talents.append(id)
	return true


func _bank_gear(id: String, rarity: int = 0) -> void:
	stash.append(id)
	stash_level.append(0)
	stash_gem.append("")
	stash_rarity.append(clampi(rarity, 0, 3))


func _sync_carried() -> void:
	while carried_rarity.size() < carried.size():
		carried_rarity.append(0)
	while carried_rarity.size() > carried.size():
		carried_rarity.remove_at(carried_rarity.size() - 1)


func _carried_power(base_id: String) -> int:
	_sync_carried()
	var total := 0
	for i in carried.size():
		if str(carried[i]) == base_id:
			total += rarity_multiplier(carried_rarity[i])
	if backpack == base_id:
		total += rarity_multiplier(backpack_rarity)
	return total


func _sync_stash() -> void:
	while stash_level.size() < stash.size():
		stash_level.append(0)
	while stash_gem.size() < stash.size():
		stash_gem.append("")
	while stash_rarity.size() < stash.size():
		stash_rarity.append(0)
	while stash_level.size() > stash.size():
		stash_level.remove_at(stash_level.size() - 1)
	while stash_gem.size() > stash.size():
		stash_gem.remove_at(stash_gem.size() - 1)
	while stash_rarity.size() > stash.size():
		stash_rarity.remove_at(stash_rarity.size() - 1)


func _ensure_weapons() -> void:
	var kept: Array[String] = []
	for id in owned_weapons:
		if WEAPONS.has(id) and not kept.has(id):
			kept.append(id)
	for id in WEAPON_ORDER:
		if not kept.has(id):
			kept.append(id)
	owned_weapons = kept


func _clear_run_growth() -> void:
	run_kills = 0
	run_xp = 0
	run_level = 0
	run_damage = 0
	run_bounce = 0
	run_catch = 0
	run_rate = 0


func _stash_damage() -> float:
	var bonus := 0.0
	_sync_stash()
	for i in stash.size():
		bonus += float(stash_level[i])
		if str(stash[i]) == "ring":
			bonus += 2.0 * float(rarity_multiplier(stash_rarity[i]))
		if stash_gem[i] == "red":
			bonus += 3.0
	if talents.has("scar"):
		bonus += 3.0
	return bonus


func _stash_gold_bonus() -> int:
	var bonus := 0
	_sync_stash()
	for i in stash.size():
		if str(stash[i]) == "jade":
			bonus += rarity_multiplier(stash_rarity[i])
		if stash_gem[i] == "gold":
			bonus += 2
	if talents.has("eye"):
		bonus += 2
	return bonus
