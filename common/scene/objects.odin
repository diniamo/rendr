package scene

import t "common:types"

Material :: struct {
	color: t.Color,
	// The exponent used for specular reflection
	specularity: f32,
	reflectiveness: f32
}

Sphere :: struct {
	using center: t.Vector3,
	radius: f32,

	using material: Material
}

Face :: struct {
	a: t.Vector3,
	b: t.Vector3,
	c: t.Vector3,

	using material: Material
}
Mesh :: [dynamic]Face
Model :: struct {
	using position: t.Vector3,
	rotation: quaternion128,
	mesh: Mesh
}

Object :: union {
	Sphere,
	Model
}
