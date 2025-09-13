package scene

import "core:math/linalg"
import t "common:types"

Transform :: struct {
	position: matrix[4, 4]f32,
	rotation: matrix[4, 4]f32,
	scale: matrix[4, 4]f32,

	combined: matrix[4, 4]f32,
	combined_vector: matrix[4, 4]f32
}

matrix_apply :: proc(m: matrix[4, 4]f32, v: t.Vector3) -> t.Vector3 {
	h := m * t.Vector4{v.x, v.y, v.z, 1}
	return {h.x, h.y, h.z} / h.w
}

transform_update :: proc(using transform: ^Transform) {
	combined = position * rotation * scale
	combined_vector = linalg.transpose(linalg.inverse(combined))
}

transform_apply :: proc(transform: Transform, point: t.Vector3) -> t.Vector3 {
	return matrix_apply(transform.combined, point)
}

transform_apply_vector :: proc(transform: Transform, vector: t.Vector3) -> t.Vector3 {
	return matrix_apply(transform.combined_vector, vector)
}

transform_get_position :: proc(transform: Transform) -> t.Vector3 {
	return swizzle(transform.position[3], 0, 1, 2)
}
