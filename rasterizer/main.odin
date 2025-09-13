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

VIEWPORT_DISTANCE :: 1
VIEWPORT_WIDTH :: 2 * VIEWPORT_DISTANCE
VIEWPORT_HEIGHT :: 2 * VIEWPORT_DISTANCE

IST :: 1 / math.SQRT_TWO
CAMERA_PLANES :: [?]Plane{
	{{}, {0, 0, 1}, -VIEWPORT_DISTANCE},
	{{}, {IST, 0, IST}, 0},
	{{}, {-IST, 0, IST}, 0},
	{{}, {0, -IST, IST}, 0},
	{{}, {0, IST, IST}, 0}
}

Plane :: struct {
	canvas: t.Vector2,
	normal: t.Vector3,
	offset: f32
}

Sphere :: struct {
	center: t.Vector3,
	radius: f32
}

Render_Data :: struct {
	scene: scene.Scene,

	camera_to_canvas: matrix[4, 4]f32,
	canvas_to_camera: matrix[4, 4]f32,

	bounds: []Sphere,
	transform_cache: []t.Vector3,
	normal_cache: []t.Vector3,
	canvas_cache: []t.Vector2,

	canvas: canvas.Canvas,
	depth_buffer: []f32
}

intersect_near_plane :: proc(a, b: t.Vector3) -> (f32, t.Vector3) {
	segment := b - a
	t := (VIEWPORT_DISTANCE - a.z) / segment.z
	return t, a + t * segment
}

distance_plane_point :: proc(plane: Plane, point: t.Vector3) -> f32 {
	return linalg.dot(plane.normal, point) + plane.offset
}
clip_distance :: proc(point: t.Vector3, min: f32) -> (Plane, bool) {
	for plane in CAMERA_PLANES {
		distance := distance_plane_point(plane, point)
		if distance < min do return plane, true
	}

	return {}, false
}

to_vector2 :: proc(v: t.Vector4) -> t.Vector2 {
	return {int(v.x / v[2]), int(v.y / v[2])}
}
to_vector3 :: proc(v: t.Vector4) -> t.Vector3 {
	return {v.x, v.y, v.z} / v.w
}
to_vector4 :: proc(v: t.Vector3) -> t.Vector4 {
	return {v.x, v.y, v.z, 1}
}

camera_to_canvas :: proc(point: t.Vector3, camera_to_canvas: matrix[4, 4]f32) -> t.Vector2 {
	v := camera_to_canvas * to_vector4(point)
	return to_vector2(v)
}

compute_light :: proc(point, normal: t.Vector3, camera: scene.Camera, lights: []scene.Light, material: scene.Material) -> f32 {
	intensity: f32 = 0

	for light in lights {
		light_vector: t.Vector3
		local_intensity: f32

		switch l in light {
		case scene.Ambient_Light:
			intensity += l.intensity
			continue
		case scene.Point_Light:
			light_vector = scene.matrix_apply(camera.inverse, l.position) - point
			local_intensity = l.intensity
		case scene.Directional_Light:
			light_vector = scene.matrix_apply(camera.inverse_vector, l.direction)
			local_intensity = l.intensity
		}

		ndl := linalg.dot(normal, light_vector)
		if ndl > 0 {
			// No need to divide by the length of the normal, since it's normalized
			scale := ndl / linalg.length(light_vector)
			intensity += scale * local_intensity
		}

		if material.specularity > 0 {
			// The normal is assumed to be normalized here as well
			reflection_vector := 2 * ndl * normal - light_vector

			// We are in camera space, so the camera is at (0, 0, 0)
			point_to_camera := -point
			rdc := linalg.dot(reflection_vector, point_to_camera)
			if rdc > 0 {
				scale := math.pow(rdc / (linalg.length(reflection_vector)*linalg.length(point_to_camera)), material.specularity)
				intensity += scale * local_intensity
			}
		}
	}

	return min(intensity, 1)
}

