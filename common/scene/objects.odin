package scene

import t "common:types"

TEXTURE_CHANNELS :: 3

@(private="file")
Instance_Material :: union {
	Material,
	[]Material
}

Texture :: struct {
	width, height: int,
	colors: []f32
}
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
	a, at, an: int,
	b, bt, bn: int,
	c, ct, cn: int
}
Model :: struct {
	vertecies: [dynamic]t.Vector3,
	texels: [dynamic]t.Vector2f,
	normals: [dynamic]t.Vector3,
	faces: [dynamic]Face,
	texture: Maybe(Texture)
}
Instance :: struct {
	using transform: Transform,
	using model: Model,
	material: Instance_Material
}

Object :: union {
	Sphere,
	Instance
}

resolve_material :: proc(material: Instance_Material, index: int) -> Material {
	switch m in material {
	case Material:
		return m
	case []Material:
		return m[index]
	case:
		panic("resolve_material: undefined material")
	}
}
