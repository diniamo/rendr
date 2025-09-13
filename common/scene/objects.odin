package scene

import t "common:types"

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

Face :: struct {
	a: int,
	b: int,
	c: int,

	using material: Material
}
Model :: struct {
	vertecies: [dynamic]t.Vector3,
	faces: [dynamic]Face
}
Instance :: struct {
	using model: Model,
	using transform: Transform
}

Object :: union {
	Sphere,
	Instance
}