render_instance :: proc(data: ^Render_Data, index: int) {
	instance := &data.scene.objects[index].(scene.Instance)
	sphere := &data.bounds[index]
	if _, clip := clip_distance(scene.transform_apply(instance.transform, sphere.center), -sphere.radius); clip do return

	local_to_camera := data.scene.camera.inverse * instance.transform.combined
	for vertex, i in instance.vertecies {
		transformed := local_to_camera * to_vector4(vertex)
		transformed /= transformed.w
		data.transform_cache[i] = swizzle(transformed, 0, 1, 2)

		if transformed.z >= VIEWPORT_DISTANCE do data.canvas_cache[i] = to_vector2(data.camera_to_canvas * transformed)
	}

	local_to_camera_vector := data.scene.camera.inverse_vector * instance.transform.combined_vector
	for normal, i in instance.normals {
		data.normal_cache[i] = linalg.normalize(scene.matrix_apply(local_to_camera_vector, normal))
	}

	for face, i in instance.faces {
		// Only clip the near plane, since the rest is cheaper to do in the triangle draw function
		clip_a := data.transform_cache[face.a].z < VIEWPORT_DISTANCE
		clip_b := data.transform_cache[face.b].z < VIEWPORT_DISTANCE
		clip_c := data.transform_cache[face.c].z < VIEWPORT_DISTANCE

		// Clipped indecies sorted to the right
		vi: [3]int = ---
		vni: [3]int = ---
		clip_count: int = ---
		{
			using face

			if clip_a {
				if clip_b {
					if clip_c do continue

					vi = {c, a, b}
					vni = {cn, an, bn}
					clip_count = 2
				} else if clip_c {
					vi = {b, c, a}
					vni = {bn, cn, an}
					clip_count = 2
				} else {
					vi = {b, c, a}
					vni = {bn, cn, an}
					clip_count = 1
				}
			} else if clip_b {
				if clip_c {
					vi = {a, b, c}
					vni = {an, bn, cn}
					clip_count = 2
				} else {
					vi = {c, a, b}
					vni = {cn, an, bn}
					clip_count = 1
				}
			} else if clip_c {
				vi = {a, b, c}
				vni = {an, bn, cn}
				clip_count = 1
			} else {
				vi = {a, b, c}
				vni = {an, bn, cn}
				clip_count = 0
			}
		}

		switch clip_count {
		case 0:
			a := data.transform_cache[vi[0]]
			b := data.transform_cache[vi[1]]
			c := data.transform_cache[vi[2]]

			draw_filled_triangle(data,
				data.canvas_cache[vi[0]], data.canvas_cache[vi[1]], data.canvas_cache[vi[2]],
				1/a.z, 1/b.z, 1/c.z,
				data.normal_cache[vni[0]], data.normal_cache[vni[1]], data.normal_cache[vni[2]],
				instance.materials[i]
			)
		case 1:
			a, a_canvas := data.transform_cache[vi[0]], data.canvas_cache[vi[0]]
			b, b_canvas := data.transform_cache[vi[1]], data.canvas_cache[vi[1]]
			c := data.transform_cache[vi[2]]

			tac, ac := intersect_near_plane(a, c)
			tbc, bc := intersect_near_plane(b, c)

			ac_canvas := camera_to_canvas(ac, data.camera_to_canvas)
			bc_canvas := camera_to_canvas(bc, data.camera_to_canvas)

			db := 1 / b.z
			dac := 1 / ac.z

			na := data.normal_cache[vni[0]]
			nb := data.normal_cache[vni[1]]
			nc := data.normal_cache[vni[2]]
			nac := (1 - tac) * na + tac * nc
			nbc := (1 - tac) * nb + tac * nc

			material := instance.materials[i]

			draw_filled_triangle(data,
				a_canvas, b_canvas, ac_canvas,
				1/a.z, db, dac,
				na, nb, nac,
				material
			)
			draw_filled_triangle(data,
				b_canvas, bc_canvas, ac_canvas,
				db, 1/bc.z, dac,
				nb, nbc, nac,
				material
			)
		case 2:
			a, a_canvas := data.transform_cache[vi[0]], data.canvas_cache[vi[0]]
			tb, b := intersect_near_plane(a, data.transform_cache[vi[1]])
			tc, c := intersect_near_plane(a, data.transform_cache[vi[2]])

			na := data.normal_cache[vni[0]]
			nb := (1 - tb) * na + tb * data.normal_cache[vni[1]]
			nc := (1 - tc) * na + tc * data.normal_cache[vni[2]]

			draw_filled_triangle(data,
				a_canvas, camera_to_canvas(b, data.camera_to_canvas), camera_to_canvas(c, data.camera_to_canvas),
				1/a.z, 1/b.z, 1/c.z,
				na, nb, nc,
				instance.materials[i]
			)
		}
	}
}

