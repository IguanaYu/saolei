@echo off
rem 地图工坊（路径驱动地图生成器编辑器）独立启动器——双击打开
rem Godot 位置如有变化，改下面一行即可
cd /d "%~dp0"
start "" "E:\godot\Godot_v4.6.1-stable_win64.exe" --path . res://scenes/tools/route_editor.tscn
