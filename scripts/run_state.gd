extends RefCounted

## One-screen bubble run. A connected group of 3+ deals chain damage to every
## monster of that color. Length 6+ is the super. Level picks last this run only.

const MIN_CHAIN := 3
const SUPER_AT := 6
const STEP_MULT := 1.15
const CHAIN_BASE := 40.0
const BASIC_DAMAGE := 12.0
const MONSTER_HP := 96.0
const KNIFE_INTERVAL := 2.0
const BOOK_INTERVAL := 5.0
const BOW_INTERVAL := 3.5
const TALISMAN_INTERVAL := 4.0
const FIRST_POPS := 12

const COLOR_NAMES: Array[String] = ["红", "蓝", "绿", "紫", "白"]
const SCHOOL_NAMES: Array[String] = ["火焰爆发", "冰冻", "藤蔓", "闪电", "白宝石"]
const GEM_COLORS: Array[Color] = [
	Color("e85d4c"),
	Color("3d9ee0"),
	Color("5cbf6a"),
	Color("b07be0"),
	Color("f4f1ea"),
]

const KNIFE_SEQUENCE: Array[int] = [0, 0, 3]
const BOOK_SEQUENCE: Array[int] = [1, 1, 1, 4, 4, 3, 3]
const BOW_SEQUENCE: Array[int] = [2, 2, 2, 4]
const TALISMAN_SEQUENCE: Array[int] = [3, 3, 0, 4]
const WEAPON_ORDER: Array[String] = ["knife", "book", "bow", "talisman"]
const WEAPON_OFFER: Array[String] = ["book", "bow", "talisman"]

const LEVEL_UPS := {
	"book": {"name": "法术书", "desc": "拿上法术书。每 5 秒连射蓝、蓝、蓝、白、白、紫、紫。"},
	"bow": {"name": "藤弓", "desc": "拿上藤弓。每 3.5 秒连射绿、绿、绿、白。"},
	"talisman": {"name": "雷符", "desc": "拿上雷符。每 4 秒连射紫、紫、红、白。"},
	"haste": {"name": "快刀", "desc": "飞刀的发射间隔缩短 0.3 秒。"},
	"rapid": {"name": "疾射", "desc": "每件武器的发射间隔缩短 15%。"},
	"power": {"name": "连锁增幅", "desc": "同色连锁伤害 +15%。"},
	"heavy": {"name": "重击", "desc": "基础伤害 +10，连锁伤害再 +10%。"},
	"wide": {"name": "宽链", "desc": "连锁所需的同色数量少 1 颗，最少 2 颗。"},
	"fire": {"name": "爆裂", "desc": "火焰爆发的范围和伤害提高。"},
	"freeze": {"name": "凝霜", "desc": "冰冻让整团气泡停得更久。"},
	"vine": {"name": "蔓延", "desc": "藤蔓会伤到旁边的怪物。"},
	"bolt": {"name": "引雷", "desc": "闪电多跳一个目标。"},
	"white": {"name": "白玉", "desc": "白宝石还会立刻缩短武器冷却。"},
}

var seed_value: int = 1
var rng := RandomNumberGenerator.new()
var spell_power: float = 1.0
var knife_interval: float = KNIFE_INTERVAL
var rate_scale: float = 1.0
var basic_bonus: float = 0.0
var chain_need: int = MIN_CHAIN
var owned: Array[String] = ["knife"]
var fire_bonus: float = 0.0
var freeze_bonus: float = 0.0
var vine_bonus: float = 0.0
var lightning_jumps: int = 0
var white_haste: bool = false
var level: int = 1
var pops: int = 0
var pops_toward: int = 0
var pops_needed: int = FIRST_POPS
var wave: int = 1
var level_stock: Array[String] = []


func start_run(new_seed: int) -> void:
	seed_value = new_seed if new_seed != 0 else 1
	rng.seed = seed_value
	spell_power = 1.0
	knife_interval = KNIFE_INTERVAL
	rate_scale = 1.0
	basic_bonus = 0.0
	chain_need = MIN_CHAIN
	owned = ["knife"]
	fire_bonus = 0.0
	freeze_bonus = 0.0
	vine_bonus = 0.0
	lightning_jumps = 0
	white_haste = false
	level = 1
	pops = 0
	pops_toward = 0
	pops_needed = FIRST_POPS
	wave = 1
	level_stock = []


func level_text() -> String:
	return "等级 %d  ·  %d/%d" % [level, pops_toward, pops_needed]


func chain_damage(length: int) -> float:
	if length < chain_need:
		return 0.0
	return CHAIN_BASE * spell_power * pow(STEP_MULT, float(length - chain_need))


func basic_amount() -> float:
	return BASIC_DAMAGE + basic_bonus


func is_weapon(id: String) -> bool:
	return WEAPON_ORDER.has(id)


func owns(id: String) -> bool:
	return owned.has(id)


func owned_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in WEAPON_ORDER:
		if owns(id):
			ids.append(id)
	return ids


func weapon_interval(id: String) -> float:
	var base := KNIFE_INTERVAL
	match id:
		"knife":
			base = knife_interval
		"book":
			base = BOOK_INTERVAL
		"bow":
			base = BOW_INTERVAL
		"talisman":
			base = TALISMAN_INTERVAL
	return maxf(base * rate_scale, 0.55)


