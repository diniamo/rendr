package raytracer

import "core:math"
import "core:math/linalg"
import t "common:types"
import "common:scene"

Intersection :: struct {
	coefficient: f32,
	position: t.Vector3,
	normal: t.Vector3,
	material: scene.Material
}

intersect_sphere :: proc(origin, direction: t.Vector3, minimum_coefficient: f32, sphere: scene.Sphere) -> Intersection {
	intersection := Intersection{coefficient = max(f32)}

	center_to_origin := origin - sphere.center

	a := linalg.dot(direction, direction)
	b := 2 * linalg.dot(direction, center_to_origin)
	c := linalg.dot(center_to_origin, center_to_origin) - sphere.radius*sphere.radius

	discriminant := b*b - 4*a*c
	if discriminant < 0 do return intersection
	root_term := math.sqrt(b*b - 4*a*c)

	c1 := (-b - root_term) / (2*a)
	c2 := (-b + root_term) / (2*a)

	if c1 >= minimum_coefficient && c1 < intersection.coefficient {
		intersection.coefficient = c1
		intersection.position = origin + c1*direction
		intersection.normal = linalg.normalize(intersection.position - sphere.center)
		intersection.material = sphere.material
	} else if c2 >= minimum_coefficient && c2 < intersection.coefficient {
		intersection.coefficient = c2
		intersection.position = origin + c2*direction
		intersection.normal = linalg.normalize(intersection.position - sphere.center)
		intersection.material = sphere.material
	}

	return intersection
}

intersect_face :: proc(origin, direction: t.Vector3, minimum_coefficient: f32, a, b, c: t.Vector3, material: scene.Material) -> Intersection {
	EPSILON :: 0.000001

	intersection := Intersection{coefficient = max(f32)}

	ab := b - a
	ac := c - a

	cross_d_ac := linalg.cross(direction, ac)
	d := linalg.dot(ab, cross_d_ac)
	if d < EPSILON do return intersection

	ao := origin - a
	u := linalg.dot(ao, cross_d_ac)
	if u < 0 || u > 1 do return intersection

	cross_ao_ab := linalg.cross(ao, ab)
	v := linalg.dot(direction, cross_ao_ab)
	if v < 0 || u + v > d do return intersection

	t := linalg.dot(ac, cross_ao_ab) / d
	if t < minimum_coefficient do return intersection

	intersection.coefficient = t
	intersection.position = origin + t*direction
	intersection.normal = linalg.normalize(linalg.cross(ab, ac))
	intersection.material = material

	return intersection
}

intersect_instance :: proc(origin, direction: t.Vector3, minimum_coefficient: f32, instance: scene.Instance, cache: []t.Vector3) -> Intersection {
	intersection := Intersection{coefficient = max(f32)}

	for vertex, i in instance.vertecies {
		cache[i] = scene.transform_apply(instance.transform, vertex)
	}

	for face, i in instance.faces {
		intersection = intersect_face(
			origin, direction, minimum_coefficient,
			cache[face.a], cache[face.b], cache[face.c],
			scene.resolve_material(instance.material, i)
		)

		if intersection.coefficient < max(f32) do break
	}

	return intersection
}

intersect_ray :: proc(origin, direction: t.Vector3, minimum_coefficient: f32, objects: []scene.Object, cache: []t.Vector3) -> Intersection {
	intersection := Intersection {
		coefficient = max(f32),
		material = {color = VOID_COLOR}
	}

	for object in objects {
		local_intersection: Intersection

		switch o in object {
		case scene.Sphere:   local_intersection = intersect_sphere(origin, direction, minimum_coefficient, o)
		case scene.Instance: local_intersection = intersect_instance(origin, direction, minimum_coefficient, o, cache)
		}

		if local_intersection.coefficient < intersection.coefficient do intersection = local_intersection
	}

	return intersection
}
