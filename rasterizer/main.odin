package rasterizer

import "core:terminal/ansi"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "common:canvas"
import t "common:types"
import "common:scene"

CANVAS_WIDTH :: 600
CANVAS_HEIGHT :: 600
CANVAS_OUTPUT :: "rasterizer.png"

VIEWPORT_DISTANCE :: 0.5
VIEWPORT_WIDTH :: 2 * VIEWPORT_DISTANCE
VIEWPORT_HEIGHT :: 2 * VIEWPORT_DISTANCE

IST :: 1 / math.SQRT_TWO
CAMERA_PLANES :: [?]Plane{
	{{0, 0, 1}, -VIEWPORT_DISTANCE},
	{{IST, 0, IST}, 0},
	{{-IST, 0, IST}, 0},
	{{0, -IST, IST}, 0},
	{{0, IST, IST}, 0}
}

Plane :: struct {
	normal: t.Vector3,
	offset: f32
}

Sphere :: struct {
	center: t.Vector3,
	radius: f32
}

Render_Data :: struct {
	scene: scene.Scene,

	transform_cache: []t.Vector3,
	camera_to_canvas: matrix[4, 4]f32,
	canvas_cache: []t.Vector2,

	bounds: []Sphere,
	clip_cache: []bool,
	plane_cache: []Plane,

	canvas: canvas.Canvas,
	depth_buffer: []f32
}

intersect_plane_segment :: proc(plane: Plane, a, b: t.Vector3) -> t.Vector3 {
	segment := b - a
	t := -(linalg.dot(plane.normal, a) + plane.offset) / linalg.dot(plane.normal, segment)
	return a + t * segment
}

distance_plane_point :: proc(plane: Plane, point: t.Vector3) -> f32 {
	return linalg.dot(plane.normal, point) + plane.offset
}
clip_distance :: proc(point: t.Vector3, min: f32) -> (plane: Plane, ok: bool) {
	for plane in CAMERA_PLANES {
		distance := distance_plane_point(plane, point)
		if distance < min do return plane, true
	}

	return {}, false
}
clip :: proc(point: t.Vector3) -> (Plane, bool) {
	return clip_distance(point, 0)
}

to_vector2 :: proc(v: t.Vector4) -> t.Vector2 {
	return {int(v.x / v[2]), int(v.y / v[2])}
}
to_vector4 :: proc(v: t.Vector3) -> t.Vector4 {
	return {v.x, v.y, v.z, 1}
}

camera_to_canvas :: proc(point: t.Vector3, camera_inverse: matrix[4, 4]f32) -> t.Vector2 {
	v := camera_inverse * to_vector4(point)
	return to_vector2(v)
}

render_instance :: proc(data: ^Render_Data, index: int) {
	instance := &data.scene.objects[index].(scene.Instance)
	sphere := &data.bounds[index]
	if _, clip := clip_distance(scene.transform_apply(instance.transform, sphere.center), -sphere.radius); clip do return

	// PERF: cache this
	world_to_camera := data.scene.camera.inverse * instance.transform.combined

	for vertex, i in instance.vertecies {
		// PERF: cache these
		transformed := world_to_camera * to_vector4(vertex)
		data.transform_cache[i] = {transformed.x, transformed.y, transformed.z} / transformed.w

		data.plane_cache[i], data.clip_cache[i] = clip(data.transform_cache[i])
		if data.clip_cache[i] do continue

		data.canvas_cache[i] = to_vector2(data.camera_to_canvas * transformed)
	}

	for face, i in instance.faces {
		indecies: [3]int = ---
		clip_indecies: [3]int = ---
		clip_count := 0
		if data.clip_cache[face.a] { clip_indecies[0] = face.a; clip_count = 1 } else { indecies[0] = face.a }
		if data.clip_cache[face.b] { clip_indecies[clip_count] = face.b; clip_count += 1 } else { indecies[1 - clip_count] = face.b }
		if data.clip_cache[face.c] { clip_indecies[clip_count] = face.c; clip_count += 1 } else { indecies[2 - clip_count] = face.c }

		switch clip_count {
		case 0:
			draw_filled_triangle(data,
				data.canvas_cache[face.a], data.canvas_cache[face.b], data.canvas_cache[face.c],
				1 / data.transform_cache[face.a].z, 1 / data.transform_cache[face.b].z, 1 / data.transform_cache[face.c].z,
				face.color
			)
		case 1:
			a, a_canvas := data.transform_cache[indecies[0]], data.canvas_cache[indecies[0]]
			b, b_canvas := data.transform_cache[indecies[1]], data.canvas_cache[indecies[1]]
			c, c_plane := data.transform_cache[clip_indecies[0]], data.plane_cache[clip_indecies[0]]

			ac_intersection := intersect_plane_segment(c_plane, a, c)
			bc_intersection := intersect_plane_segment(c_plane, b, c)

			da := 1 / a.z
			dbc := 1 / bc_intersection.z

			draw_filled_triangle(data,
				a_canvas, camera_to_canvas(ac_intersection, data.camera_to_canvas), camera_to_canvas(bc_intersection, data.camera_to_canvas),
				da, 1 / ac_intersection.z, dbc,
				face.color
			)
			draw_filled_triangle(data,
				a_canvas, b_canvas, camera_to_canvas(bc_intersection, data.camera_to_canvas),
				da, 1 / b.z, dbc,
				face.color
			)
		case 2:
			a, a_canvas := data.transform_cache[indecies[0]], data.canvas_cache[indecies[0]]
			b, b_plane := data.transform_cache[clip_indecies[0]], data.plane_cache[clip_indecies[0]]
			c, c_plane := data.transform_cache[clip_indecies[1]], data.plane_cache[clip_indecies[1]]

			ab_intersection := intersect_plane_segment(b_plane, a, b)
			ac_intersection := intersect_plane_segment(c_plane, a, c)

			draw_filled_triangle(data,
				a_canvas, camera_to_canvas(ab_intersection, data.camera_to_canvas), camera_to_canvas(ac_intersection, data.camera_to_canvas),
				1 / a.z, 1 / ab_intersection.z, 1 / ac_intersection.z,
				face.color
			)
		}
	}
}

