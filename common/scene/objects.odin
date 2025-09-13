package scene

import t "common:types"

Material :: struct {
	color: t.Color,
	// The exponent used for specular reflection
	specularity: f32,
	reflectiveness: f32
}

Sphere :: struct {
	using material: Material,

	center: t.Vector3,
	radius: f32
}

Face :: struct {
	using material: Material,

	a: int,
	b: int,
	c: int
}
Model :: struct {
	vertecies: [dynamic]t.Vector3,
	faces: [dynamic]Face
}
Instance :: struct {
	using transform: Transform,
	using model: Model
}

Object :: union {
	Sphere,
	Instance
}
