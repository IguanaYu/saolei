extends RefCounted
## A 版局内界面：集中定义色彩与控件样式，沿用项目字体及像素图标。
const INK := Color("f1ede2")
const SOFT := Color("a2acaa")
const SIGNAL := Color("91d5c3")
const GOLD := Color("f0c04a")
const LINE := Color("3d4544")
const PANEL := Color("20272a")

static func panel() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL
	s.border_color = LINE
	s.set_border_width_all(1)
	s.set_corner_radius_all(9)
	s.set_content_margin_all(16)
	return s

static func button(b: Button, font_size := 14) -> void:
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", SIGNAL)
	b.add_theme_color_override("font_pressed_color", SIGNAL)
	b.add_theme_color_override("font_disabled_color", Color("697371"))
	b.add_theme_constant_override("icon_max_width", 30)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color("2a3235") if state in ["hover", "pressed"] else PANEL
		s.border_color = SIGNAL if state == "focus" else LINE
		s.set_border_width_all(1)
		s.set_corner_radius_all(5)
		s.content_margin_left = 8
		s.content_margin_right = 8
		s.content_margin_top = 5
		s.content_margin_bottom = 5
		b.add_theme_stylebox_override(state, s)

static func label(text: String, node_name: String, font_size := 14, color := INK) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l

static func icon(texture: Texture2D, node_name: String, px := 24) -> TextureRect:
	var t := TextureRect.new()
	t.name = node_name
	t.texture = texture
	t.custom_minimum_size = Vector2(px, px)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t
