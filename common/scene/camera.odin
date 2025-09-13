package scene

import "core:math/linalg"

Camera :: struct {
	transform: Transform,
	inverse: matrix[4, 4]f32,
	inverse_vector: matrix[4, 4]f32
}

camera_update_inverse :: proc(using camera: ^Camera) {
	scale := matrix[4, 4]f32{
		1/transform.scale[0, 0], 0, 0, 0,
		0, 1/transform.scale[1, 1], 0, 0,
		0, 0, 1/transform.scale[2, 2], 0,
		0, 0, 0, 1
	}
	rotation := linalg.transpose(transform.rotation)
	translation := matrix[4, 4]f32{
		1, 0, 0, -transform.position[0, 3],
		0, 1, 0, -transform.position[1, 3],
		0, 0, 1, -transform.position[2, 3],
		0, 0, 0, 1,
	}

	inverse = scale * rotation * translation
	inverse_vector = linalg.transpose(linalg.inverse(inverse))
}
