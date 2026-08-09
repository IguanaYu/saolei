class_name RewardData
extends Resource
## 通关奖励（首通 / 重刷）

var ore: int = 0
var gold: int = 0
# 强制留空：模块解锁唯一入口是 chapter.unlock_module，避免双重解锁路径
var unlock_id: String = ""
