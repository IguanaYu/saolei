extends SceneTree
## Export generated transparent sheets to the existing native sprite dimensions.
## Crop registration is shared across each animation family, preserving frame anchors.
## Run: godot --headless --path <project> --script res://visual_v2/export_completion.gd

const SOURCE := "res://visual_v2/source/completion_20261002/"
const OUTPUT := "res://visual_v2/runtime/completion/"

func _initialize() -> void:
	var jobs: Array = JSON.parse_string(FileAccess.get_file_as_string(SOURCE + "manifest.json"))
	for job in jobs:
		_export_family(job)
	await process_frame
	quit()

func _export_family(job: Dictionary) -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(SOURCE + String(job.sheet) + ".png"))
	assert(image != null and not image.is_empty(), "Missing source: " + String(job.sheet))
	image.convert(Image.FORMAT_RGBA8)
	var columns := int(job.columns)
	var rows := int(job.rows)
	var frames: Array[Image] = []
	var common := Rect2i()
	if bool(job.get("components", false)):
		frames = _separate_boss(image)
	for slot in ([] if not frames.is_empty() else job.slots):
		var column := int(slot) % columns
		var row := int(slot) / columns
		# Rounding both boundaries supports source sizes not divisible by the grid.
		var left := roundi(float(column) * image.get_width() / columns)
		var top := roundi(float(row) * image.get_height() / rows)
		var right := roundi(float(column + 1) * image.get_width() / columns)
		var bottom := roundi(float(row + 1) * image.get_height() / rows)
		if job.has("x_cuts"):
			left = int(job.x_cuts[column])
			right = int(job.x_cuts[column + 1])
		if job.has("y_cuts"):
			top = int(job.y_cuts[row])
			bottom = int(job.y_cuts[row + 1])
		var frame := image.get_region(Rect2i(left, top, right - left, bottom - top))
		frames.append(frame)
	# Uneven source gutters are measured independently; center smaller source cells
	# on a common canvas before computing animation-family registration.
	var canvas := Vector2i.ZERO
	for frame in frames:
		canvas.x = maxi(canvas.x, frame.get_width())
		canvas.y = maxi(canvas.y, frame.get_height())
	for index in frames.size():
		var frame := frames[index]
		var padded := Image.create(canvas.x, canvas.y, false, Image.FORMAT_RGBA8)
		padded.fill(Color.TRANSPARENT)
		padded.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), (canvas - frame.get_size()) / 2)
		frames[index] = padded
		# Generated alpha can contain nearly invisible stray pixels far from the art.
		# Bounds use significant alpha; the original alpha inside the crop is preserved.
		var used := _visible_bounds(padded)
		assert(used.has_area(), "Empty sprite slot: " + String(job.sheet) + str(job.slots[index]))
		common = used if not common.has_area() else common.merge(used)
	var target := Vector2i(int(job.width), int(job.height))
	var margin := int(job.get("margin", 1))
	var ratio := minf(float(target.x - margin * 2) / common.size.x,
		float(target.y - margin * 2) / common.size.y)
	var resized := Vector2i(maxi(1, roundi(common.size.x * ratio)), maxi(1, roundi(common.size.y * ratio)))
	for index in frames.size():
		var cropped := frames[index].get_region(common)
		cropped.resize(resized.x, resized.y, Image.INTERPOLATE_NEAREST)
		var result := Image.create(target.x, target.y, false, Image.FORMAT_RGBA8)
		result.fill(Color.TRANSPARENT)
		var destination := (target - resized) / 2
		result.blit_rect(cropped, Rect2i(Vector2i.ZERO, resized), destination)
		var path := OUTPUT + String(job.names[index]) + ".png"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		assert(result.save_png(path) == OK, "Cannot save " + path)
		print("SPRITE_EXPORT ", path, " size=", target, " used=", result.get_used_rect())

func _visible_bounds(image: Image) -> Rect2i:
	var first := image.get_size()
	var last := Vector2i(-1, -1)
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a >= 0.5:
				first.x = mini(first.x, x)
				first.y = mini(first.y, y)
				last.x = maxi(last.x, x)
				last.y = maxi(last.y, y)
	return Rect2i(first, last - first + Vector2i.ONE) if last.x >= 0 else Rect2i()

## Boss poses have different heights: a rectangular row cut would include the
## neighboring pose's crest. Extract the 21 independently verified alpha components.
func _separate_boss(image: Image) -> Array[Image]:
	var width := image.get_width()
	var height := image.get_height()
	var visited := PackedByteArray()
	visited.resize(width * height)
	var groups: Array = []
	var canvas := Vector2i.ZERO
	for sy in height:
		for sx in width:
			var seed := sy * width + sx
			if visited[seed] or image.get_pixel(sx, sy).a < 0.5:
				continue
			var pending: Array[int] = [seed]
			var pixels := PackedInt32Array()
			visited[seed] = 1
			var first := Vector2i(sx, sy)
			var last := first
			while not pending.is_empty():
				var pixel: int = pending.pop_back()
				pixels.append(pixel)
				var x := pixel % width
				var y := pixel / width
				first.x = mini(first.x, x)
				first.y = mini(first.y, y)
				last.x = maxi(last.x, x)
				last.y = maxi(last.y, y)
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var next := Vector2i(x + dx, y + dy)
						if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
							continue
						var key := next.y * width + next.x
						if not visited[key] and image.get_pixelv(next).a >= 0.5:
							visited[key] = 1
							pending.append(key)
			if pixels.size() < 3000:
				continue
			var bounds := Rect2i(first, last - first + Vector2i.ONE)
			var center := bounds.get_center()
			var column := clampi(int(float(center.x) * 3 / width), 0, 2)
			var row := clampi(int(float(center.y) * 7 / height), 0, 6)
			groups.append({"slot": row * 3 + column, "bounds": bounds, "pixels": pixels})
			canvas.x = maxi(canvas.x, bounds.size.x)
			canvas.y = maxi(canvas.y, bounds.size.y)
	assert(groups.size() == 21, "Boss alpha components must contain 21 complete poses")
	groups.sort_custom(func(a, b): return a.slot < b.slot)
	var result: Array[Image] = []
	for index in groups.size():
		var group: Dictionary = groups[index]
		assert(int(group.slot) == index, "Missing or duplicate boss pose")
		var frame := Image.create(canvas.x + 2, canvas.y + 2, false, Image.FORMAT_RGBA8)
		frame.fill(Color.TRANSPARENT)
		var bounds: Rect2i = group.bounds
		var offset := Vector2i((frame.get_width() - bounds.size.x) / 2, frame.get_height() - bounds.size.y - 1)
		for pixel in group.pixels:
			var source := Vector2i(int(pixel) % width, int(pixel) / width)
			frame.set_pixelv(source - bounds.position + offset, image.get_pixelv(source))
		result.append(frame)
	return result
