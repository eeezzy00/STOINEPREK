shader_type canvas_item;

uniform float line_intensity : hint_range(0.0, 1.0) = 0.16;
uniform float line_count : hint_range(50.0, 800.0) = 320.0;
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.55;
uniform float flicker_speed : hint_range(0.0, 20.0) = 7.0;
uniform float flicker_amount : hint_range(0.0, 0.2) = 0.025;

void fragment() {
	vec2 uv = UV;
	float scanline = sin(uv.y * line_count) * 0.5 + 0.5;
	float dark = scanline * line_intensity;

	vec2 center_dist = uv - vec2(0.5);
	float vignette = dot(center_dist, center_dist) * vignette_strength;

	float flicker = flicker_amount * sin(TIME * flicker_speed);

	float alpha = clamp(dark + vignette + flicker, 0.0, 0.85);
	COLOR = vec4(0.0, 0.0, 0.0, alpha);
}
