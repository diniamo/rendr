package canvas

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:strings"
import "vendor:stb/image"
import t "common:types"

CHANNELS :: 3

Canvas :: struct {
	width, height, stride: int,
	data: []u8,
	path: cstring
}

create :: proc(width, height: int, path: string) -> Canvas {
	stride := CHANNELS * width

	return {
		width = width,
		height = height,
		stride = stride,
		data = make([]byte, stride * height),
		path = strings.clone_to_cstring(path)
	}
}

clear :: proc(canvas: ^Canvas, color: t.Color) {
	for y in 0..<canvas.height {
		for x in 0..<canvas.width {
			start := canvas.stride * y + CHANNELS * x

			canvas.data[start] = u8(color[0] * 255)
			canvas.data[start + 1] = u8(color[1] * 255)
			canvas.data[start + 2] = u8(color[2] * 255)
		}
	}
}

position_to_index :: proc(canvas: ^Canvas, point: t.Vector2i) -> int {
	// From a Cartesian coordinate system
	// To a top-left origin with the y axis increasing down
	translated_x := point.x + canvas.width/2
	translated_y := canvas.height/2 - point.y

	when ODIN_DEBUG {
		if translated_x < 0 || translated_x >= canvas.width  do panic(fmt.aprintf("x pixel coordinate out of range: %d -> %d", point.x, translated_x))
		if translated_y < 0 || translated_y >= canvas.height do panic(fmt.aprintf("y pixel coordinate out of range: %d -> %d", point.y, translated_y))
	}

	return canvas.stride * translated_y + CHANNELS * translated_x
}

pixel_index :: proc(canvas: ^Canvas, index: int, color: t.Color) {
	color := 255 * color
	for value, i in color do canvas.data[index + i] = u8(value)
}

pixel :: proc(canvas: ^Canvas, point: t.Vector2i, color: t.Color) {
	pixel_index(canvas, position_to_index(canvas, point), color)
}

row :: proc(canvas: ^Canvas, y: int, color: t.Color) {
	y := canvas.height/2 - y
	for index := y * canvas.stride; index < (y + 1) * canvas.stride; index += CHANNELS {
		pixel_index(canvas, index, color)
	}
}

col :: proc(canvas: ^Canvas, x: int, color: t.Color) {
	x := x + canvas.width/2
	for index := CHANNELS * x; index < canvas.height * canvas.stride; index += canvas.stride {
		pixel_index(canvas, index, color)
	}
}

draw_circle :: proc(target: ^Canvas, center: t.Vector2f, radius: int, color: t.Color) {
	center_round := linalg.array_cast(linalg.round(center), int)

	for x in center_round.x - radius..=center_round.x + radius {
		for y in center_round.y - radius..=center_round.y + radius {
			if linalg.distance(center, t.Vector2f{f32(x), f32(y)}) < f32(radius) {
				pixel(target, {x, y}, color)
			}
		}
	}
}

draw_line :: proc(target: ^Canvas, p0, p1: t.Vector2f, color: t.Color) {
	p0, p1 := p0, p1
	d := p1 - p0

	if math.abs(d.x) > math.abs(d.y) {
		if p0.x > p1.x do p0, p1 = p1, p0

		m := f32(d.y) / f32(d.x)
		y := f32(p0.y)
		for ; p0.x <= p1.x; p0 += {1, m} {
			pixel(target, linalg.array_cast(linalg.round(p0), int), color)
		}
	} else {
		if p0.y > p1.y do p0, p1 = p1, p0

		m := f32(d.x) / f32(d.y)
		for ; p0.y <= p1.y; p0 += {m, 1} {
			pixel(target, linalg.array_cast(linalg.round(p0), int), color)
		}
	}
}

flush :: proc(canvas: ^Canvas) -> bool {
	return image.write_png(
		canvas.path,
		i32(canvas.width), i32(canvas.height),
		CHANNELS, &canvas.data[0], i32(canvas.stride)
	) == 0
}

destroy :: proc(canvas: ^Canvas) {
	delete(canvas.path)
	delete(canvas.data)
}
