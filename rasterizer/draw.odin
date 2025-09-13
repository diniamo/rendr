package rasterizer

import "core:math"
import "core:math/linalg"
import t "common:types"
import "common:canvas"

clamp_pixel :: proc(pixel: t.Vector2) -> t.Vector2 {
	MIN_X :: -CANVAS_WIDTH/2
	MAX_X :: CANVAS_WIDTH/2 - 1
	MIN_Y :: -CANVAS_HEIGHT/2 + 1
	MAX_Y :: CANVAS_HEIGHT/2

	return {
		math.clamp(pixel.x, MIN_X, MAX_X),
		math.clamp(pixel.y, MIN_Y, MAX_Y)
	}
}

pixel :: proc(data: ^Render_Data, point: t.Vector2, depth: f32, color: t.Color) {
	index := canvas.position_to_index(&data.canvas, point)
	// The depth values are actually 1/z, so the comparison is inverted
	if depth > data.depth_buffer[index] {
		canvas.pixel(&data.canvas, index, color)
		data.depth_buffer[index] = depth
	}
}

draw_filled_triangle :: proc(data: ^Render_Data, a, b, c: t.Vector2, da, db, dc: f32, color: t.Color) {
	a := clamp_pixel(a); da := da
	b := clamp_pixel(b); db := db
	c := clamp_pixel(c); dc := dc

	x_min := min(a.x, b.x, c.x)
	x_max := max(a.x, b.x, c.x)
	y_min := min(a.y, b.y, c.y)
	y_max := max(a.y, b.y, c.y)

	edge_function :: proc(a, b, p: t.Vector2) -> f32 {
		ab := b - a
		ap := p - a
		return f32(ap.x*ab.y - ap.y*ab.x)
	}

	coefficient_triangle := edge_function(a, b, c)
	if coefficient_triangle <= 0 do return

	// TODO: avoid unnecessary calculations
	// PERF: better traversal
	for x in x_min..=x_max {
		for y in y_min..=y_max {
			point := t.Vector2{x, y}
			coefficient_a := edge_function(b, c, point)
			coefficient_b := edge_function(c, a, point)
			coefficient_c := edge_function(a, b, point)

			if coefficient_a < 0 || coefficient_b < 0 || coefficient_c < 0 do continue

			coefficient_a /= coefficient_triangle
			coefficient_b /= coefficient_triangle
			coefficient_c /= coefficient_triangle

			depth := da * coefficient_a + db * coefficient_b + dc * coefficient_c
			pixel(data, point, depth, color)
		}
	}
}
