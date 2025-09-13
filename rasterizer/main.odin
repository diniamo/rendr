package rasterizer

import "core:io"
import "core:os"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "common:canvas"
import t "common:types"
import "common:scene"

CANVAS_WIDTH :: 2000
CANVAS_HEIGHT :: 2000
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
	canvas: t.Vector2i,
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
	canvas_cache: []t.Vector2i,

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

to_vector2 :: proc(v: t.Vector4) -> t.Vector2i {
	return {int(v.x / v[2]), int(v.y / v[2])}
}
to_vector3 :: proc(v: t.Vector4) -> t.Vector3 {
	return {v.x, v.y, v.z} / v.w
}
to_vector4 :: proc(v: t.Vector3) -> t.Vector4 {
	return {v.x, v.y, v.z, 1}
}

camera_to_canvas :: proc(point: t.Vector3, camera_to_canvas: matrix[4, 4]f32) -> t.Vector2i {
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

	for unsorted_face, i in instance.faces {
		// Only clip the near plane, since the rest is cheaper to do in the triangle draw function
		clip_a := data.transform_cache[unsorted_face.a].z < VIEWPORT_DISTANCE
		clip_b := data.transform_cache[unsorted_face.b].z < VIEWPORT_DISTANCE
		clip_c := data.transform_cache[unsorted_face.c].z < VIEWPORT_DISTANCE

		// Clipped indecies sorted towards c
		face: scene.Face = ---
		clip_count: int = ---
		{
			using unsorted_face

			if clip_a {
				if clip_b {
					if clip_c do continue

					face = {
						c, ct, cn,
						a, at, an,
						b, bt, bn
					}
					clip_count = 2
				} else if clip_c {
					face = {
						b, bt, bn,
						c, ct, cn,
						a, at, an
					}
					clip_count = 2
				} else {
					face = {
						b, bt, bn,
						c, ct, cn,
						a, at, an
					}
					clip_count = 1
				}
			} else if clip_b {
				if clip_c {
					face = {
						a, at, an,
						b, bt, bn,
						c, ct, cn
					}
					clip_count = 2
				} else {
					face = {
						c, ct, cn,
						a, at, an,
						b, bt, bn
					}
					clip_count = 1
				}
			} else if clip_c {
				face = {
					a, at, an,
					b, bt, bn,
					c, ct, cn
				}
				clip_count = 1
			} else {
				face = {
					a, at, an,
					b, bt, bn,
					c, ct, cn
				}
				clip_count = 0
			}
		}

		switch clip_count {
		case 0:
			draw_filled_triangle(data,
				data.canvas_cache[face.a], data.canvas_cache[face.b], data.canvas_cache[face.c],
				instance.texels[face.at], instance.texels[face.bt], instance.texels[face.ct],
				data.normal_cache[face.an], data.normal_cache[face.bn], data.normal_cache[face.cn],
				1/data.transform_cache[face.a].z, 1/data.transform_cache[face.b].z, 1/data.transform_cache[face.c].z,
				scene.resolve_material(instance.material, i),
				instance.texture
			)
		case 1:
			a, a_canvas := data.transform_cache[face.a], data.canvas_cache[face.a]
			b, b_canvas := data.transform_cache[face.b], data.canvas_cache[face.b]
			c := data.transform_cache[face.c]

			tac, ac := intersect_near_plane(a, c); ctac := 1 - tac
			tbc, bc := intersect_near_plane(b, c); ctbc := 1 - tbc

			ac_canvas := camera_to_canvas(ac, data.camera_to_canvas)
			bc_canvas := camera_to_canvas(bc, data.camera_to_canvas)

			at := instance.texels[face.at]
			bt := instance.texels[face.bt]
			ct := instance.texels[face.ct]
			act := ctac * at + tac * ct
			bct := ctbc * bt + tbc * ct

			an := data.normal_cache[face.an]
			bn := data.normal_cache[face.bn]
			cn := data.normal_cache[face.cn]
			acn := ctac * an + tac * cn
			bcn := ctbc * bn + tbc * cn

			bd := 1 / b.z
			acd := 1 / ac.z

			draw_filled_triangle(data,
				a_canvas, b_canvas, ac_canvas,
				at, bt, act,
				an, bn, acn,
				1/a.z, bd, acd,
				scene.resolve_material(instance.material, i),
				instance.texture
			)
			draw_filled_triangle(data,
				b_canvas, bc_canvas, ac_canvas,
				bt, bct, act,
				bn, bcn, acn,
				bd, 1/bc.z, acd,
				scene.resolve_material(instance.material, i),
				instance.texture
			)
		case 2:
			a, a_canvas := data.transform_cache[face.a], data.canvas_cache[face.a]
			tb, b := intersect_near_plane(a, data.transform_cache[face.b]); ctb := 1 - tb
			tc, c := intersect_near_plane(a, data.transform_cache[face.c]); ctc := 1 - tc

			at := instance.texels[face.at]
			bt := ctb * at + tb * instance.texels[face.bt]
			ct := ctc * at + tc * instance.texels[face.ct]

			an := data.normal_cache[face.an]
			bn := ctb * an + tb * data.normal_cache[face.bn]
			cn := ctc * an + tc * data.normal_cache[face.cn]

			draw_filled_triangle(data,
				a_canvas, camera_to_canvas(b, data.camera_to_canvas), camera_to_canvas(c, data.camera_to_canvas),
				at, bt, ct,
				an, bn, cn,
				1/a.z, 1/b.z, 1/c.z,
				scene.resolve_material(instance.material, i),
				instance.texture
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
		scene = scene.crate(),

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
				material = o.material
			}
			scene.transform_update(&instance.transform)

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
	data.canvas_cache = make([]t.Vector2i, max_vertex_count)

	render_scene(&data)

	canvas.flush(&data.canvas)
}
