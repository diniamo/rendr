package rasterizer

import "common:canvas"
import t "common:types"

CANVAS_WIDTH :: 600
CANVAS_HEIGHT :: 600
CANVAS_OUTPUT :: "rasterizer.png"

VIEWPORT_WIDTH :: 1
VIEWPORT_HEIGHT :: 1
VIEWPORT_DISTANCE :: 1

viewport_to_canvas :: proc(p: t.Vector3) -> t.Vector2 {
	return {p.x * CANVAS_WIDTH/VIEWPORT_WIDTH, p.y * CANVAS_HEIGHT/VIEWPORT_HEIGHT}
}

project_point :: proc(p: t.Vector3) -> t.Vector2 {
	return viewport_to_canvas({VIEWPORT_DISTANCE * p.x/p.z, VIEWPORT_DISTANCE * p.y/p.z, VIEWPORT_DISTANCE})
}

main :: proc() {
	target := canvas.create(CANVAS_WIDTH, CANVAS_HEIGHT, CANVAS_OUTPUT)
	defer {
		canvas.flush(&target)
		canvas.destroy(&target)
	}

	canvas.clear(&target, {0.3, 0.3, 0.3})

	// draw_gradient_triangle(&target,
	// 	{20, 250}, {200, 50}, {-200, -250},
	// 	{1, 0, 0}, {0, 1, 0}, {0, 0, 1}
	// )

	// draw_gradient_triangle(&target,
	// 	{0, 250}, {200, -250}, {-200, -250},
	// 	{1, 0, 0}, {0, 1, 0}, {0, 0, 1}
	// )

	vAf := t.Vector3{-2, -0.5, 5}
	vBf := t.Vector3{-2,  0.5, 5}
	vCf := t.Vector3{-1,  0.5, 5}
	vDf := t.Vector3{-1, -0.5, 5}

	vAb := t.Vector3{-2, -0.5, 6}
	vBb := t.Vector3{-2,  0.5, 6}
	vCb := t.Vector3{-1,  0.5, 6}
	vDb := t.Vector3{-1, -0.5, 6}

	RED :: t.Color{1, 0, 0}
	GREEN :: t.Color{0, 1, 0}
	BLUE :: t.Color{0, 0, 1}

	draw_line(&target, project_point(vAf), project_point(vBf), BLUE)
	draw_line(&target, project_point(vBf), project_point(vCf), BLUE)
	draw_line(&target, project_point(vCf), project_point(vDf), BLUE)
	draw_line(&target, project_point(vDf), project_point(vAf), BLUE)

	draw_line(&target, project_point(vAb), project_point(vBb), RED)
	draw_line(&target, project_point(vBb), project_point(vCb), RED)
	draw_line(&target, project_point(vCb), project_point(vDb), RED)
	draw_line(&target, project_point(vDb), project_point(vAb), RED)

	draw_line(&target, project_point(vAf), project_point(vAb), GREEN)
	draw_line(&target, project_point(vBf), project_point(vBb), GREEN)
	draw_line(&target, project_point(vCf), project_point(vCb), GREEN)
	draw_line(&target, project_point(vDf), project_point(vDb), GREEN)
}
