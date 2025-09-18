package raytracer

import "core:os"
import "core:thread"
import "core:sync/chan"
import "core:math"
import "core:math/rand"
import "core:math/linalg"
import t "common:types"
import "common:canvas"
import "common:scene"

CANVAS_WIDTH :: 600
CANVAS_HEIGHT :: 600
OUTPUT_PATH :: "output.png"

VIEWPORT_WIDTH :: 1
VIEWPORT_HEIGHT :: 1
VIEWPORT_DISTANCE :: 1

VOID_COLOR :: t.Color{0, 0, 0}

// The minimum coefficient to use when raycasting from collision points
OFFSET_COEFFICIENT :: 0.05
// Recursion limit for reflections
RECURSION_LIMIT :: 3

Task_Data :: struct {
	task_chan: chan.Chan(t.Vector2),
	scene: ^scene.Scene,
	target: ^canvas.Canvas
}

canvas_to_viewport :: proc(camera: scene.Camera, from: t.Vector2) -> t.Vector3 {
	scaled := t.Vector3{
		f32(from.x) * VIEWPORT_WIDTH/CANVAS_WIDTH,
		f32(from.y) * VIEWPORT_HEIGHT/CANVAS_HEIGHT,
		VIEWPORT_DISTANCE
	}
	rotated := linalg.quaternion_mul_vector3(camera.rotation, scaled)
	offset := camera.position + rotated

	return offset
}

compute_light :: proc(intersection: Intersection, origin_direction: t.Vector3, origin_direction_length: f32, lights: []scene.Light, objects: []scene.Object) -> f32 {
	intensity: f32 = 0

	for light in lights {
		light_vector: t.Vector3
		local_intensity: f32

		switch l in light {
		case scene.Ambient_Light:
			intensity += l.intensity
			continue
		case scene.Point_Light:
			light_vector = l.position - intersection.position
			light_intersection := intersect_ray(intersection.position, light_vector, objects, OFFSET_COEFFICIENT)
			if light_intersection.coefficient <= 1 do continue

			local_intensity = l.intensity
		case scene.Directional_Light:
			light_vector = l.direction
			light_intersection := intersect_ray(intersection.position, light_vector, objects, OFFSET_COEFFICIENT)
			if light_intersection.coefficient < max(f32) do continue

			local_intensity = l.intensity
		}

		ndl := linalg.dot(intersection.normal, light_vector)
		if ndl > 0 {
			// No need to divide by the length of the normal, since it's normalized
			scale := ndl / linalg.length(light_vector)
			intensity += scale * local_intensity
		}

		if intersection.material.specularity > 0 {
			light_parallel := ndl * intersection.normal
			light_perpendicular := light_parallel - light_vector
			reflection_vector := light_parallel + light_perpendicular

			rdc := linalg.dot(reflection_vector, origin_direction)
			if rdc > 0 {
				scale := math.pow(rdc / (linalg.length(reflection_vector)*origin_direction_length), intersection.material.specularity)
				intensity += scale * local_intensity
			}
		}
	}

	return intensity
}

trace_ray :: proc(origin, direction: t.Vector3, minimum_coefficient: f32, objects: []scene.Object, lights: []scene.Light, level: int) -> t.Color {
	intersection := intersect_ray(origin, direction, objects, minimum_coefficient)
	if intersection.coefficient == max(f32) do return VOID_COLOR

	origin_direction := -direction
	intensity := compute_light(intersection, origin_direction, linalg.length(origin_direction), lights, objects)

	color := intersection.material.color * min(intensity, 1)

	if intersection.material.reflectiveness > 0 && level <= RECURSION_LIMIT {
		reflection_parallel := linalg.dot(origin_direction, intersection.normal) * intersection.normal
		reflection_perpendicular := reflection_parallel - origin_direction
		reflection_vector := reflection_parallel + reflection_perpendicular

		reflection := trace_ray(intersection.position, reflection_vector, OFFSET_COEFFICIENT, objects, lights, level + 1)
		color = (1 - intersection.material.reflectiveness) * color + intersection.material.reflectiveness * reflection
	}

	return color
}

worker :: proc(task: thread.Task) {
	data := cast(^Task_Data)task.data
	scene := data.scene

	for pixel in chan.recv(data.task_chan) {
		viewport_position := canvas_to_viewport(scene.camera, pixel)
		direction := viewport_position - scene.camera.position
		color := trace_ray(scene.camera.position, direction, 1, scene.objects, scene.lights, 1)

		canvas.pixel(data.target, pixel.x, pixel.y, color)
	}
}

main :: proc() {
	monkey_mesh := scene.load_obj("assets/monkey.obj")
	defer delete(monkey_mesh)
	for &face in monkey_mesh do face.color = {rand.float32(), rand.float32(), rand.float32()}
	monkey := scene.Model{
		position = t.Vector3{0, 0.5, 4},
		rotation = linalg.quaternion_angle_axis(math.PI, t.Vector3{0, 1, 0}),
		mesh = monkey_mesh
	}

	objects := [?]scene.Object{
		scene.Sphere{{0, -1, 3},    1,    {{1, 0, 0}, 500, 0.2}},
		scene.Sphere{{2, 0, 4},     1,    {{0, 0, 1}, 500, 0.3}},
		scene.Sphere{{-2, 0, 4},    1,    {{0, 1, 0}, 10, 0.4}},
		scene.Sphere{{0, -5001, 0}, 5000, {{1, 1, 0}, 1000, 0.5}},
		monkey
	}

	lights := [?]scene.Light{
		    scene.Ambient_Light{0.2},
		      scene.Point_Light{0.6, {2, 1, 0}},
		scene.Directional_Light{0.2, {1, 4, 4}}
	}

	scene := scene.Scene {
		camera = {
			position = {2.5, 0, 1.5},
			rotation = linalg.quaternion_angle_axis(-math.PI / 4, t.Vector3{0, 1, 0})
		},
		objects = objects[:],
		lights = lights[:]
	}

	target := canvas.create(CANVAS_WIDTH, CANVAS_HEIGHT, OUTPUT_PATH)
	defer {
		canvas.flush(&target)
		canvas.destroy(&target)
	}

	// -1 since the main thread is dispatching coordinates
	worker_count := os.processor_core_count() - 1

	pool: thread.Pool
	thread.pool_init(&pool, context.allocator, worker_count)
	defer thread.pool_destroy(&pool)

	task_chan, _ := chan.create(chan.Chan(t.Vector2), context.allocator)

	data := Task_Data {
		task_chan = task_chan,
		scene = &scene,
		target = &target
	}
	for _ in 0..<worker_count do thread.pool_add_task(&pool, context.allocator, worker, &data)

	thread.pool_start(&pool)
	for x in -CANVAS_WIDTH/2..<CANVAS_WIDTH/2 {
		for y in -CANVAS_HEIGHT/2 + 1..=CANVAS_HEIGHT/2 {
			chan.send(task_chan, t.Vector2{f32(x), f32(y)})
			thread.yield()
		}
	}

	chan.close(task_chan)
	thread.pool_join(&pool)
}
