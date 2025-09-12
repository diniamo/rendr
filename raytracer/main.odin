package raytracer

import "core:fmt"
import "core:math"
import "core:math/linalg"
import t "common:types"
import "common:canvas"

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

Camera :: struct {
	using position: t.Vector3,
	rotation: quaternion128
}

Material :: struct {
	color: t.Color,
	// The exponent used for specular reflection
	specularity: f32,
	reflectiveness: f32
}
Sphere :: struct {
	center: t.Vector3,
	radius: f32,

	using material: Material
}

Ambient_Light :: struct{
	intensity: f32
}
Point_Light :: struct {
	intensity: f32,
	position: t.Vector3
}
Directional_Light :: struct {
	intensity: f32,
	direction: t.Vector3
}
Light :: union {
	Ambient_Light,
	Point_Light,
	Directional_Light
}

Intersection :: struct {
	coefficient: f32,
	sphere: Sphere
}

canvas_to_viewport :: proc(from: t.Vector2) -> t.Vector3 {
	return {
		f32(from.x) * VIEWPORT_WIDTH/CANVAS_WIDTH,
		f32(from.y) * VIEWPORT_HEIGHT/CANVAS_HEIGHT,
		VIEWPORT_DISTANCE
	}
}

intersect_ray :: proc(origin, direction: t.Vector3, minimum_coefficient: f32, spheres: []Sphere) -> Intersection {
	intersection := Intersection{coefficient = max(f32)}

	for sphere in spheres {
		center_to_origin := origin - sphere.center

		a := linalg.dot(direction, direction)
		b := 2 * linalg.dot(direction, center_to_origin)
		c := linalg.dot(center_to_origin, center_to_origin) - sphere.radius*sphere.radius

		discriminant := b*b - 4*a*c
		if discriminant < 0 do continue
		root_term := math.sqrt(b*b - 4*a*c)

		c1 := (-b - root_term) / (2*a)
		c2 := (-b + root_term) / (2*a)

		if c1 >= minimum_coefficient && c1 < intersection.coefficient {
			intersection.coefficient = c1
			intersection.sphere = sphere
		} else if c2 >= minimum_coefficient && c2 < intersection.coefficient {
			intersection.coefficient = c2
			intersection.sphere = sphere
		}
	}

	return intersection
}

trace_ray :: proc(origin, direction: t.Vector3, minimum_coefficient: f32, spheres: []Sphere, lights: []Light, level: int) -> t.Color {
	intersection := intersect_ray(origin, direction, minimum_coefficient, spheres)
	if intersection.coefficient == max(f32) do return VOID_COLOR

	position := origin + intersection.coefficient*direction
	normal := linalg.normalize(position - intersection.sphere.center)
	position_to_camera := -direction
	position_to_camera_length := linalg.length(position_to_camera)

	intensity: f32 = 0
	for light in lights {
		light_vector: t.Vector3
		local_intensity: f32

		switch l in light {
		case Ambient_Light:
			intensity += l.intensity
			continue
		case Point_Light:
			light_vector = l.position - position
			light_intersection := intersect_ray(position, light_vector, OFFSET_COEFFICIENT, spheres)
			if light_intersection.coefficient <= 1 do continue

			local_intensity = l.intensity
		case Directional_Light:
			light_vector = l.direction
			light_intersection := intersect_ray(position, light_vector, OFFSET_COEFFICIENT, spheres)
			if light_intersection.coefficient < max(f32) do continue

			local_intensity = l.intensity
		}

		ndl := linalg.dot(normal, light_vector)
		if ndl > 0 {
			// No need to divide by the length of the normal, since it's normalized
			scale := ndl / linalg.length(light_vector)
			intensity += scale * local_intensity
		}

		if intersection.sphere.specularity > 0 {
			light_parallel := ndl * normal
			light_perpendicular := light_parallel - light_vector
			reflection_vector := light_parallel + light_perpendicular

			rdc := linalg.dot(reflection_vector, position_to_camera)
			if rdc > 0 {
				scale := math.pow(rdc / (linalg.length(reflection_vector)*position_to_camera_length), intersection.sphere.specularity)
				intensity += scale * local_intensity
			}
		}
	}

	color := intersection.sphere.color * min(intensity, 1)

	if intersection.sphere.reflectiveness > 0 && level <= RECURSION_LIMIT {
		reflection_parallel := linalg.dot(position_to_camera, normal) * normal
		reflection_perpendicular := reflection_parallel - position_to_camera
		reflection_vector := reflection_parallel + reflection_perpendicular

		reflection := trace_ray(position, reflection_vector, OFFSET_COEFFICIENT, spheres, lights, level + 1)
		color = (1 - intersection.sphere.reflectiveness) * color + intersection.sphere.reflectiveness * reflection
	}

	return color
}

main :: proc() {
	target := canvas.create(CANVAS_WIDTH, CANVAS_HEIGHT, OUTPUT_PATH)
	defer {
		canvas.flush(target)
		canvas.destroy(target)
	}

	camera_angle := -math.PI / 4
	camera := Camera {
		position = {2.5, 0, 1.5},
		rotation = linalg.quaternion_angle_axis(-math.PI / 4, t.Vector3{0, 1, 0})
	}

	spheres := [?]Sphere{
		{{0, -1, 3},    1,    {{1, 0, 0}, 500, 0.2}},
		{{2, 0, 4},     1,    {{0, 0, 1}, 500, 0.3}},
		{{-2, 0, 4},    1,    {{0, 1, 0}, 10, 0.4}},
		{{0, -5001, 0}, 5000, {{1, 1, 0}, 1000, 0.5}}
	}

	lights := [?]Light{
		    Ambient_Light{0.2},
		      Point_Light{0.6, {2, 1, 0}},
		Directional_Light{0.2, {1, 4, 4}}
	}

	for x in (-CANVAS_WIDTH/2)..<(CANVAS_WIDTH/2) {
		for y in (-CANVAS_HEIGHT/2 + 1)..=(CANVAS_HEIGHT/2) {
			viewport_position := camera.position + linalg.quaternion_mul_vector3(camera.rotation, canvas_to_viewport(t.Vector2{x, y}))
			direction := viewport_position - camera.position
			color := trace_ray(camera.position, direction, 1, spheres[:], lights[:], 0)

			canvas.pixel(target, x, y, color)
		}
	}
}
