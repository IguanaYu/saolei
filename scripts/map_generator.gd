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


## 生成以 center 为中心的矩形安全区
static func make_center_safe_zone(rows: int, cols: int, radius: int) -> Rect2i:
	var center := Vector2i(rows / 2, cols / 2)
	return Rect2i(center.x - radius, center.y - radius, radius * 2 + 1, radius * 2 + 1)


static func _in_safe_zone(c: Vector2i, zone: Rect2i) -> bool:
	return c.x >= zone.position.x and c.x < zone.position.x + zone.size.x \
	   and c.y >= zone.position.y and c.y < zone.position.y + zone.size.y