render_scene :: proc(data: ^Render_Data) {
	for object, i in data.scene.objects {
		#partial switch o in object {
		case scene.Instance: render_instance(data, i)
		}
	}
}

main :: proc() {
	monkey_model := scene.load_obj("assets/monkey.obj")
	// monkey_model := scene.load_obj("assets/cube.obj")
	for &face, i in monkey_model.faces do face.color = {rand.float32(), rand.float32(), rand.float32()}
	// for &face, i in monkey_model.faces do face.color = {0, 1, 1}
	// monkey_model.faces[0].color = {1, 0, 0} // red
	// monkey_model.faces[1].color = {0, 1, 0} // green
	// monkey_model.faces[2].color = {0, 0, 1} // blue
	// monkey_model.faces[3].color = {1, 1, 0} // yellow
	// monkey_model.faces[4].color = {0, 1, 1} // cyan
	// monkey_model.faces[5].color = {1, 0, 1} // magenta
	// monkey_model.faces[6].color = {1, 0.65, 0} // orange
	// monkey_model.faces[7].color = {0.502, 0, 0.502} // purple
	// monkey_model.faces[8].color = {0.2, 0.81, 0.2} // lime
	// monkey_model.faces[9].color = {0, 0.51, 0.51} // teal
	// monkey_model.faces[10].color = {0.981, 0.502, 0.45} // salmon
	// monkey_model.faces[11].color = {0.44, 0.502, 0.565} // slate gray

	monkey := scene.Instance{
		model = monkey_model,
		transform = {
			position = linalg.matrix4_translate(t.Vector3{0, 0, 2}),
			rotation = linalg.matrix4_rotate(math.PI, t.Vector3{0, 1, 0}),
			scale = linalg.matrix4_scale(f32(1))
		}
	}
	scene.transform_update(&monkey.transform)

	objects := [?]scene.Object{monkey}

	data := Render_Data {
		scene = scene.Scene {
			camera = {
				transform = {
					position = linalg.matrix4_translate(t.Vector3{0, 0, 0}),
					rotation = linalg.matrix4_rotate(0, t.Vector3{0, 1, 0}),
					scale = linalg.matrix4_scale(f32(1))
				}
			},
			objects = objects[:]
		},

		camera_to_canvas = matrix[4, 4]f32{
			VIEWPORT_DISTANCE * CANVAS_WIDTH/VIEWPORT_WIDTH, 0,  0, 0,
			0,  VIEWPORT_DISTANCE * CANVAS_HEIGHT/VIEWPORT_HEIGHT, 0, 0,
			0,  0,  1, 0,
			0,  0,  0, 0
		},

		bounds = make([]Sphere, len(objects)),

		canvas = canvas.create(CANVAS_WIDTH, CANVAS_HEIGHT, CANVAS_OUTPUT),
		depth_buffer = make([]f32, CANVAS_WIDTH * CANVAS_HEIGHT * canvas.CHANNELS)
	}
	scene.camera_update_inverse(&data.scene.camera)

	max_vertex_count := 0
	for object, i in data.scene.objects {
		#partial switch o in object {
		case scene.Instance:
			vertex_count := len(o.vertecies)
			if vertex_count > max_vertex_count do max_vertex_count = vertex_count

			bounds := &data.bounds[i]
			for vertex in o.vertecies do bounds.center += vertex
			bounds.center /= f32(vertex_count)
			for vertex in o.vertecies {
				distance := linalg.distance(bounds.center, vertex)
				if distance > bounds.radius do bounds.radius = distance
			}
		}
	}
	data.transform_cache = make([]t.Vector3, max_vertex_count)
	data.clip_cache = make([]bool, max_vertex_count)
	data.plane_cache = make([]Plane, max_vertex_count)
	data.canvas_cache = make([]t.Vector2, max_vertex_count)

	canvas.clear(&data.canvas, {0.2, 0.2, 0.2})
	render_scene(&data)
	canvas.flush(&data.canvas)
}
