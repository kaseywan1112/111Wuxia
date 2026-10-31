extends RefCounted

## Equipment that survives between runs. Two equipped pieces of a set grant a bonus.

const SAVE_PATH := "user://xiaochu_gear.cfg"

const SETS := {
	"flame": {"name": "赤焰", "bonus": "同色伤害 +30%"},
	"frost": {"name": "寒铁", "bonus": "攻击间隔 -20%"},
	"vine": {"name": "青藤", "bonus": "远程多一发侧向弹"},
}

const ITEMS := {
	"plain": {
		"name": "朴刀", "slot": "weapon", "set": "", "kind": "melee",
		"color": 0, "interval": 0.42, "reach": 250.0,
		"desc": "近战。打红色是重击。没有套装。",
	},
	"flame_bow": {
		"name": "赤焰弓", "slot": "weapon", "set": "flame", "kind": "ranged",
		"color": 0, "interval": 0.48, "reach": 0.0,
		"desc": "远程。红色。赤焰。",
	},
	"flame_armor": {
		"name": "赤焰甲", "slot": "armor", "set": "flame", "kind": "",
		"color": -1, "interval": 0.0, "reach": 0.0,
		"desc": "护甲。伤害 +10%。赤焰。",
	},
	"frost_sword": {
		"name": "寒铁剑", "slot": "weapon", "set": "frost", "kind": "melee",
		"color": 1, "interval": 0.62, "reach": 270.0,
		"desc": "近战。蓝色。挥得更远。寒铁。",
	},
	"frost_charm": {
		"name": "寒铁坠", "slot": "trinket", "set": "frost", "kind": "",
		"color": -1, "interval": 0.0, "reach": 0.0,
		"desc": "饰品。攻击间隔 -10%。寒铁。",
	},
	"vine_bow": {
		"name": "青藤弓", "slot": "weapon", "set": "vine", "kind": "ranged",
		"color": 2, "interval": 0.56, "reach": 0.0,
		"desc": "远程。绿色。青藤。",
	},
	"vine_armor": {
		"name": "青藤甲", "slot": "armor", "set": "vine", "kind": "",
		"color": -1, "interval": 0.0, "reach": 0.0,
		"desc": "护甲。青藤。",
	},
}

const SLOT_ORDER: Array[String] = ["weapon", "armor", "trinket"]
const SLOT_NAMES := {"weapon": "武器", "armor": "护甲", "trinket": "饰品"}
const LOOT: Array[String] = ["flame_bow", "flame_armor", "frost_sword", "frost_charm", "vine_bow", "vine_armor"]
const SET_ORDER: Array[String] = ["flame", "frost", "vine"]

var owned: Array[String] = ["plain"]
var weapon_id: String = "plain"
var armor_id: String = ""
var trinket_id: String = ""


func reset_new() -> void:
	owned = ["plain"]
	weapon_id = "plain"
	armor_id = ""
	trinket_id = ""


func owns(id: String) -> bool:
	return owned.has(id)


func add_item(id: String) -> void:
	if ITEMS.has(id) and not owns(id):
		owned.append(id)


func equip(id: String) -> void:
	if not owns(id) or not ITEMS.has(id):
		return
	var slot := str(ITEMS[id]["slot"])
	match slot:
		"weapon":
			weapon_id = id
		"armor":
			armor_id = id
		"trinket":
			trinket_id = id


func equipped_id(slot: String) -> String:
	match slot:
		"weapon":
			return weapon_id
		"armor":
			return armor_id
		"trinket":
			return trinket_id
	return ""


func item_name(id: String) -> String:
	if not ITEMS.has(id):
		return "空"
	return str(ITEMS[id]["name"])


func set_count(set_id: String) -> int:
	var n := 0
	for id in [weapon_id, armor_id, trinket_id]:
		if id == "":
			continue
		if str(ITEMS[id]["set"]) == set_id:
			n += 1
	return n


func set_active(set_id: String) -> bool:
	return set_count(set_id) >= 2


func attack_kind() -> String:
	if weapon_id == "" or not ITEMS.has(weapon_id):
		return "melee"
	return str(ITEMS[weapon_id]["kind"])


func attack_color() -> int:
	if weapon_id == "" or not ITEMS.has(weapon_id):
		return 0
	return int(ITEMS[weapon_id]["color"])


func attack_interval() -> float:
	if weapon_id == "" or not ITEMS.has(weapon_id):
		return 0.42
	return float(ITEMS[weapon_id]["interval"])


func attack_reach() -> float:
	if weapon_id == "" or not ITEMS.has(weapon_id):
		return 250.0
	return float(ITEMS[weapon_id]["reach"])


func damage_factor() -> float:
	if armor_id == "flame_armor":
		return 1.10
	return 1.0


func rate_factor() -> float:
	var factor := 1.0
	if trinket_id == "frost_charm":
		factor *= 0.90
	if set_active("frost"):
		factor *= 0.80
	return factor


func extra_projectiles() -> int:
	if set_active("vine"):
		return 1
	return 0


func same_factor() -> float:
	if set_active("flame"):
		return 1.30
	return 1.0


func unowned_loot() -> Array[String]:
	var pool: Array[String] = []
	for id in LOOT:
		if not owns(id):
			pool.append(id)
	return pool


func set_partner() -> String:
	for set_id in SET_ORDER:
		var piece := ""
		var count := 0
		for id in LOOT:
			if str(ITEMS[id]["set"]) != set_id:
				continue
			if owns(id):
				count += 1
			elif piece == "":
				piece = id
		if count == 1 and piece != "":
			return piece
	return ""


func try_drop(rng: RandomNumberGenerator, force: bool) -> String:
	var pool := unowned_loot()
	if pool.is_empty():
		return ""
	if not force and rng.randf() > 0.34:
		return ""
	var partner := set_partner()
	if partner != "" and rng.randf() < 0.55:
		return partner
	return pool[rng.randi() % pool.size()]


func save() -> void:
	save_to(SAVE_PATH)


func load_default() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		load_from(SAVE_PATH)


func save_to(path: String) -> void:
	var file := ConfigFile.new()
	var names := PackedStringArray()
	for id in owned:
		names.append(id)
	file.set_value("gear", "owned", ",".join(names))
	file.set_value("gear", "weapon", weapon_id)
	file.set_value("gear", "armor", armor_id)
	file.set_value("gear", "trinket", trinket_id)
	file.save(path)


func load_from(path: String) -> bool:
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return false
	reset_new()
	owned.clear()
	var text := str(file.get_value("gear", "owned", "plain"))
	for part in text.split(",", false):
		var id := str(part)
		if ITEMS.has(id) and not owned.has(id):
			owned.append(id)
	if not owns("plain"):
		owned.append("plain")
	weapon_id = str(file.get_value("gear", "weapon", "plain"))
	armor_id = str(file.get_value("gear", "armor", ""))
	trinket_id = str(file.get_value("gear", "trinket", ""))
	if not owns(weapon_id):
		weapon_id = "plain"
	if armor_id != "" and not owns(armor_id):
		armor_id = ""
	if trinket_id != "" and not owns(trinket_id):
		trinket_id = ""
	return true
