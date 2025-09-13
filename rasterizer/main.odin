package rasterizer

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
	camera_rotation_inverse: matrix[3, 3]f32,
	bounds: []Sphere,
	transform_cache: []t.Vector3,
	clip_cache: []bool,
	plane_cache: []Plane,
	canvas_cache: []t.Vector2
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

clip :: #force_inline proc(point: t.Vector3) -> (Plane, bool) {
	return clip_distance(point, 0)
}

local_to_world :: proc(point: t.Vector3, transform: scene.Transform) -> t.Vector3 {
	return transform.rotation * (transform.scale * point) + transform.position
}

world_to_camera :: proc(point: t.Vector3, transform: scene.Transform, camera_position: t.Vector3, camera_rotation_inverse: matrix[3, 3]f32) -> t.Vector3 {
	transform_applied := local_to_world(point, transform)
	camera_applied := camera_rotation_inverse * (transform_applied - camera_position)

	return camera_applied
}

camera_to_canvas :: proc(point: t.Vector3) -> t.Vector2 {
	on_viewport := (VIEWPORT_DISTANCE / point.z) * t.Vector2{point.x, point.y}
	return {
		CANVAS_WIDTH/VIEWPORT_WIDTH * on_viewport.x,
		CANVAS_HEIGHT/VIEWPORT_HEIGHT * on_viewport.y
	}
}

render_instance :: proc(target: ^canvas.Canvas, s: scene.Scene, data: Render_Data, index: int) {
	instance := &s.objects[index].(scene.Instance)
	sphere := &data.bounds[index]
	if _, clip := clip_distance(local_to_world(sphere.center, instance.transform), -sphere.radius); clip do return

	/* Matracies are normally used for transforming points, but it complicates things here pointlessly, and is slower without caching
	// These matracies are normally cached and updated only when needed
	instance_scale := linalg.matrix4_scale(t.Vector3{instance.scale, instance.scale, instance.scale})
	instance_rotate := linalg.to_matrix4(instance.rotation)
	instance_translate := linalg.matrix4_translate(instance.transform.position)
	camera_translate := linalg.matrix4_translate(-s.camera.position)
	camera_rotate := linalg.to_matrix4(data.camera_rotation_inverse)

	cx :: VIEWPORT_DISTANCE * (CANVAS_WIDTH + CANVAS_PADDING)/VIEWPORT_WIDTH
	cy :: VIEWPORT_DISTANCE * (CANVAS_HEIGHT + CANVAS_PADDING)/VIEWPORT_HEIGHT
	world_to_canvas := matrix[4, 4]f32{
		cx, 0,  0, 0,
		0,  cy, 0, 0,
		0,  0,  1, 0,
		0,  0,  0, 0
	}

	transform := world_to_canvas * camera_rotate * camera_translate * instance_translate * instance_rotate * instance_scale

	for vertex, i in instance.vertecies {
		h := transform * [4]f32{vertex[0], vertex[1], vertex[2], 1}
		data.canvas_cache[i] = {h[0], h[1]} / h[2]
	}
	*/

	for vertex, i in instance.vertecies {
		data.transform_cache[i] = world_to_camera(vertex, instance.transform, s.camera.position, data.camera_rotation_inverse)

		data.plane_cache[i], data.clip_cache[i] = clip(data.transform_cache[i])
		if data.clip_cache[i] do continue

		data.canvas_cache[i] = camera_to_canvas(data.transform_cache[i])
	}

	for face in instance.faces {
		indecies: [3]int = ---
		clip_indecies: [3]int = ---
		clip_count := 0
		if data.clip_cache[face.a] { clip_indecies[0] = face.a; clip_count = 1 } else { indecies[0] = face.a }
		if data.clip_cache[face.b] { clip_indecies[clip_count] = face.b; clip_count += 1 } else { indecies[1 - clip_count] = face.b }
		if data.clip_cache[face.c] { clip_indecies[clip_count] = face.c; clip_count += 1 } else { indecies[2 - clip_count] = face.c }

		switch clip_count {
		case 0:
			draw_wireframe_triangle(target,
				data.canvas_cache[face.a],
				data.canvas_cache[face.b],
				data.canvas_cache[face.c],
				face.color
			)
		case 1:
			a, a_canvas := data.transform_cache[indecies[0]], data.canvas_cache[indecies[0]]
			b, b_canvas := data.transform_cache[indecies[1]], data.canvas_cache[indecies[1]]
			c, c_plane := data.transform_cache[clip_indecies[0]], data.plane_cache[clip_indecies[0]]

			ac_intersection := intersect_plane_segment(c_plane, a, c)
			bc_intersection := intersect_plane_segment(c_plane, b, c)

			draw_wireframe_triangle(target,
				a_canvas,
				camera_to_canvas(ac_intersection),
				camera_to_canvas(bc_intersection),
				face.color
			)
			draw_wireframe_triangle(target,
				a_canvas,
				b_canvas,
				camera_to_canvas(bc_intersection),
				face.color
			)
		case 2:
			a, a_canvas := data.transform_cache[indecies[0]], data.canvas_cache[indecies[0]]
			b, b_plane := data.transform_cache[clip_indecies[0]], data.plane_cache[clip_indecies[0]]
			c, c_plane := data.transform_cache[clip_indecies[1]], data.plane_cache[clip_indecies[1]]

			ab_intersection := intersect_plane_segment(b_plane, a, b)
			ac_intersection := intersect_plane_segment(c_plane, a, c)

			draw_wireframe_triangle(target,
				a_canvas,
				camera_to_canvas(ab_intersection),
				camera_to_canvas(ac_intersection),
				face.color
			)
		}
	}
}

render_scene :: proc(target: ^canvas.Canvas, s: scene.Scene, data: Render_Data) {
	for object, i in s.objects {
		#partial switch o in object {
		case scene.Instance: render_instance(target, s, data, i)
		}
	}
}

main :: proc() {
	monkey_model := scene.load_obj("assets/monkey.obj")
	for &face in monkey_model.faces do face.color = {rand.float32(), rand.float32(), rand.float32()}

	objects := [?]scene.Object{
		scene.Instance{
			model = monkey_model,
			transform = {
				position = t.Vector3{1.5, -0.5, 3},
				rotation = linalg.matrix3_rotate(math.PI, t.Vector3{0, 1, 0}),
				scale = 1
			}
		}
	}

	s := scene.Scene {
		camera = {
			position = {2.5, 0, 1.5},
			rotation = linalg.matrix3_rotate(-math.PI / 4, t.Vector3{0, 1, 0}),
		},
		objects = objects[:]
	}

	target := canvas.create(CANVAS_WIDTH, CANVAS_HEIGHT, CANVAS_OUTPUT)
	defer canvas.flush(&target)

	data := Render_Data {
		camera_rotation_inverse = linalg.transpose(s.camera.rotation),
		bounds = make([]Sphere, len(objects))
	}
	max_vertex_count := 0
	for object, i in s.objects {
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

	render_scene(&target, s, data)
}
