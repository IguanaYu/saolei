# Windows 封闭试玩包

运行 `scripts/build_windows.ps1` 重新导入资源、导出 Release 并生成
`build/扫雷挖矿_外部试玩_v0.1.zip`。脚本可通过 `-GodotPath` 指定 Godot 4.6.1。

预设使用 Windows x86_64、内嵌 PCK，无控制台窗口；图标复用现有双镐矿洞徽记。
保留 `visual_v2/runtime/`，排除设计稿、调试截图、临时目录和构建产物。
项目显式使用 OpenGL Compatibility 渲染器。

2026-10-01 本机验证：导入与导出成功，256 项运行资源可加载；通过导出 EXE
中的 PCK 加载主菜单和五关，检查实际渲染窗口；补上音频退出释放后，退出日志
无资源泄漏提示。独立 Release EXE 另做启动检查。

这些检查覆盖启动与关卡加载，不代表五关完整游玩通过。
尚需测试者在未安装 Godot 的电脑上验证完整游玩、音频和全屏切换。

参考：
- https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_windows.html
- https://github.com/godotengine/godot-demo-projects/blob/master/.github/dist/export_presets.cfg
