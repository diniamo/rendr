package scene

import t "common:types"

Camera :: struct {
	using position: t.Vector3,
	rotation: quaternion128
}

Scene :: struct {
	camera: Camera,
	objects: []Object,
	lights: []Light
}
