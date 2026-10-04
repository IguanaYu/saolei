class_name ObjectiveData
extends Resource
## 单关过关目标

enum Type {
	CLEAR_ALL_SAFE,  # 清空全部安全格
	REACH_SCORE,     # 达到指定积分
	FLAG_N_MINES,    # 标对 N 颗雷
	SURVIVE_TIME,    # 生存 N 秒
	ACTIVATE_N_TOWER,  # 激活 N 座充能塔（功能未实现，仅占位）
	FIND_ALL_MINES,  # 处理全部雷（正确旗/探测确认/踩塌坍塌，L5 Boss 关「拔牙」）
}

var type: Type = Type.CLEAR_ALL_SAFE
var target_value: int = 0


func get_type_name() -> String:
	match type:
		Type.CLEAR_ALL_SAFE: return "CLEAR_ALL_SAFE"
		Type.REACH_SCORE: return "REACH_SCORE"
		Type.FLAG_N_MINES: return "FLAG_N_MINES"
		Type.SURVIVE_TIME: return "SURVIVE_TIME"
		Type.ACTIVATE_N_TOWER: return "ACTIVATE_N_TOWER"
	return ""


## HUD 显示的进度文本，如 "目标: 标 5 颗雷 (3/5)"
## total > 0 时 CLEAR_ALL_SAFE 也带 (已开/总数) 数字
func build_progress_text(current: int, total: int = 0) -> String:
	match type:
		Type.CLEAR_ALL_SAFE:
			if target_value > 0:
				return "目标: 开 %d 格 (%d/%d)" % [target_value, mini(current, target_value), target_value]
			if total > 0:
				return "目标: 清空安全格 (%d/%d)" % [mini(current, total), total]
			return "目标: 清空全部安全格"
		Type.REACH_SCORE:
			return "目标: 达到 %d 分 (%d/%d)" % [target_value, min(current, target_value), target_value]
		Type.FLAG_N_MINES:
			return "目标: 标 %d 颗雷 (%d/%d)" % [target_value, min(current, target_value), target_value]
		Type.SURVIVE_TIME:
			return "目标: 生存 %d 秒 (剩余 %d)" % [target_value, max(0, current)]
		Type.ACTIVATE_N_TOWER:
			return "目标: 激活 %d 座充能塔" % target_value
		Type.FIND_ALL_MINES:
			return "目标: 拔牙 (%d/%d)" % [mini(current, target_value), target_value]
	return ""


## 关卡列表按钮上的短描述
func short_label() -> String:
	match type:
		Type.CLEAR_ALL_SAFE:
			if target_value > 0: return "开 %d 格" % target_value
			return "清空安全格"
		Type.REACH_SCORE: return "%d 分" % target_value
		Type.FLAG_N_MINES: return "标 %d 雷" % target_value
		Type.SURVIVE_TIME: return "生存 %ds" % target_value
		Type.ACTIVATE_N_TOWER: return "激活 %d 塔" % target_value
		Type.FIND_ALL_MINES: return "拔光 %d 牙" % target_value
	return ""


# ---- 近失判定（P0.4 差一点激励）----
# 到点/命尽未达标时"差一点就过"的判定与距离文案；纯函数便于单测。
# current/total 为局末数值快照（main._end_game 存 result_stats.obj_final_current/total）。
# 文案红线（设计 v1.2）：非失败框架，措辞用"还差/只差"，不出现失败字样。

## 各目标类型的近失阈值：差距小于等于阈值即近失
static func is_near_miss(type: Type, current: int, total: int, target_value: int) -> bool:
	match type:
		Type.REACH_SCORE:
			return target_value > 0 and current < target_value \
					and float(target_value - current) / float(target_value) <= 0.10
		Type.CLEAR_ALL_SAFE:
			var goal: int = target_value if target_value > 0 else total
			return goal > 0 and current < goal and goal - current <= 5
		Type.FIND_ALL_MINES:
			var goal_teeth: int = target_value if target_value > 0 else total
			return goal_teeth > 0 and current < goal_teeth and goal_teeth - current <= 3
		Type.FLAG_N_MINES:
			return target_value > 0 and current < target_value and target_value - current <= 3
		Type.SURVIVE_TIME:
			# current = 剩余秒快照；差一点 = 只剩 ≤20% 时长（即已存活 ≥80%）
			return target_value > 0 and current > 0 and float(current) / float(target_value) <= 0.20
	return false


## 近失距离文案（结算页金色行）；调用方需先过 is_near_miss
static func near_miss_gap_text(type: Type, current: int, total: int, target_value: int) -> String:
	match type:
		Type.REACH_SCORE:
			return "差 %d 分就达成" % (target_value - current)
		Type.CLEAR_ALL_SAFE:
			var goal: int = target_value if target_value > 0 else total
			return "还差 %d 格清完" % (goal - current)
		Type.FIND_ALL_MINES:
			var goal_teeth: int = target_value if target_value > 0 else total
			return "还差 %d 颗牙" % (goal_teeth - current)
		Type.FLAG_N_MINES:
			return "还差 %d 面旗" % (target_value - current)
		Type.SURVIVE_TIME:
			return "只差 %d 秒" % current
	return ""
