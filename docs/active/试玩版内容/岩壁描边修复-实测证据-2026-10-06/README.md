# 岩壁假描边修复 · 实测证据（2026-10-06）

## Bug
`Grid.init_empty_grid()` 按行逐个 `add_child` 建格，Cell `_ready` 立即算描边时
右/下邻居尚未写入 `cells`，`get_cell()==null` 被判"地图外=开侧"→ 未开岩壁的
右/下两面从开局就挂着假碎裂描边（金线）。贴开区的格子随挖掘被 `refresh_edges_around`
刷新而自愈，远岩永远没人碰 → 肉眼看到"贴数字一圈与远处岩石描边不一致"。

## 修复（commit f6fb8ba，已推送）
`init_empty_grid` 建格循环后对全盘统一 `refresh_wall_edges()`（两条建盘路径共用）。

## 验证（三层）
1. headless spec 断言：L5 固定盘全盘 784 边，"可见⇔邻格是地图外或已开"0 失配（修复前实测 (12,13) 等多处假 true）。
2. 真机 harness（tmp/auto_edge_fix_shot.gd，真实导航进 L5）：放基地前后各一次 spec 断言均 0 失配；截图 01/02。
3. 像素级（verify 脚本，几何真值来自游戏侧导出，暖线=描边签名）：
   - 修复前（用户实拍 bug 截图）：岩|岩 199 条边界 164 条带假描边暖线（82%）
   - 修复后（01/02 两张）：岩|岩 217 条 **0 条**；岩|开区 30/30 描边齐全（该在的全在）
   - 对比图 compare-far-rock-before-after.png

## 文件
- 01-l5-board-settled.png / 02-l5-base-placed.png：harness 实拍（网格线层已隐藏，避免与本验证混淆）
- geometry-01/02.json：每格窗口物理坐标+开/岩状态（像素验证地面真值）
- compare-far-rock-before-after.png：远处岩区修复前后肉眼对比
- 像素验证输出.txt：验证脚本完整输出

## 备注
- 截图像素=窗口物理像素（2560x1440），画布坐标须经 `root.get_final_transform()` 变换——harness 里 `_inject_click` 与几何导出同源，坐标才对得上。
- 本机存档 show_grid=on 会给所有相邻格画黑色 35% 网格线（含岩|岩），与描边无关；验证用暖线签名（描边独有）区分。
