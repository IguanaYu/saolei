class_name MapGenerator
## 静态工具类：生成扫雷地图（雷位置 + 数字）

const NEIGHBOR_OFFSETS := [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0),                Vector2i(1, 0),
	Vector2i(-1, 1),  Vector2i(0, 1),  Vector2i(1, 1),
]


## 生成地图
## 返回 { mines: Array, mine_set: Dictionary{Vector2i: bool}, numbers: Dictionary{Vector2i: int} }
## safe_zone 内的格子不会放雷
static func generate(rows: int, cols: int, mine_count: int, safe_zone: Rect2i) -> Dictionary:
	var candidates: Array[Vector2i] = []
	for y in rows:
		for x in cols:
			var c := Vector2i(x, y)
			if not _in_safe_zone(c, safe_zone):
				candidates.append(c)
	candidates.shuffle()

	var mine_count_clamped: int = min(mine_count, candidates.size())
	var mines: Array = candidates.slice(0, mine_count_clamped)
	var mine_set: Dictionary = {}
	for m in mines:
		mine_set[m] = true

	var numbers: Dictionary = {}
	for y in rows:
		for x in cols:
			var c := Vector2i(x, y)
			if mine_set.has(c):
				continue
			var count: int = 0
			for o in NEIGHBOR_OFFSETS:
				if mine_set.has(c + o):
					count += 1
			numbers[c] = count

	return {"mines": mines, "mine_set": mine_set, "numbers": numbers}


## 在排除区域外放雷（用于 v0.2 基地放置后生成雷）
## exclude_coords: Array[Vector2i] - 这些格子不会放雷
## shape_mask: Array[String] - 可选形状掩码（'1'=有格，'0'=洞/盘外，行数=rows）；
## 非空时候选与数字都只算掩码内格子——雷数守恒（不会布进洞里被丢弃）
## 返回结构同 generate()
static func generate_excluding(rows: int, cols: int, mine_count: int, exclude_coords: Array,
		shape_mask: Array = []) -> Dictionary:
	var exclude_set: Dictionary = {}
	for c in exclude_coords:
		exclude_set[c] = true
	var candidates: Array[Vector2i] = []
	for y in rows:
		for x in cols:
			if not _shape_ok(shape_mask, x, y):
				continue
			var c := Vector2i(x, y)
			if not exclude_set.has(c):
				candidates.append(c)
	candidates.shuffle()

	var mine_count_clamped: int = min(mine_count, candidates.size())
	var mines: Array = candidates.slice(0, mine_count_clamped)
	var mine_set: Dictionary = {}
	for m in mines:
		mine_set[m] = true

	var numbers: Dictionary = {}
	for y in rows:
		for x in cols:
			if not _shape_ok(shape_mask, x, y):
				continue
			var c := Vector2i(x, y)
			if mine_set.has(c):
				continue
			var count: int = 0
			for o in NEIGHBOR_OFFSETS:
				if mine_set.has(c + o):
					count += 1
			numbers[c] = count

	return {"mines": mines, "mine_set": mine_set, "numbers": numbers}


## 掩码判定：无掩码=矩形全过；有掩码按行字符（越界/缺字符=缺格）
static func _shape_ok(shape_mask: Array, x: int, y: int) -> bool:
	if shape_mask.is_empty():
		return true
	if y < 0 or y >= shape_mask.size():
		return false
	var row: String = shape_mask[y]
	return x >= 0 and x < row.length() and row[x] == '1'


## 生成以 center 为中心的矩形安全区
static func make_center_safe_zone(rows: int, cols: int, radius: int) -> Rect2i:
	var center := Vector2i(rows / 2, cols / 2)
	return Rect2i(center.x - radius, center.y - radius, radius * 2 + 1, radius * 2 + 1)


static func _in_safe_zone(c: Vector2i, zone: Rect2i) -> bool:
	return c.x >= zone.position.x and c.x < zone.position.x + zone.size.x \
	   and c.y >= zone.position.y and c.y < zone.position.y + zone.size.y
