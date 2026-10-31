extends RefCounted

## One run. Relics last until the monsters reach you. Gear is copied in at the start.

const Gear = preload("res://scripts/gear.gd")

const SAME_BASE := 50.0
const CHAIN_BASE := 24.0
const BASIC_BASE := 16.0
const MONSTER_HP := 84.0
const FIRST_KILLS := 8

const COLOR_NAMES: Array[String] = ["红", "蓝", "绿", "紫", "白"]
const GEM_COLORS: Array[Color] = [
	Color("e85d4c"),
	Color("3d9ee0"),
	Color("5cbf6a"),
	Color("b07be0"),
	Color("f4f1ea"),
]

const RELICS := {
	"power": {"name": "猛击", "desc": "伤害 +15%。基础、同色和连锁都算。"},
	"haste": {"name": "疾射", "desc": "攻击间隔缩短 15%。"},
	"chain": {"name": "连锁", "desc": "同色连锁伤害 +25%。"},
	"extra": {"name": "双发", "desc": "远程多一发弹。近战挥击更宽。"},
	"reach": {"name": "长刃", "desc": "近战范围 +40%。"},
}

const RELIC_ORDER: Array[String] = ["power", "haste", "chain", "extra", "reach"]

var rng := RandomNumberGenerator.new()
var seed_value: int = 1
var kills: int = 0
var kills_toward: int = 0
var kills_needed: int = FIRST_KILLS
var level: int = 1
var level_stock: Array[String] = []
var relic_power: int = 0
var relic_haste: int = 0
var relic_chain: int = 0
var relic_extra: int = 0
var relic_reach: int = 0

var attack_kind: String = "melee"
var attack_color: int = 0
var weapon_name: String = "朴刀"
var base_interval: float = 0.42
var base_reach: float = 250.0
var gear_damage: float = 1.0
var gear_rate: float = 1.0
var gear_extra: int = 0
var same_scale: float = 1.0


func begin_run(gear: Gear, new_seed: int) -> void:
	seed_value = new_seed if new_seed != 0 else 1
	rng.seed = seed_value
	kills = 0
	kills_toward = 0
	kills_needed = FIRST_KILLS
	level = 1
	level_stock = []
	relic_power = 0
	relic_haste = 0
	relic_chain = 0
	relic_extra = 0
	relic_reach = 0
	attack_kind = gear.attack_kind()
	attack_color = gear.attack_color()
	weapon_name = gear.item_name(gear.weapon_id)
	base_interval = gear.attack_interval()
	base_reach = gear.attack_reach()
	gear_damage = gear.damage_factor()
	gear_rate = gear.rate_factor()
	gear_extra = gear.extra_projectiles()
	same_scale = gear.same_factor()


func level_text() -> String:
	return "等级 %d  ·  %d/%d" % [level, kills_toward, kills_needed]


func damage_mult() -> float:
	return (1.0 + 0.15 * float(relic_power)) * gear_damage


func same_damage() -> float:
	return SAME_BASE * damage_mult() * same_scale


func chain_damage() -> float:
	return CHAIN_BASE * damage_mult() * same_scale * (1.0 + 0.25 * float(relic_chain))


func basic_damage() -> float:
	return BASIC_BASE * damage_mult()


func attack_interval() -> float:
	return maxf(base_interval * gear_rate * pow(0.85, float(relic_haste)), 0.26)


func projectile_count() -> int:
	if attack_kind != "ranged":
		return 1
	return 1 + gear_extra + relic_extra


func melee_reach() -> float:
	return base_reach * (1.0 + 0.40 * float(relic_reach))


func melee_arc() -> float:
	return 1.05 + 0.32 * float(relic_extra)


func note_kills(count: int) -> int:
	if count <= 0:
		return 0
	kills += count
	kills_toward += count
	var gained := 0
	while kills_toward >= kills_needed:
		kills_toward -= kills_needed
		level += 1
		kills_needed += 4
		gained += 1
	return gained


func roll_level() -> void:
	level_stock = _pick_from(RELIC_ORDER, 3)


func apply_relic(id: String) -> void:
	match id:
		"power":
			relic_power += 1
		"haste":
			relic_haste += 1
		"chain":
			relic_chain += 1
		"extra":
			relic_extra += 1
		"reach":
			relic_reach += 1


func relic_line() -> String:
	var parts: PackedStringArray = []
	if relic_power > 0:
		parts.append("猛击%d" % relic_power)
	if relic_haste > 0:
		parts.append("疾射%d" % relic_haste)
	if relic_chain > 0:
		parts.append("连锁%d" % relic_chain)
	if relic_extra > 0:
		parts.append("双发%d" % relic_extra)
	if relic_reach > 0:
		parts.append("长刃%d" % relic_reach)
	if parts.is_empty():
		return "遗物  无"
	return "遗物  " + " ".join(parts)


func _pick_from(pool: Array[String], count: int) -> Array[String]:
	var bag: Array[String] = pool.duplicate()
	var picked: Array[String] = []
	for _n in count:
		if bag.is_empty():
			break
		var index := rng.randi() % bag.size()
		picked.append(bag[index])
		bag.remove_at(index)
	return picked
