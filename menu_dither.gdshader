shader_type canvas_item;

uniform float cell_size : hint_range(2.0, 64.0) = 7.0;
uniform float contrast_amt : hint_range(0.0, 3.0) = 1.15;
uniform vec3 tint_color : source_color = vec3(1.0, 0.231, 0.122);
uniform float tint_opacity : hint_range(0.0, 1.0) = 0.32;
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.28;
uniform float bloom_intensity : hint_range(0.0, 1.0) = 0.45;
uniform float bloom_threshold : hint_range(0.0, 1.0) = 0.55;
uniform float circle_radius : hint_range(0.0, 0.5) = 0.34;
uniform float circle_feather : hint_range(0.0, 0.4) = 0.12;
uniform float aspect_ratio : hint_range(0.1, 5.0) = 1.0;
uniform float glow_speed : hint_range(0.05, 3.0) = 0.6;

// 4x4 Bayer ordered-dither threshold matrix, flattened.
float bayer_value(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int idx = y * 4 + x;
	if (idx == 0) { return 0.0; }
	if (idx == 1) { return 8.0; }
	if (idx == 2) { return 2.0; }
	if (idx == 3) { return 10.0; }
	if (idx == 4) { return 12.0; }
	if (idx == 5) { return 4.0; }
	if (idx == 6) { return 14.0; }
	if (idx == 7) { return 6.0; }
	if (idx == 8) { return 3.0; }
	if (idx == 9) { return 11.0; }
	if (idx == 10) { return 1.0; }
	if (idx == 11) { return 9.0; }
	if (idx == 12) { return 15.0; }
	if (idx == 13) { return 7.0; }
	if (idx == 14) { return 13.0; }
	return 5.0;
}

// Photoshop-style "overlay" blend, per channel.
vec3 overlay_blend(vec3 base, vec3 blend) {
	vec3 lo = 2.0 * base * blend;
	vec3 hi = 1.0 - 2.0 * (1.0 - base) * (1.0 - blend);
	return mix(lo, hi, step(0.5, base));
}

void fragment() {
	vec2 tex_size = 1.0 / TEXTURE_PIXEL_SIZE;

	vec2 pixel_pos = UV * tex_size;
	vec2 cell_center = (floor(pixel_pos / cell_size) + 0.5) * cell_size;
	vec2 sample_uv = clamp(cell_center / tex_size, vec2(0.0), vec2(1.0));

	// Sample a mip level matched to the cell size to approximate a block average.
	float lod = log2(max(cell_size / 4.0, 1.0));
	vec4 col = textureLod(TEXTURE, sample_uv, lod);

	float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	lum = clamp((lum - 0.5) * contrast_amt + 0.5, 0.0, 1.0);

	float threshold = bayer_value(floor(pixel_pos / 2.0)) / 16.0;
	float dithered = step(threshold, lum);

	vec3 shaded = mix(vec3(dithered), col.rgb * (0.5 + dithered * 0.5), 0.45);

	vec3 tinted = mix(shaded, overlay_blend(shaded, tint_color), tint_opacity);

	// Cheap single-pass bloom: bright cells glow outward in the tint color.
	float glow = smoothstep(bloom_threshold, 1.0, lum) * bloom_intensity;
	tinted += tint_color * glow * 0.6;

	vec2 vpos = UV - 0.5;
	float vig = 1.0 - dot(vpos, vpos) * vignette_intensity * 2.2;
	tinted *= clamp(vig, 0.0, 1.0);

	// Circular soft-edged mask — the photo reads as a gentle medallion, not a hard rectangle.
	vec2 centered = UV - 0.5;
	centered.x *= aspect_ratio;
	float dist = length(centered);
	float mask = 1.0 - smoothstep(circle_radius, circle_radius + circle_feather, dist);

	// Slow breathing halo just past the edge — a soft pulse of the tint color.
	float breathe = 0.5 + 0.5 * sin(TIME * glow_speed);
	float halo = smoothstep(circle_radius, circle_radius + circle_feather * 0.5, dist)
		* (1.0 - smoothstep(circle_radius + circle_feather * 0.5, circle_radius + circle_feather * 1.2, dist));
	vec3 halo_color = tint_color * halo * (0.18 + breathe * 0.3);
	tinted += halo_color;

	float alpha = clamp(mask + halo * (0.25 + breathe * 0.25), 0.0, 1.0);
	COLOR = vec4(clamp(tinted, vec3(0.0), vec3(1.0)), alpha);
}
