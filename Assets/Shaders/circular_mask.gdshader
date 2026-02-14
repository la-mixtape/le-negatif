shader_type canvas_item;

// Circular magnifier shader
// Samples the investigation image zoomed around the cursor point

uniform sampler2D magnified_texture : filter_linear_mipmap;
uniform vec2 uv_center = vec2(0.5, 0.5);       // cursor position in texture UV
uniform vec2 magnifier_uv_size = vec2(0.1, 0.2); // UV window the magnifier spans at zoom=1
uniform float zoom = 1.5;
uniform float border_width : hint_range(0.0, 0.1) = 0.02;
uniform vec4 border_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float dist = length(centered);

	// 1. Translate: offset from magnifier center (centered goes -1..1, so *0.5 → -0.5..0.5)
	vec2 offset = centered * 0.5;

	// 2. Scale: convert magnifier-space offset to texture UV offset, divided by zoom
	vec2 tex_offset = offset * magnifier_uv_size / zoom;

	// 3. Translate: position in texture UV space relative to cursor
	vec2 image_uv = uv_center + tex_offset;
	image_uv = clamp(image_uv, vec2(0.0), vec2(1.0));

	vec4 tex_color = texture(magnified_texture, image_uv);

	// Circular mask with smooth edge
	float circle = smoothstep(1.0, 0.98, dist);

	// Border ring
	float border = smoothstep(1.0 - border_width, 1.0 - border_width + 0.02, dist);
	border *= 1.0 - smoothstep(1.0, 1.0 + 0.02, dist);

	vec4 final_color = mix(tex_color, border_color, border);
	final_color.a *= circle;

	COLOR = final_color;
}
