package rasterizer

import "core:math/rand"
import "core:math"
import "core:math/linalg"
import t "common:types"
import "common:canvas"
import "common:scene"

pixel :: proc(target: ^canvas.Canvas, depth_buffer: []f32, point: t.Vector2i, depth: f32, color: t.Color) {
	index := canvas.position_to_index(target, point)
	// The depth values are actually 1/z, so the comparison is inverted
	if depth > depth_buffer[index] {
		canvas.pixel_index(target, index, color)
		depth_buffer[index] = depth
	}
}

draw_filled_triangle :: proc(
	data: ^Render_Data,
	a, b, c: t.Vector2i,
	at, bt, ct: t.Vector2f,
	an, bn, cn: t.Vector3,
	ad, bd, cd: f32,
	material: scene.Material,
	texture: Maybe(scene.Texture)
) {
	edge_function :: proc(a, b, p: t.Vector2i) -> f32 {
		ab := b - a
		ap := p - a
		return f32(ap.x*ab.y - ap.y*ab.x)
	}

	coefficient_triangle := edge_function(a, b, c)
	if coefficient_triangle <= 0 do return

	x_min := max(min(a.x, b.x, c.x), -CANVAS_WIDTH/2)
	x_max := min(max(a.x, b.x, c.x), CANVAS_WIDTH/2 - 1)
	y_min := max(min(a.y, b.y, c.y), -CANVAS_HEIGHT/2 + 1)
	y_max := min(max(a.y, b.y, c.y), CANVAS_HEIGHT/2)

	at := at * ad
	bt := bt * bd
	ct := ct * cd

	material := material

	for x in x_min..=x_max {
		for y in y_min..=y_max {
			point := t.Vector2i{x, y}
			coefficient_a := edge_function(b, c, point)
			coefficient_b := edge_function(c, a, point)
			coefficient_c := edge_function(a, b, point)

			if coefficient_a < 0 || coefficient_b < 0 || coefficient_c < 0 do continue

			coefficient_a /= coefficient_triangle
			coefficient_b /= coefficient_triangle
			coefficient_c /= coefficient_triangle

			depth := coefficient_a * ad + coefficient_b * bd + coefficient_c * cd

			switch texture in texture {
			case scene.Texture:
				texel := (coefficient_a * at + coefficient_b * bt + coefficient_c * ct) / depth
				texture_x := int(texel.x * f32(texture.width))
				texture_y := int(texel.y * f32(texture.height))
				color_start := (texture_y * texture.width + texture_x) * scene.TEXTURE_CHANNELS

				material.color = {texture.colors[color_start], texture.colors[color_start + 1], texture.colors[color_start + 2]}
			}

			camera_point := to_vector3(data.canvas_to_camera * t.Vector4{f32(x), f32(y), 1, depth})
			normal := coefficient_a * an + coefficient_b * bn + coefficient_c * cn
			intensity := compute_light(camera_point, normal, data.scene.camera, data.scene.lights[:], material)

			pixel(&data.canvas, data.depth_buffer[:], point, depth, intensity * material.color)
		}
	}
}
