extends RefCounted

## Run rules for the real-time lane roguelike.
## A chain of length n deals base * 1.15^(n-3). Length 6+ is a super.
## White is a bonus, not a damage school.

const COLS := 8
const MIN_CHAIN := 3
const SUPER_AT := 6
const STEP_MULT := 1.15
const BASE_DAMAGE := 46.0
const COMBO_WINDOW := 5.0

const SCHOOLS: Array[String] = ["fire", "ice", "vine", "lightning", "white"]
const SCHOOL_NAMES: Array[String] = ["火焰", "寒冰", "藤蔓", "雷电", "白宝石"]
const GEM_COLORS: Array[Color] = [
	Color("e85d4c"),
	Color("3d9ee0"),
	Color("5cbf6a"),
	Color("b07be0"),
	Color("f4f1ea"),
]

const ROUTES: Array[Dictionary] = [
	{
		"id": "calm",
		"name": "平缓小径",
		"blurb": "两场普通战斗后才遇到精英，商店来得比较早。",
		"nodes": ["trash", "trash", "shop", "elite", "reward", "boss"],
	},
	{
		"id": "steep",
		"name": "险峻山路",
		"blurb": "精英来得更早，中途有一次免费奖赏。",
		"nodes": ["trash", "elite", "reward", "shop", "trash", "boss"],
	},
	{
		"id": "short",
		"name": "捷径",
		"blurb": "路更短，硬仗之间才有商店和奖赏。",
		"nodes": ["trash", "reward", "elite", "shop", "boss"],
	},
]

const FOES := {
	"grunt": {"hp": 700, "speed": 32.0, "touch": 8, "gold": 12, "name": "灰盗"},
	"runner": {"hp": 560, "speed": 48.0, "touch": 7, "gold": 12, "name": "疾影"},
	"elite": {"hp": 1500, "speed": 26.0, "touch": 12, "gold": 36, "name": "精英卫"},
	"boss": {"hp": 3200, "speed": 22.0, "touch": 15, "gold": 50, "name": "守关巨像"},
}

const SHOP := {
	"heal": {"name": "伤药", "desc": "恢复 28 点生命。", "price": 16},
	"power": {"name": "法术晶石", "desc": "所有法术伤害 +15%。", "price": 22},
	"freeze": {"name": "寒霜瓶", "desc": "冰冻时间额外 +0.45 秒。", "price": 20},
	"summon": {"name": "藤种", "desc": "藤灵多停留 1.4 秒。", "price": 20},
	"vital": {"name": "护符", "desc": "最大生命 +20，并恢复 20。", "price": 18},
	"tempo": {"name": "连击手套", "desc": "连击增伤提高，连击时间 +0.8 秒。", "price": 18},
}

const REWARDS := {
	"power": {"name": "法术精通", "desc": "所有法术伤害 +20%。"},
	"vital": {"name": "壮骨", "desc": "最大生命 +30，并恢复 30。"},
	"white": {"name": "白宝石矿", "desc": "棋盘上更容易出现白宝石。"},
	"tempo": {"name": "从容", "desc": "连击中断前的空窗 +1.6 秒。"},
	"purse": {"name": "钱袋", "desc": "立刻获得 30 金。"},
}

var seed_value: int = 1
var rng := RandomNumberGenerator.new()
var route_index: int = -1
var node_index: int = 0
var gold: int = 0
var hp: int = 110
var max_hp: int = 110
var spell_power: float = 1.0
var freeze_bonus: float = 0.0
var summon_bonus: float = 0.0
var combo_window_bonus: float = 0.0
var combo_step_bonus: float = 0.0
var white_weight: float = 0.1
var empower_next: bool = false
var combo: int = 0
var combo_time: float = 0.0
var shop_stock: Array[String] = []
var reward_stock: Array[String] = []


func start_run(new_seed: int) -> void:
	seed_value = new_seed if new_seed != 0 else 1
	rng.seed = seed_value
	route_index = -1
	node_index = 0
	gold = 0
	max_hp = 110
	hp = max_hp
	spell_power = 1.0
	freeze_bonus = 0.0
	summon_bonus = 0.0
	combo_window_bonus = 0.0
	combo_step_bonus = 0.0
	white_weight = 0.1
	empower_next = false
	combo = 0
	combo_time = 0.0
	shop_stock = []
	reward_stock = []


func choose_route(index: int) -> void:
	route_index = clampi(index, 0, ROUTES.size() - 1)
	node_index = 0


func current_kind() -> String:
	var nodes: Array = ROUTES[route_index]["nodes"]
	if node_index < 0 or node_index >= nodes.size():
		return ""
	return str(nodes[node_index])


func advance() -> void:
	node_index += 1


func route_done() -> bool:
	if route_index < 0:
		return false
	var nodes: Array = ROUTES[route_index]["nodes"]
	return node_index >= nodes.size()


func route_name() -> String:
	if route_index < 0:
		return ""
	return str(ROUTES[route_index]["name"])


func progress_text() -> String:
	var nodes: Array = ROUTES[route_index]["nodes"]
	return "%s  ·  第 %d / %d 关  ·  %s" % [
		route_name(),
		node_index + 1,
		nodes.size(),
		node_title(current_kind()),
	]


func trash_variant() -> int:
	var nodes: Array = ROUTES[route_index]["nodes"]
	var seen := 0
	for i in node_index:
		if str(nodes[i]) == "trash":
			seen += 1
	return seen % 2


static func node_title(kind: String) -> String:
	match kind:
		"trash":
			return "普通战斗"
		"elite":
			return "精英战斗"
		"shop":
			return "商店"
		"reward":
			return "奖赏"
		"boss":
			return "首领"
		_:
			return kind


