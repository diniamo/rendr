package scene

import t "common:types"

Scene :: struct {
	camera: Camera,
	objects: []Object,
	lights: []Light
}
