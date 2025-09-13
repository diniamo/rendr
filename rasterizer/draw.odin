package rasterizer

import "core:math"
import "core:math/linalg"
import t "common:types"
import "common:canvas"
import "common:scene"

pixel :: proc(target: ^canvas.Canvas, depth_buffer: []f32, point: t.Vector2, depth: f32, color: t.Color) {
	index := canvas.position_to_index(target, point)
	// The depth values are actually 1/z, so the comparison is inverted
	if depth > depth_buffer[index] {
		// if debug_face do canvas.pixel(target, index, {0, 1, 1})
		// else do canvas.pixel(target, index, color)
		canvas.pixel(target, index, color)
		depth_buffer[index] = depth
	}
}

draw_filled_triangle :: proc(
	data: ^Render_Data,
	a, b, c: t.Vector2,
	da, db, dc: f32,
	na, nb, nc: t.Vector3,
	material: scene.Material
) {
	x_min := max(min(a.x, b.x, c.x), -CANVAS_WIDTH/2)
	x_max := min(max(a.x, b.x, c.x), CANVAS_WIDTH/2 - 1)
	y_min := max(min(a.y, b.y, c.y), -CANVAS_HEIGHT/2 + 1)
	y_max := min(max(a.y, b.y, c.y), CANVAS_HEIGHT/2)

	edge_function :: proc(a, b, p: t.Vector2) -> f32 {
		ab := b - a
		ap := p - a
		return f32(ap.x*ab.y - ap.y*ab.x)
	}

	coefficient_triangle := edge_function(a, b, c)
	if coefficient_triangle <= 0 do return

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

			depth := coefficient_a * da + coefficient_b * db + coefficient_c * dc
			camera_point := to_vector3(data.canvas_to_camera * t.Vector4{f32(x), f32(y), 1, depth})
			normal := coefficient_a * na + coefficient_b * nb + coefficient_c * nc
			intensity := compute_light(camera_point, normal, data.scene.camera, data.scene.lights[:], material)
			pixel(&data.canvas, data.depth_buffer[:], point, depth, intensity * material.color)
		}
	}
}