static func route_steps_text(index: int) -> String:
	var parts := PackedStringArray()
	for kind in ROUTES[index]["nodes"]:
		parts.append(node_title(str(kind)))
	return " → ".join(parts)


func roll_color() -> int:
	if rng.randf() < clampf(white_weight, 0.02, 0.45):
		return 4
	return rng.randi_range(0, 3)


func school_of(color_index: int) -> String:
	if color_index < 0 or color_index >= SCHOOLS.size():
		return "fire"
	return SCHOOLS[color_index]


func school_name(color_index: int) -> String:
	if color_index < 0 or color_index >= SCHOOL_NAMES.size():
		return ""
	return SCHOOL_NAMES[color_index]


func spell_kind(school: String, length: int) -> String:
	if school == "white":
		if length >= SUPER_AT:
			return "loot"
		if length >= 4:
			return "empower"
		return "extra"
	if school == "ice":
		if length >= SUPER_AT:
			return "wall"
		if length >= 4:
			return "freeze"
		return "spike"
	if school == "vine":
		if length >= SUPER_AT:
			return "summon"
		if length >= 4:
			return "entangle"
		return "lash"
	if school == "lightning":
		if length >= SUPER_AT:
			return "stun"
		if length >= 4:
			return "chain"
		return "bolt"
	if length >= SUPER_AT:
		return "explosion"
	if length >= 4:
		return "burn"
	return "fireball"


func spell_title(school: String, length: int) -> String:
	match spell_kind(school, length):
		"fireball":
			return "火球"
		"burn":
			return "燃烧火球"
		"explosion":
			return "爆裂火球"
		"spike":
			return "冰刺"
		"freeze":
			return "冰封"
		"wall":
			return "冰墙"
		"lash":
			return "藤鞭"
		"entangle":
			return "缠绕"
		"summon":
			return "召唤藤灵"
		"bolt":
			return "雷击"
		"chain":
			return "连锁雷"
		"stun":
			return "眩晕雷暴"
		"extra":
			return "额外连锁"
		"empower":
			return "强化下一发"
		"loot":
			return "战利品"
		_:
			return "法术"


func length_multiplier(length: int) -> float:
	return pow(STEP_MULT, float(maxi(length, MIN_CHAIN) - MIN_CHAIN))


func combo_multiplier(level: int) -> float:
	if level <= 1:
		return 1.0
	return 1.0 + (0.10 + combo_step_bonus) * float(level - 1)


func chain_damage(length: int, combo_level: int, empowered: bool) -> float:
	if length < MIN_CHAIN:
		return 0.0
	var amount := BASE_DAMAGE * spell_power * length_multiplier(length)
	amount *= combo_multiplier(combo_level)
	if empowered:
		amount *= 1.65
	return amount


func combo_window() -> float:
	return COMBO_WINDOW + combo_window_bonus


func note_chain_success() -> void:
	combo += 1
	combo_time = combo_window()


func break_combo() -> void:
	combo = 0
	combo_time = 0.0


func roll_shop() -> void:
	shop_stock = _pick_ids(SHOP.keys(), 3)


func roll_reward() -> void:
	reward_stock = _pick_ids(REWARDS.keys(), 3)


func apply_shop(id: String) -> bool:
	if not SHOP.has(id):
		return false
	var price := int(SHOP[id]["price"])
	if gold < price:
		return false
	gold -= price
	match id:
		"heal":
			hp = mini(max_hp, hp + 28)
		"power":
			spell_power += 0.15
		"freeze":
			freeze_bonus += 0.45
		"summon":
			summon_bonus += 1.4
		"vital":
			max_hp += 20
			hp = mini(max_hp, hp + 20)
		"tempo":
			combo_step_bonus += 0.05
			combo_window_bonus += 0.8
	return true


func apply_reward(id: String) -> void:
	match id:
		"power":
			spell_power += 0.2
		"vital":
			max_hp += 30
			hp = mini(max_hp, hp + 30)
		"white":
			white_weight += 0.06
		"tempo":
			combo_window_bonus += 1.6
		"purse":
			gold += 30


func apply_white(kind: String) -> String:
	match kind:
		"extra":
			combo += 1
			combo_time = combo_window()
			return "额外连锁"
		"empower":
			empower_next = true
			return "下一发强化"
		"loot":
			gold += 25
			hp = mini(max_hp, hp + 18)
			return "战利品 +25 金，生命 +18"
		_:
			return ""


static func try_extend(path: Array, next: Vector2i, colors: Array, cols: int) -> Dictionary:
	if next.x < 0 or next.y < 0:
		return {"path": path, "action": "ignore"}
	var index := next.y * cols + next.x
	if index < 0 or index >= colors.size() or int(colors[index]) < 0:
		return {"path": path, "action": "ignore"}
	if path.is_empty():
		return {"path": [next], "action": "start"}
	if path.size() >= 2 and next == path[path.size() - 2]:
		var trimmed: Array = path.duplicate()
		trimmed.pop_back()
		return {"path": trimmed, "action": "undo"}
	if path.has(next):
		return {"path": path, "action": "ignore"}
	var last: Vector2i = path[path.size() - 1]
	if absi(last.x - next.x) + absi(last.y - next.y) != 1:
		return {"path": path, "action": "ignore"}
	var last_index := last.y * cols + last.x
	if int(colors[index]) != int(colors[last_index]):
		return {"path": path, "action": "ignore"}
	var grown: Array = path.duplicate()
	grown.append(next)
	return {"path": grown, "action": "add"}


func _pick_ids(source: Array, count: int) -> Array[String]:
	var pool: Array[String] = []
	for item in source:
		pool.append(str(item))
	var picked: Array[String] = []
	for _n in count:
		if pool.is_empty():
			break
		var index := rng.randi() % pool.size()
		picked.append(pool[index])
		pool.remove_at(index)
	return picked
