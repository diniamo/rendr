package scene

import "core:math/linalg"
import t "common:types"

Transform :: struct {
	position: t.Vector3,
	rotation: matrix[3, 3]f32,
	scale: f32
}

transform :: proc(point: t.Vector3, transform: Transform) -> t.Vector3 {
	scaled := point * transform.scale
	rotated := linalg.mul(transform.rotation, scaled)
	translated := rotated + transform.position

	return translated
}
