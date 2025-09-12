package canvas

import "core:strings"
import "core:fmt"
import stbi "vendor:stb/image"
import t "common:types"

CHANNELS :: 3

Canvas :: struct {
	width, height, stride: int,
	data: []u8,
	path: cstring
}

create :: proc(width, height: int, path: string) -> Canvas {
	canvas: Canvas

	canvas.width = width
	canvas.height = height
	canvas.stride = CHANNELS * canvas.width
	canvas.data = make([]byte, canvas.stride * canvas.height)
	canvas.path = strings.clone_to_cstring(path)

	return canvas
}

pixel :: proc(canvas: Canvas, x, y: int, color: t.Color) {
	// From a Cartesian coordinate system
	// To a top-left origin with the y axis increasing down
	translated_x := x + canvas.width/2
	translated_y := canvas.height/2 - y

	start := canvas.stride * translated_y + CHANNELS * translated_x

	canvas.data[start] = u8(color[0] * 255)
	canvas.data[start + 1] = u8(color[1] * 255)
	canvas.data[start + 2] = u8(color[2] * 255)
}

flush :: proc(canvas: Canvas) -> bool {
	return stbi.write_png(
		canvas.path,
		i32(canvas.width), i32(canvas.height),
		CHANNELS, &canvas.data[0], i32(canvas.stride)
	) == 0
}

destroy :: proc(canvas: Canvas) {
	delete(canvas.path)
	delete(canvas.data)
}