render_scene :: proc(data: ^Render_Data) {
	for object, i in data.scene.objects {
		#partial switch _ in object {
		case scene.Instance:
			render_instance(data, i)
		}
	}
}

main :: proc() {
	data := Render_Data {
		scene = scene.example_scene(),

		// If I don't cast to float, Odin isn't smart enough to figure out that the result is a float,
		// so it just divides the constants as integers, and then converts them to floats,
		// and the matricies end up with mostly 0s. Sigh.
		camera_to_canvas = matrix[4, 4]f32{
			f32(VIEWPORT_DISTANCE) * CANVAS_WIDTH/VIEWPORT_WIDTH, 0, 0, 0,
			0, f32(VIEWPORT_DISTANCE) * CANVAS_HEIGHT/VIEWPORT_HEIGHT, 0, 0,
			0, 0, 1, 0,
			0, 0, 0, 0
		},
		canvas_to_camera = matrix[4, 4]f32{
			f32(VIEWPORT_WIDTH)/(CANVAS_WIDTH * VIEWPORT_DISTANCE), 0, 0, 0,
			0, f32(VIEWPORT_HEIGHT)/(CANVAS_HEIGHT * VIEWPORT_DISTANCE), 0, 0,
			0, 0, 1, 0,
			0, 0, 0, 1
		},

		canvas = canvas.create(CANVAS_WIDTH, CANVAS_HEIGHT, CANVAS_OUTPUT),
		depth_buffer = make([]f32, CANVAS_WIDTH * CANVAS_HEIGHT * canvas.CHANNELS)
	}

	data.bounds = make([]Sphere, len(data.scene.objects))
	scene.camera_update_inverse(&data.scene.camera)

	sphere_model := scene.load_obj("assets/sphere.obj")

	max_vertex_count := 0
	max_normal_count := 0
	for &object, i in data.scene.objects {
		switch &o in object {
		case scene.Sphere:
			instance := scene.Instance{
				transform = {
					position = linalg.matrix4_translate(o.center),
					rotation = linalg.identity(matrix[4, 4]f32),
					scale = linalg.matrix4_scale(o.radius)
				},
				model = sphere_model,
				materials = make([]scene.Material, len(sphere_model.faces))
			}
			scene.transform_update(&instance.transform)
			for &material in instance.materials do material = o.material

			data.bounds[i].radius = o.radius
			if len(sphere_model.vertecies) > max_vertex_count do max_vertex_count = len(sphere_model.vertecies)
			if len(sphere_model.normals) > max_normal_count do max_normal_count = len(sphere_model.normals)

			object = instance
		case scene.Instance:
			vertex_count := len(o.vertecies)
			if vertex_count > max_vertex_count do max_vertex_count = vertex_count
			if len(o.normals) > max_normal_count do max_normal_count = len(o.normals)

			bounds := &data.bounds[i]
			for vertex in o.vertecies do bounds.center += vertex
			bounds.center /= f32(vertex_count)
			for vertex in o.vertecies {
				distance := linalg.distance(bounds.center, vertex)
				if distance > bounds.radius do bounds.radius = distance
			}

			scene.transform_update(&o.transform)
		}
	}
	data.transform_cache = make([]t.Vector3, max_vertex_count)
	data.normal_cache = make([]t.Vector3, max_normal_count)
	data.canvas_cache = make([]t.Vector2, max_vertex_count)

	render_scene(&data)
	canvas.flush(&data.canvas)
}
