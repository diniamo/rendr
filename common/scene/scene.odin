package scene

import t "common:types"

Scene :: struct {
	camera: Camera,
	objects: []Object,
	lights: []Light
}

Camera :: struct {
	position: t.Vector3,
	rotation: matrix[3, 3]f32
}
