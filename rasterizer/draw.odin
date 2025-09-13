package rasterizer

import "core:math/linalg"
import t "common:types"
import "common:canvas"

draw_line :: proc(target: ^canvas.Canvas, from, to: t.Vector2, color: t.Color) {
	from := from
	to := to

	d := linalg.abs(to - from)
	if d.x > d.y {
		if from.x > to.x do from, to = to, from

		interpolation := interpolate(from.x, to.x, from.y, to.y)
		for x, y in interpolate_next(&interpolation) do canvas.pixel(target, {x, y}, color, .Clamp)
	} else {
		if from.y > to.y do from, to = to, from

		interpolation := interpolate(from.y, to.y, from.x, to.x)
		for y, x in interpolate_next(&interpolation) do canvas.pixel(target, {x, y}, color, .Clamp)
	}
}

draw_wireframe_triangle :: proc(target: ^canvas.Canvas, a, b, c: t.Vector2, color: t.Color) {
	draw_line(target, a, b, color)
	draw_line(target, a, c, color)
	draw_line(target, b, c, color)
}

draw_filled_triangle :: proc(target: ^canvas.Canvas, a, b, c: t.Vector2, color: t.Color) {
	a := linalg.floor(a)
	b := linalg.floor(b)
	c := linalg.floor(c)

	if a.y > b.y do a, b = b, a
	if a.y > c.y do a, c = c, a
	if b.y > c.y do b, c = c, b

	ab := interpolate(a.y, b.y, a.x, b.x)
	ac := interpolate(a.y, c.y, a.x, c.x)
	bc := interpolate(b.y + 1, c.y, b.x, c.x)

	if b.x < c.x {
		for y, x2 in interpolate_next(&ac) {
			_, x1, ok := interpolate_next(&ab)
			if !ok {
				_, x1, ok = interpolate_next(&bc)
				assert(ok)
			}

			for x in x1..=x2 do canvas.pixel(target, {x, y}, color, .Clamp)
		}
	} else {
		for y, x1 in interpolate_next(&ac) {
			_, x2, ok := interpolate_next(&ab)
			if !ok {
				_, x2, ok = interpolate_next(&bc)
				assert(ok)
			}

			for x in x1..=x2 do canvas.pixel(target, {x, y}, color, .Clamp)
		}
	}
}

draw_shaded_triangle :: proc(target: ^canvas.Canvas, a, b, c: t.Vector2, ia, ib, ic: f32, color: t.Color) {
	a := linalg.floor(a)
	b := linalg.floor(b)
	c := linalg.floor(c)

	ia, ib, ic := ia, ib, ic
	if a.y > b.y { a, b = b, a; ia, ib = ib, ia }
	if a.y > c.y { a, c = c, a; ia, ic = ic, ia }
	if b.y > c.y { b, c = c, b; ib, ic = ic, ib }

	by1 := b.y + 1

	ac := interpolate(a.y, c.y, a.x, c.x)
	ab := interpolate(a.y, b.y, a.x, b.x)
	bc := interpolate(by1, c.y, b.x, c.x)

	iac := interpolate(a.y, c.y, ia, ic)
	iab := interpolate(a.y, b.y, ia, ib)
	ibc := interpolate(by1, c.y, ib, ic)

	if b.x < c.x {
		for y, x2 in interpolate_next(&ac) {
			_, h2, _ := interpolate_next(&iac)

			h1: f32 = ---
			_, x1, ok := interpolate_next(&ab)
			if ok {
				_, h1, _ = interpolate_next(&iab)
			} else {
				_, x1, _ = interpolate_next(&bc)
				_, h1, _ = interpolate_next(&ibc)
			}

			i := interpolate(x1, x2, h1, h2)
			for x, i in interpolate_next(&i) do canvas.pixel(target, {x, y}, color * i, .Clamp)
		}
	} else {
		for y, x1 in interpolate_next(&ac) {
			_, i1, _ := interpolate_next(&iac)

			i2: f32 = ---
			_, x2, ok := interpolate_next(&ab)
			if ok {
				_, i2, _ = interpolate_next(&iab)
			} else {
				_, x2, _ = interpolate_next(&bc)
				_, i2, _ = interpolate_next(&ibc)
			}

			i := interpolate(x1, x2, i1, i2)
			for x, i in interpolate_next(&i) do canvas.pixel(target, {x, y}, color * i, .Clamp)
		}
	}
}

draw_gradient_triangle :: proc(target: ^canvas.Canvas, a, b, c: t.Vector2, ca, cb, cc: t.Color) {
	a := linalg.floor(a)
	b := linalg.floor(b)
	c := linalg.floor(c)

	ca, cb, cc := ca, cb, cc
	if a.y > b.y { a, b = b, a; ca, cb = cb, ca }
	if a.y > c.y { a, c = c, a; ca, cc = cc, ca }
	if b.y > c.y { b, c = c, b; cb, cc = cc, cb }

	by1 := b.y + 1

	ac := interpolate(a.y, c.y, a.x, c.x)
	ab := interpolate(a.y, b.y, a.x, b.x)
	bc := interpolate(by1, c.y, b.x, c.x)

	cac := interpolate(a.y, c.y, ca, cc)
	cab := interpolate(a.y, b.y, ca, cb)
	cbc := interpolate(by1, c.y, cb, cc)

	if b.x < c.x {
		for y, x2 in interpolate_next(&ac) {
			_, c2, _ := interpolate_next(&cac)

			c1: t.Color = ---
			_, x1, ok := interpolate_next(&ab)
			if ok {
				_, c1, _ = interpolate_next(&cab)
			} else {
				_, x1, _ = interpolate_next(&bc)
				_, c1, _ = interpolate_next(&cbc)
			}

			c := interpolate(x1, x2, c1, c2)
			for x, c in interpolate_next(&c) do canvas.pixel(target, {x, y}, c, .Clamp)
		}
	} else {
		for y, x1 in interpolate_next(&ac) {
			_, c1, _ := interpolate_next(&cac)

			c2: t.Color = ---
			_, x2, ok := interpolate_next(&ab)
			if ok {
				_, c2, _ = interpolate_next(&cab)
			} else {
				_, x2, _ = interpolate_next(&bc)
				_, c2, _ = interpolate_next(&cbc)
			}

			c := interpolate(x1, x2, c1, c2)
			for x, c in interpolate_next(&c) do canvas.pixel(target, {x, y}, c, .Clamp)
		}
	}
}
