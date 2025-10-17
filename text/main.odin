package text

import "core:slice"
import "core:math"
import "core:math/linalg"
import t "common:types"
import "common:canvas"

CANVAS_WIDTH :: 600
CANVAS_HEIGHT :: 600

FONT_FILE :: "assets/InterVariable.ttf"
FONT_SIZE :: 256
FONT_COLOR :: t.Color{1, 1, 1}

LETTER :: 'a'

intersect_line :: proc(p0, p1: t.Vector2f, y: f32) -> (f32, bool) {
	// This avoids double intersections too, since in that case,
	// one line will have its minimum and the other its maximum
	// at the intersection point, so only 1 will pass the check.
	if y <= min(p0.y, p1.y) || y > max(p0.y, p1.y) do return 0, false

	d := p1 - p0

	// This would mean that if y == p0.y == p1.y, then there would be
	// infinite intersections, which doesn't make sense with this algorithm.
	if d.y == 0 do return 0, false

	x := p0.x + (y - p0.y)*(d.x/d.y)
	return x, true
}

// This function is not strictly correct becuase of floating-point imprecision
intersect_bezier :: proc(p0, p1, p2: t.Vector2f, y: f32) -> (x: [2]f32, count: int) {
	a := p0 - 2*p1 + p2
	b := 2 * (p1 - p0)
	cy := p0.y - y

	if a.y == 0 {
		t := -cy / b.y
		if t >= 0 && t < 1 {
			x[0] = t*b.x + p0.x
			count = 1
		}
	} else {
		determinant := b.y*b.y - 4*a.y*cy
		switch {
		case determinant == 0:
			t := -b.y / (2*a.y)
			if t >= 0 && t < 1 {
				x[0] = t*t*a.x + t*b.x + p0.x
				count = 1
			}
		case determinant > 0:
			sqrt_term := math.sqrt(determinant)

			a2 := 2 * a.y
			t1 :=  (sqrt_term - b.y) / a2
			t2 := -(sqrt_term + b.y) / a2

			if t1 >= 0 && t1 < 1 {
				x[0] = t1*t1*a.x + t1*b.x + p0.x
				count = 1
			}
			if t2 >= 0 && t2 < 1 {
				x[count] = t2*t2*a.x + t2*b.x + p0.x
				count += 1
			}
		}
	}

	return
}

index_wrapped :: proc(slice: []$T, index: int) -> T {
	return slice[index < len(slice) ? index : index - len(slice)]
}

main :: proc() {
	target := canvas.create(CANVAS_WIDTH, CANVAS_HEIGHT, "text.png")
	defer canvas.flush(&target)

	font := load_ttf(FONT_FILE)

	scale := FONT_SIZE / f32(font.units_per_em)
	for &glyph in font.glyphs {
		for &point in glyph.points {
			point.position *= scale
		}

		glyph.min *= scale
		glyph.max *= scale
	}

	glyph := &font.glyphs[font.character_map[LETTER]]

	for y in int(glyph.min.y)..=int(glyph.max.y) {
		intersections: [32]f32 = ---
		intersection_count := 0

		start := 0
		for end in glyph.end_indecies {
			next_start := end + 1
			points := glyph.points[start:next_start]
			last := end - start
			start = next_start

			i := 0
			p0 := points[0]
			p1 := points[1]
			p2 := points[2]
			for {
				if p1.on_curve {
					x, ok := intersect_line(p0.position, p1.position, f32(y))
					if ok {
						intersections[intersection_count] = x
						intersection_count += 1
					}

					i += 1
					if i > last do break

					p0 = p1
					p1 = p2
					p2 = index_wrapped(points, i + 2)
 				} else {
					p0p := p0.position
					p1p := p1.position
					p2p: t.Vector2f = ---
					if p2.on_curve {
						p2p = p2.position

						i += 2
						if i <= last {
							p0 = p2
							p1 = index_wrapped(points, i + 1)
							p2 = index_wrapped(points, i + 2)
						}
					} else {
						p2p = (p1.position + p2.position) / 2

						i += 1
						if i <= last {
							p0 = {p2p, true, f32(i) + 0.5}
							p1 = p2
							p2 = index_wrapped(points, i + 2)
						}
					}

					x, c := intersect_bezier(p0p, p1p, p2p, f32(y))
					switch c {
					case 1:
						intersections[intersection_count] = x[0]
						intersection_count += 1
					case 2:
						intersections[intersection_count] = x[0]
						intersections[intersection_count] = x[1]
						intersection_count += 2
					}

					if i > last do break
				}
			}
		}

		slice.sort(intersections[:intersection_count])

		for i := 1; i < intersection_count; i += 2 {
			x0 := intersections[i - 1]
			x0i := int(x0)

			x1 := intersections[i]
			x1i := int(x1)

			_, f0 := math.modf(x0)
			_, f1 := math.modf(x1)

			// This is a naive attempt at anti-aliasing
			// Doesn't look good for beziers that extend more horizontally than vertically
			canvas.pixel(&target, {x0i, y}, (1 - f0) * FONT_COLOR)
			canvas.pixel(&target, {x1i, y}, f1 * FONT_COLOR)

			for x in x0i + 1..=x1i - 1 {
				canvas.pixel(&target, {x, y}, FONT_COLOR)
			}
		}
	}
}