func weapon_sequence(id: String) -> Array:
	match id:
		"book":
			return BOOK_SEQUENCE
		"bow":
			return BOW_SEQUENCE
		"talisman":
			return TALISMAN_SEQUENCE
		_:
			return KNIFE_SEQUENCE


func weapon_line() -> String:
	var names: PackedStringArray = []
	for id in owned_ids():
		names.append(str(LEVEL_UPS[id]["name"]) if id != "knife" else "飞刀")
	return "  ·  ".join(names)


func is_super(length: int) -> bool:
	return length >= SUPER_AT


## Each call adds popped bubbles. Returns how many level-ups that earned.
func note_pops(count: int) -> int:
	if count <= 0:
		return 0
	pops += count
	pops_toward += count
	var gained := 0
	while pops_toward >= pops_needed:
		pops_toward -= pops_needed
		level += 1
		pops_needed += 4
		gained += 1
	return gained


func roll_level() -> void:
	var upgrades: Array[String] = []
	for key in LEVEL_UPS.keys():
		var id := str(key)
		if is_weapon(id):
			continue
		upgrades.append(id)
	var pending := _unowned_weapons()
	if pending.is_empty():
		level_stock = _pick_from(upgrades, 3)
		return
	var forced := pending[0]
	var pool: Array[String] = upgrades.duplicate()
	for id in pending:
		if id != forced:
			pool.append(id)
	level_stock = [forced]
	for id in _pick_from(pool, 2):
		level_stock.append(id)


func _unowned_weapons() -> Array[String]:
	var pending: Array[String] = []
	for id in WEAPON_OFFER:
		if not owns(id):
			pending.append(id)
	return pending


func apply_level(id: String) -> void:
	if is_weapon(id):
		if not owns(id):
			owned.append(id)
		return
	match id:
		"haste":
			knife_interval = maxf(knife_interval - 0.3, 0.8)
		"rapid":
			rate_scale *= 0.85
		"power":
			spell_power += 0.15
		"heavy":
			basic_bonus += 10.0
			spell_power += 0.10
		"wide":
			chain_need = maxi(chain_need - 1, 2)
		"fire":
			fire_bonus += 0.55
		"freeze":
			freeze_bonus += 0.8
		"vine":
			vine_bonus += 16.0
		"bolt":
			lightning_jumps += 1
		"white":
			white_haste = true


func apply_white(length: int) -> String:
	var cut := 0.8
	if is_super(length):
		cut = 2.2
	if white_haste:
		cut += 0.6
	return "冷却 -%.1f 秒" % cut


func white_cooldown_cut(length: int) -> float:
	var cut := 2.2 if is_super(length) else 0.8 as float
	if white_haste:
		cut += 0.6
	return cut


static func row_width(row: int, cols: int) -> int:
	return cols if row % 2 == 0 else cols - 1


static func neighbors(col: int, row: int) -> Array:
	var deltas: Array
	if row % 2 == 0:
		deltas = [[-1, 0], [1, 0], [-1, -1], [0, -1], [-1, 1], [0, 1]]
	else:
		deltas = [[-1, 0], [1, 0], [0, -1], [1, -1], [0, 1], [1, 1]]
	var out: Array = []
	for pair in deltas:
		out.append(Vector2i(col + int(pair[0]), row + int(pair[1])))
	return out


static func same_color_component(cells: Array, start: int) -> Array:
	if start < 0 or start >= cells.size():
		return []
	var origin: Dictionary = cells[start]
	var color := int(origin["color"])
	var index_at := {}
	for i in cells.size():
		var cell: Dictionary = cells[i]
		index_at[_key(int(cell["col"]), int(cell["row"]))] = i
	var seen := {}
	var stack: Array = [start]
	var found: Array[int] = []
	seen[start] = true
	while not stack.is_empty():
		var current := int(stack.pop_back())
		found.append(current)
		var cell: Dictionary = cells[current]
		for npos in neighbors(int(cell["col"]), int(cell["row"])):
			var spot: Vector2i = npos
			var key := _key(spot.x, spot.y)
			if not index_at.has(key):
				continue
			var next := int(index_at[key])
			if seen.has(next):
				continue
			if int(cells[next]["color"]) != color:
				continue
			seen[next] = true
			stack.append(next)
	return found


static func floating_indices(cells: Array) -> Array:
	var index_at := {}
	var stack: Array = []
	var seen := {}
	for i in cells.size():
		var cell: Dictionary = cells[i]
		index_at[_key(int(cell["col"]), int(cell["row"]))] = i
		if int(cell["row"]) == 0:
			stack.append(i)
			seen[i] = true
	while not stack.is_empty():
		var current := int(stack.pop_back())
		var cell: Dictionary = cells[current]
		for npos in neighbors(int(cell["col"]), int(cell["row"])):
			var spot: Vector2i = npos
			var key := _key(spot.x, spot.y)
			if not index_at.has(key):
				continue
			var next := int(index_at[key])
			if seen.has(next):
				continue
			seen[next] = true
			stack.append(next)
	var floating: Array[int] = []
	for i in cells.size():
		if not seen.has(i):
			floating.append(i)
	return floating


static func _key(col: int, row: int) -> String:
	return "%d:%d" % [col, row]


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
