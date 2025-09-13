package scene

import "core:math/linalg"

Camera :: struct {
	transform: Transform,
	inverse: matrix[4, 4]f32
}

camera_update_inverse :: proc(using camera: ^Camera) {
	inverse = matrix[4, 4]f32{
		1/transform.scale[0, 0], 0, 0, 0,
		0, 1/transform.scale[1, 1], 0, 0,
		0, 0, 1/transform.scale[2, 2], 0,
		0, 0, 0, 1
	} * linalg.transpose(transform.rotation) * -transform.position
}
