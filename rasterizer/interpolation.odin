package rasterizer

Interpolation :: struct($T: typeid) {
	i1, i: f32,
	a, d: T
}

interpolate :: proc(i0, i1: f32, d0, d1: $T) -> Interpolation(T) {
	return {
		i1 = i1,
		a = (d1 - d0) / f32(i1 - i0) if i0 != i1 else 0,
		i = i0,
		d = d0
	}
}

interpolate_next :: proc(using interpolation: ^Interpolation($E)) -> (f32, E, bool) {
	if i > i1 do return 0, 0, false

	defer {
		d += a
		i += 1
	}

	return i, d, true
}
