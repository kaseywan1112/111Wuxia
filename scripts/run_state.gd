extends RefCounted

## Extraction run. Carried gear and gold are not kept until secured or extracted.

const SAVE_PATH := "user://extract_stash.cfg"

const WEAPONS := {
	"chain": {
		"name": "连弹",
		"damage": 22.0,
		"speed": 540.0,
		"damp": 1.0,
		"bounces": -1,
		"life": 5.5,
		"catch": false,
	},
	"return": {
		"name": "回手",
		"damage": 16.0,
		"speed": 400.0,
		"damp": 0.99,
		"bounces": -1,
		"life": -1.0,
		"catch": true,
	},
	"hammer": {
		"name": "重锤",
		"damage": 48.0,
		"speed": 250.0,
		"damp": 0.55,
		"bounces": 3,
		"life": 4.0,
		"catch": false,
	},
}

const WEAPON_ORDER: Array[String] = ["chain", "return", "hammer"]

const GEAR := {
	"hide": {"name": "皮甲", "slot": "护甲", "desc": "挨打时少掉 2 点生命。"},
	"ring": {"name": "铜戒", "slot": "饰品", "desc": "球的伤害 +4。"},
	"jade": {"name": "玉佩", "slot": "饰品", "desc": "每个金币堆再多 2 枚。"},
	"helm": {"name": "铁盔", "slot": "头盔", "desc": "生命上限 +12。"},
}

const GEAR_ORDER: Array[String] = ["hide", "ring", "jade", "helm"]

var rng := RandomNumberGenerator.new()
var seed_value: int = 1
var weapon: String = "chain"
var owned_weapons: Array[String] = ["chain"]
var carried: Array[String] = []
var backpack: String = ""
var run_gold: int = 0
var stash: Array[String] = []
var stash_gold: int = 0
var area: int = 1
var step: int = 0
var gear_forced: int = 0
var run_kills: int = 0
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
	weapon = "chain"
	carried = []
	backpack = ""
	run_gold = 0
	area = 1
	step = 0
	gear_forced = 0
	_clear_run_growth()


func weapon_name(id: String = "") -> String:
	var key := id if id != "" else weapon
	if not WEAPONS.has(key):
		return "连弹"
	return str(WEAPONS[key]["name"])


func weapon_damage() -> float:
	return float(WEAPONS[weapon]["damage"]) + _ring_bonus() + float(run_damage) + _stash_damage()


func weapon_speed() -> float:
	return float(WEAPONS[weapon]["speed"]) * (1.0 + float(run_rate) * 0.12)


func weapon_damp() -> float:
	return float(WEAPONS[weapon]["damp"])


func weapon_bounces() -> int:
	var bounces := int(WEAPONS[weapon]["bounces"])
	if bounces < 0:
		return -1
	return bounces + run_bounce


func weapon_life() -> float:
	var life := float(WEAPONS[weapon]["life"])
	if life > 0.0:
		return life + float(run_bounce) * 0.8
	return life


func refire_delay() -> float:
	return maxf(0.08, 0.5 - float(run_rate) * 0.14)


func catch_gold() -> int:
	return 8 + run_catch * 4


func weapon_needs_catch() -> bool:
	return bool(WEAPONS[weapon]["catch"])


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


func roll_gear(force: bool) -> String:
	if not force and rng.randf() > 0.42:
		return ""
	return GEAR_ORDER[rng.randi() % GEAR_ORDER.size()]


func note_forced_drop() -> bool:
	if gear_forced >= 2:
		return false
	gear_forced += 1
	return true


func pickup_gear(id: String) -> void:
	if GEAR.has(id):
		carried.append(id)


func pickup_gold(amount: int) -> void:
	run_gold += amount


func secure_first() -> String:
	if backpack != "" or carried.is_empty():
		return ""
	var id := str(carried[0])
	carried.remove_at(0)
	backpack = id
	return id


func extract() -> Dictionary:
	var items: Array[String] = []
	for id in carried:
		var kept := str(id)
		items.append(kept)
		_bank_gear(kept)
	if backpack != "":
		items.append(backpack)
		_bank_gear(backpack)
	var gold := run_gold
	stash_gold += run_gold
	carried = []
	backpack = ""
	run_gold = 0
	_clear_run_growth()
	return {"items": items, "gold": gold}


func fail_run() -> Dictionary:
	var lost: Array[String] = []
	for id in carried:
		lost.append(str(id))
	var lost_gold := run_gold
	var kept := backpack
	if backpack != "":
		_bank_gear(backpack)
	carried = []
	backpack = ""
	run_gold = 0
	_clear_run_growth()
	return {"lost": lost, "lost_gold": lost_gold, "kept": kept}


func current_room() -> String:
	var schedule := _schedule()
	return str(schedule[step])


func advance() -> void:
	step += 1
	if step >= _schedule().size():
		area += 1
		step = 0


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
		return "多弹一下"
	if id == "catch":
		return "接球金币更多"
	if id == "rate":
		return "射速加快"
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
	stash_gold += 8
	return 8


func _schedule() -> Array:
	if area <= 1:
		return ["fight", "rest", "fight", "boss", "rest"]
	return ["fight", "fight", "boss", "rest"]


func _ring_bonus() -> float:
	if _holding("ring"):
		return 4.0
	return 0.0


func _jade_bonus() -> int:
	if _holding("jade"):
		return 2
	return 0


func armor_reduction() -> int:
	var reduction := 0
	if _holding("hide"):
		reduction += 2
	_sync_stash()
	for i in stash.size():
		if str(stash[i]) == "hide":
			reduction += 1 + stash_level[i]
	return reduction


func bonus_hp() -> int:
	var extra := 0
	if _holding("helm"):
		extra += 12
	_sync_stash()
	for i in stash.size():
		if str(stash[i]) == "helm":
			extra += 4 + stash_level[i] * 4
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
		gear_names.append("%s:%d:%s" % [str(stash[i]), stash_level[i], stash_gem[i]])
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
			stash_level.append(level)
			stash_gem.append(gem)
	stash_gold = int(file.get_value("stash", "gold", 0))
	owned_weapons = ["chain"]
	var weapon_text := str(file.get_value("stash", "weapons", "chain"))
	for part in weapon_text.split(",", false):
		var id := str(part)
		if WEAPONS.has(id) and not owned_weapons.has(id):
			owned_weapons.append(id)
	talents = []
	var talent_text := str(file.get_value("stash", "talents", ""))
	if talent_text != "":
		for part in talent_text.split(",", false):
			var id := str(part)
			if TALENTS.has(id) and not talents.has(id):
				talents.append(id)
	return true


func _bank_gear(id: String) -> void:
	stash.append(id)
	stash_level.append(0)
	stash_gem.append("")


func _sync_stash() -> void:
	while stash_level.size() < stash.size():
		stash_level.append(0)
	while stash_gem.size() < stash.size():
		stash_gem.append("")
	while stash_level.size() > stash.size():
		stash_level.remove_at(stash_level.size() - 1)
	while stash_gem.size() > stash.size():
		stash_gem.remove_at(stash_gem.size() - 1)


func _clear_run_growth() -> void:
	run_kills = 0
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
			bonus += 2.0
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
			bonus += 1
		if stash_gem[i] == "gold":
			bonus += 2
	if talents.has("eye"):
		bonus += 2
	return bonus
