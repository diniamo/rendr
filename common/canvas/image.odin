package canvas

import "core:fmt"
import "core:math"
import "core:strings"
import stbi "vendor:stb/image"
import t "common:types"

CHANNELS :: 3

Bounds_Check_Mode :: enum {
	None,
	Clamp,
	Assert
}

Canvas :: struct {
	wi, hi: int,
	stride: int,
	wf, hf: f32,
	data: []u8,
	path: cstring
}

create :: proc(width, height: int, path: string) -> Canvas {
	stride := CHANNELS * width

	return {
		wi = width,
		hi = height,
		stride = stride,
		wf = f32(width),
		hf = f32(height),
		data = make([]byte, stride * height),
		path = strings.clone_to_cstring(path)
	}
}

clear :: proc(canvas: ^Canvas, color: t.Color) {
	for y in 0..<canvas.hi {
		for x in 0..<canvas.wi {
			start := canvas.stride * y + CHANNELS * x

			canvas.data[start] = u8(color[0] * 255)
			canvas.data[start + 1] = u8(color[1] * 255)
			canvas.data[start + 2] = u8(color[2] * 255)
		}
	}
}

pixel :: proc(canvas: ^Canvas, position: t.Vector2, color: t.Color, $bounds_check_mode: Bounds_Check_Mode) {
	// From a Cartesian coordinate system
	// To a top-left origin with the y axis increasing down
	translated_x := int(position.x + canvas.wf/2)
	translated_y := int(canvas.hf/2 - position.y)

	when bounds_check_mode == .Assert {
		if translated_x < 0 || translated_x >= canvas.wi do panic(fmt.aprintf("x pixel coordinate out of range: %f -> %d", position.x, translated_x))
		if translated_y < 0 || translated_y >= canvas.hi do panic(fmt.aprintf("y pixel coordinate out of range: %f -> %d", position.y, translated_y))
	} else when bounds_check_mode == .Clamp {
		translated_x = math.clamp(translated_x, 0, canvas.wi - 1)
		translated_y = math.clamp(translated_y, 0, canvas.hi - 1)
	}

	start := canvas.stride * translated_y + CHANNELS * translated_x

	canvas.data[start] = u8(color[0] * 255)
	canvas.data[start + 1] = u8(color[1] * 255)
	canvas.data[start + 2] = u8(color[2] * 255)
}

flush :: proc(canvas: ^Canvas) -> bool {
	return stbi.write_png(
		canvas.path,
		i32(canvas.wi), i32(canvas.hi),
		CHANNELS, &canvas.data[0], i32(canvas.stride)
	) == 0
}

destroy :: proc(canvas: ^Canvas) {
	delete(canvas.path)
	delete(canvas.data)
}
