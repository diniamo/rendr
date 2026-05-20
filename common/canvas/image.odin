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
	data: []u8
}

create :: proc(width, height: int) -> Canvas {
	stride := CHANNELS * width

	return {
		width = width,
		height = height,
		stride = stride,
		data = make([]byte, stride * height)
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

middle_to_index :: proc(canvas: ^Canvas, point: t.Vector2i) -> int {
	translated_x := point.x + canvas.width/2
	translated_y := canvas.height/2 - point.y
	return canvas.stride * translated_y + CHANNELS * translated_x
}

pixel_index :: proc(canvas: ^Canvas, index: int, color: t.Color) {
	color := 255 * color
	for value, i in color do canvas.data[index + i] = u8(value)
}

pixel_middle :: proc(canvas: ^Canvas, point: t.Vector2i, color: t.Color) {
	pixel_index(canvas, middle_to_index(canvas, point), color)
}

pixel_bottom_left :: proc(canvas: ^Canvas, point: t.Vector2i, color: t.Color) {
	translated_y := canvas.height - point.y - 1
	index := canvas.stride * translated_y + CHANNELS * point.x
	pixel_index(canvas, index, color)
}

flush :: proc(canvas: ^Canvas, path: string) -> bool {
	return image.write_png(
		strings.clone_to_cstring(path, context.temp_allocator),
		i32(canvas.width), i32(canvas.height),
		CHANNELS, &canvas.data[0], i32(canvas.stride)
	) == 0
}

destroy :: proc(canvas: ^Canvas) {
	delete(canvas.data)
}
