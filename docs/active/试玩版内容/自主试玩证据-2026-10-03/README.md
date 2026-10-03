# 自主试玩证据索引

测试日期：2026-10-03。测试版本：worktree 起始提交 `433ca1c`，Godot 4.6.1。

入口见 [10月3日测试反馈](../自主试玩-反馈文档-2026-10-03.md) 和 [验证清单](../自主试玩-验证清单-2026-10-03.md)。第一轮采用引擎内输入，第二轮成功使用 Windows Computer Use 操控真实游戏窗口。两轮覆盖范围不同，详见反馈文档。

## 关键问题证据

| 问题 | 截图或日志 |
| --- | --- |
| F01 暂停期间 Esc 失效 | `35-pause.png`、`40-settings-returns-pause.png`、`41-pause-settings-esc-repeat.png`、`43-pause-escape-resume.png`、`44-resume-button.png` |
| F02 机器人规则过期 | `04-rules-bottom.png`、`22-level1-buy-opener.png`、`25-marker-and-robots.png` |
| F03 日志容量淘汰错误 | `99-boss-pause-again.png`、`100-boss-log-overflow-running.png`；`runtime-engine-input-03.log` 第 228 行起，共 41 次脚本错误 |

## 文件用途

- `01` 至 `114` 前缀截图及 `scroll-step-*`、`settings-scroll-*`：各操作步骤后的真实画面。命名数字用于采集顺序，部分步骤有多个截图；命名不作为实际行为判定。
- `40-settings-returns-pause.png`、`43-pause-escape-resume.png`：当时按预期动作命名，实际仍在设置/暂停页，正是 F01 的反证。
- `45-upgrade-through-end.png`、`80-step-mine.png`：实际已到超时结算；不能单凭文件名判定“升级浮层跨结算”或“踩雷动画”已完整验证。
- `92-level5-phase2-trigger.png`：拍到了第二阶段与落点预警，但右键操作前阶段已推进；不能据此声称该次右键触发了阶段变化。
- `108-quit-exit.png`、`115-final-exit.png` 未生成：点击确认后游戏正常退出，异步截图没有继续执行；退出行为由日志与进程状态确认。
- `state.json`：最后一次成功截图的可见 Button/Label、控件矩形和暂停状态，属于可见 UI，不含隐藏棋盘数据。另有第 78、84 步的独立状态快照。
- `input-harness.gd.txt`：临时 SceneTree 输入/截图入口的归档副本；原项目场景及函数未替换。
- `editor-import.log`、`import-confirm.log`：首次编辑器导入与二次无错导入确认。
- `runtime-01.log`：原始场景入口启动记录。
- `runtime-engine-input*.log`：临时入口测试记录，主要试玩在 `runtime-engine-input-03.log`。前两版入口仅用于验证方法；最终按 `Input.parse_input_event()` 的操作判断问题。
- `runtime-restart.log`：正常重启、检查设置和选关、退出的记录。
- `native-01-*` 至 `native-26-*`：第二轮真实 Windows 鼠标、键盘、滚轮操作后的窗口截图。包括开格/标旗/撤旗、购买机器人、暂停/设置/规则 Esc、按钮返回、退出确认。
- `native-control-result.json`：原生电脑操作记录和最终窗口关闭状态。确认退出后第一次即时窗口枚举仍有旧窗口，随后再次枚举已消失，进程退出码为 0。
- `runtime-native-retry.log`：第二轮原始游戏入口日志，没有注入输入脚本；无 ERROR / SCRIPT ERROR / WARNING，正常退出码 0。
- `log-summary.json`：各日志 ERROR / SCRIPT ERROR / WARNING 行计数。测试脚本 JSON 解析错误与退出警告的归因见反馈文档。
- `save-before-restart.json` / `save-after-restart.json`、`settings-before-restart.json` / `settings-after-restart.json`：独立测试数据的重启前后副本。
- `data-protection.json`：原玩家存档、设置的前后 SHA256；两项均未改变。

本轮保留采集原件，没有把脚本错误清除后重新包装为“无报错”。未覆盖的功能见反馈文档。
