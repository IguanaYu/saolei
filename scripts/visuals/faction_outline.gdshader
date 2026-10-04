shader_type canvas_item;
render_mode unshaded;

uniform vec4 faction_color : source_color = vec4(0.18, 0.85, 0.94, 1.0);
uniform vec2 frame_count = vec2(1.0);
varying vec4 item_modulate;

void vertex() {
	item_modulate = COLOR;
}

// Sample only the active atlas frame: animation neighbours must not create edges.
float frame_alpha(sampler2D sprite_texture, vec2 uv, vec2 frame_min, vec2 frame_max) {
	if (any(lessThan(uv, frame_min)) || any(greaterThanEqual(uv, frame_max))) {
		return 0.0;
	}
	return texture(sprite_texture, uv).a;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec2 frame_min = floor(UV * frame_count) / frame_count;
	vec2 frame_max = frame_min + 1.0 / frame_count;
	vec2 pixel = TEXTURE_PIXEL_SIZE;
	float adjacent_alpha = min(
		min(frame_alpha(TEXTURE, UV + vec2(pixel.x, 0.0), frame_min, frame_max),
			frame_alpha(TEXTURE, UV - vec2(pixel.x, 0.0), frame_min, frame_max)),
		min(frame_alpha(TEXTURE, UV + vec2(0.0, pixel.y), frame_min, frame_max),
			frame_alpha(TEXTURE, UV - vec2(0.0, pixel.y), frame_min, frame_max)));
	// Colour the existing silhouette rim, keeping sprite geometry and padding intact.
	float rim = step(0.1, source.a) * (1.0 - step(0.1, adjacent_alpha));
	source.rgb = mix(source.rgb, faction_color.rgb, rim * 0.9);
	COLOR = source * item_modulate;
}
