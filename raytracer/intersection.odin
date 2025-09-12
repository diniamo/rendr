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

intersect_sphere :: proc(origin, direction: t.Vector3, sphere: scene.Sphere, minimum_coefficient: f32) -> Intersection {
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

intersect_face :: proc(origin, direction: t.Vector3, using face: scene.Face, minimum_coefficient: f32) -> Intersection {
	intersection := Intersection{coefficient = max(f32)}

	m := matrix[3, 3]f32{
		direction.x, -b.x + a.x, -c.x + a.x,
		direction.y, -b.y + a.y, -c.y + a.y,
		direction.z, -b.z + a.z, -c.z + a.z
	}
	d := linalg.determinant(m)

	m_u := matrix[3, 3]f32{
		direction.x, a.x - origin.x, -c.x + a.x,
		direction.y, a.y - origin.y, -c.y + a.y,
		direction.z, a.z - origin.z, -c.z + a.z
	}
	d_u := linalg.determinant(m_u)
	u := d_u / d
	if u < 0 do return intersection

	m_v := matrix[3, 3]f32{
		direction.x, -b.x + a.x, a.x - origin.x,
		direction.y, -b.y + a.y, a.y - origin.y,
		direction.z, -b.z + a.z, a.z - origin.z
	}
	d_v := linalg.determinant(m_v)
	v := d_v / d
	if v < 0 || u + v > 1 do return intersection

	m_t := matrix[3, 3]f32{
		a.x - origin.x, -b.x + a.x, -c.x + a.x,
		a.y - origin.y, -b.y + a.y, -c.y + a.y,
		a.z - origin.z, -b.z + a.z, -c.z + a.z
	}
	d_t := linalg.determinant(m_t)
	t := d_t / d
	if t < minimum_coefficient do return intersection

	intersection.coefficient = t
	intersection.position = origin + t*direction
	intersection.normal = linalg.normalize(linalg.cross(b - a, c - a))
	intersection.material = face.material

	return intersection
}

intersect_model :: proc(origin, direction: t.Vector3, model: scene.Model, minimum_coefficient: f32) -> Intersection {
	intersection := Intersection{coefficient = max(f32)}

	for face in model.mesh {
		face := face
		face.a = model.position + linalg.quaternion_mul_vector3(model.rotation, face.a)
		face.b = model.position + linalg.quaternion_mul_vector3(model.rotation, face.b)
		face.c = model.position + linalg.quaternion_mul_vector3(model.rotation, face.c)

		intersection = intersect_face(origin, direction, face, minimum_coefficient)
		if intersection.coefficient < max(f32) do break
	}

	return intersection
}

intersect_ray :: proc(origin, direction: t.Vector3, objects: []scene.Object, minimum_coefficient: f32) -> Intersection {
	intersection := Intersection {
		coefficient = max(f32),
		material = {color = VOID_COLOR}
	}

	for object in objects {
		local_intersection: Intersection

		switch o in object {
		case scene.Sphere: local_intersection = intersect_sphere(origin, direction, o, minimum_coefficient)
		case scene.Model:  local_intersection = intersect_model(origin, direction, o, minimum_coefficient)
		}

		if local_intersection.coefficient < intersection.coefficient do intersection = local_intersection
	}

	return intersection
}
