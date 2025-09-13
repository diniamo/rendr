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
	a, an: int,
	b, bn: int,
	c, cn: int
}
Model :: struct {
	vertecies: [dynamic]t.Vector3,
	normals: [dynamic]t.Vector3,
	faces: [dynamic]Face
}
Instance :: struct {
	using transform: Transform,
	using model: Model,
	materials: []Material
}

Object :: union {
	Sphere,
	Instance
}
