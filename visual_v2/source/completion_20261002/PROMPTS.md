# 生成提示词生产规格

生成工具：内置 image_gen，所有图使用真实透明 alpha。以下按最终提示词集归档主体、构图、帧序和约束；保留的 boss.png 是第一次图集，实际导出使用 boss_repacked.png。

共用约束：production pixel sprite atlas for a dark steampunk mining minesweeper game; crisp chunky hand-crafted pixel art, purposeful readable clusters, dark outlines, dark slate / muted earth / copper / pale steel palette, restrained cyan machinery lights, amber ore/fire, red warning flag. No words, labels, grid lines, UI, scenery, blur or smooth gradients. Entire silhouettes contained in transparent slots; readability at 22–28px runtime sizes.

| 源图 | 最终提示词集的主体和排布 |
| --- | --- |
| base.png | One compact three-quarter front/top mining robot headquarters. Octagonal steel bunker, copper roof trim, wide dark robot doorway, two vents, cyan status lamp, antenna and tiny copper pennant. Solid building silhouette, substantial roof, not a computer monitor. Centered in square transparent canvas, full sprite inside margins, readable at 28px. |
| specials.png | Three equal square cells in one row: red triangular cloth marker flag on steel pole and bolted foot; dark jagged gold ore rock with irregular amber seams and three facets, gold less than 40%; deep collapsed black mine crater with dark reddish broken stone ring. Three-quarter top-down. |
| guard.png | Two cells, same security robot idle and walking. Squat steel-gray armor, copper fittings, cyan eyes, blue-gray shield, short stun baton, mechanical legs. Same size and identity, changed foot/elbow pose only. Readable at24px. |
| enemies.png | Four columns × three rows. Row1 spider idle/walk, lock-armored horn beetle idle/walk. Row2 teal ridged-shell slime snail idle/walk, green gelatinous slime idle/squashed. Row3 rocky egg nest full/damaged/broken, last cell empty. Distinct organic silhouettes, restrained cyan/amber eyes. |
| overlays.png | Four columns × two rows. Row1 silver tangled web with dense center; purple plated iron padlock; teal bubble slime puddle with transparent digit window; darker slime variation. Row2 fire with burned stone base; alternate fire tips; dying embers; copper diamond plaque with dark exclamation mark. |
| hazards.png | Four columns × three rows. Row1 tentacle amber-core root, horizontally connectable purple ridged middle, tapering ivory-claw tip, two broken pieces. Row2 riveted black iron bomb with lit fuse, same bomb alternate fuse, deflected bomb with contained cyan trail, dark landing oval and amber brackets. Row3 compact flash, expanding orange blast with fragments, smoky flame, fading smoke/embers. |
| utilities.png | Four square slots: twin-rotor copper mining drone with cyan lens and claw; copper radar probe on steel tripod with cyan console; chipped curved ivory beast tooth; cyan crystal ore in dark stone base. Readable at24px, tooth at16px. |
| boss.png | Three columns × seven rows. Giant broad squat craggy cave beast, two hooked forearms, toothy maw and forehead fangs, amber eyes. Columns calm purple slate / enraged rusty purple / furious red cracked stone. Rows idle, claw swipe, inhale, growl, staggered, crawl, defeated. Same creature and scale; runtime140×64. |
| boss_repacked.png | Edit target boss.png. Change ONLY packing/spacing; preserve monster identity, colors and 21 poses. Three equal columns × seven equal rows, complete isolated silhouettes, roomy transparent gutters, no labels or lines. Same column phases and row order. Critical correction: never cut or combine neighboring sprites. |

模型排布仍需独立 alpha 像素测量，不能把提示词中的网格要求当成已实现的事实；实际切片规则记录于 manifest.json。
