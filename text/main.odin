package text

import "core:math"
import "core:math/linalg"
import "core:slice"
import "common:canvas"
import "common:logger"

CANVAS_WIDTH :: 600
CANVAS_HEIGHT :: 600

FONT_FILE :: "../assets/InterVariable.ttf"
FONT_SIZE :: 256
FONT_COLOR :: [3]f32{1, 1, 1}
CHARACTER :: '$'
PER_PIXEL :: false

MAGIC_NUMBER :: 0b0010_1110_0111_0100
EPSILON :: 1/1024.0

font_data := #load(FONT_FILE)

matrix3_mul_vector2 :: proc(m: matrix[3, 3]f32, v: [2]f32) -> [2]f32 {
	r := m * [3]f32{v.x, v.y, 1}
	return {r.x, r.y} / r[2]
}

x_t :: proc(x1, x2, x3, t: f32) -> f32 {
	c := 1 - t
	return c*c*x1 + 2*t*c*x2 + t*t*x3
}

per_pixel :: proc(target: ^canvas.Canvas, glyph: Glyph, to_pixels: f32) {
	shoot_ray :: proc(contours: []Contour, transform: matrix[3,3]f32) -> (int, f32) {
		winding: int = 0
		coverage: f32 = 0

		for contour in contours {
			for i := 0; i < len(contour) - 2; i += 3 {
				p1 := matrix3_mul_vector2(transform, contour[i])
				p2 := matrix3_mul_vector2(transform, contour[i + 1])
				p3 := matrix3_mul_vector2(transform, contour[i + 2])

				amount: uint = (p1.y > 0 ? 0b10 : 0) | (p2.y > 0 ? 0b100 : 0) | (p3.y > 0 ? 0b1000 : 0)
				result := MAGIC_NUMBER >> amount
				if (result & 0b11) == 0 { continue }

				a := p1.y - 2*p2.y + p3.y
				b := p1.y - p2.y
				c := p1.y
				t1, t2: f32 = ---, ---
				if abs(a) < EPSILON {
					t1 = c/(2*b)
					t2 = t1
				} else {
					sqrt_term := math.sqrt(max(0, b*b - a*c))
					t1 = (b - sqrt_term) / a
					t2 = (b + sqrt_term) / a
				}

				x1 := x_t(p1.x, p2.x, p3.x, t1)
				x2 := x_t(p1.x, p2.x, p3.x, t2)
				if (result & 0b1)  != 0 && x1 >= 0 { winding += 1; coverage += math.saturate(x1 + 0.5) }
				if (result & 0b10) != 0 && x2 >= 0 { winding -= 1; coverage -= math.saturate(x2 + 0.5) }
			}
		}

		return winding, coverage
	}

	sample :: proc(contours: []Contour, position: [2]f32, to_pixels: f32) -> f32 {
		transform := matrix[3, 3]f32{
			to_pixels, 0, -position.x,
			0, to_pixels, -position.y,
			0, 0, 1
		}

		w_right, c_right := shoot_ray(contours, transform)
		if w_right == 0 { return 0 }

		_, c_up := shoot_ray(contours, {
			0, 1, 0,
			-1, 0, 0,
			0, 0, 1
		} * transform)

		_, c_left := shoot_ray(contours, {
			-1, 0, 0,
			0, -1, 0,
			0, 0, 1
		} * transform)

		_, c_down := shoot_ray(contours, {
			0, -1, 0,
			1, 0, 0,
			0, 0, 1
		} * transform)

		return math.saturate((c_right + c_up + c_left + c_down) / 4)
	}

	SAMPLES_PER_SIDE :: 4
	SAMPLE_STEP :: 1.0/SAMPLES_PER_SIDE
	SAMPLE_COUNT :: SAMPLES_PER_SIDE * SAMPLES_PER_SIDE

	min_floor := linalg.floor(to_pixels * glyph.min)
	max_ceil := linalg.ceil(to_pixels * glyph.max)
	for y in min_floor.y..<max_ceil.y {
		pixel := [2]f32{min_floor.x, y}
		for ; pixel.x < max_ceil.x; pixel.x += 1 {
			running_sum: f32 = 0

			top_left_sample := pixel - 0.5 + SAMPLE_STEP/2
			running_sample := top_left_sample
			for _ in 0..<SAMPLES_PER_SIDE {
				for _ in 0..<SAMPLES_PER_SIDE {
					running_sum += sample(glyph.contours, running_sample, to_pixels)
					running_sample.x += SAMPLE_STEP
				}

				running_sample = {top_left_sample.x, running_sample.y + SAMPLE_STEP}
			}

			intensity := running_sum / SAMPLE_COUNT
			canvas.pixel(target, linalg.array_cast(pixel, int), intensity * FONT_COLOR)
		}
	}
}

scanline :: proc(target: ^canvas.Canvas, glyph: Glyph, to_pixels: f32) {
	Intersection :: struct {
		x: f32,
		winding: int
	}

	shoot_ray :: proc(contours: []Contour, transform: matrix[3,3]f32) -> (intersections: [dynamic; 64]Intersection) {
		windings: u32

		for contour in contours {
			for i := 0; i < len(contour) - 2; i += 3 {
				p1 := matrix3_mul_vector2(transform, contour[i])
				p2 := matrix3_mul_vector2(transform, contour[i + 1])
				p3 := matrix3_mul_vector2(transform, contour[i + 2])

				amount: uint = (p1.y > 0 ? 0b10 : 0) | (p2.y > 0 ? 0b100 : 0) | (p3.y > 0 ? 0b1000 : 0)
				result := MAGIC_NUMBER >> amount
				if (result & 0b11) == 0 { continue }

				a := p1.y - 2*p2.y + p3.y
				b := p1.y - p2.y
				c := p1.y
				t1, t2: f32 = ---, ---
				if abs(a) < EPSILON {
					t1 = c/(2*b)
					t2 = t1
				} else {
					sqrt_term := math.sqrt(max(0, b*b - a*c))
					t1 = (b - sqrt_term) / a
					t2 = (b + sqrt_term) / a
				}

				x1 := x_t(p1.x, p2.x, p3.x, t1)
				x2 := x_t(p1.x, p2.x, p3.x, t2)
				if (result & 0b1)  != 0 && x1 >= 0 { append(&intersections, Intersection{x1, 1}) }
				if (result & 0b10) != 0 && x2 >= 0 { append(&intersections, Intersection{x2, -1}) }
			}
		}

		return
	}

	sample :: proc(contours: []Contour, y: f32, to_pixels: f32, intensities: []f32) {
		transform := matrix[3, 3]f32{
			to_pixels, 0, 0,
			0, to_pixels, -y,
			0, 0, 1
		}
		intersections := shoot_ray(contours, transform)
		slice.sort_by_key(intersections[:], proc(i: Intersection) -> f32 { return i.x })

		running_winding := 0
		for i := 0; i < len(intersections); {
			i1 := intersections[i]
			i2: Intersection = ---

			running_winding += i1.winding
			for running_winding != 0 {
				i += 1
				i2 = intersections[i]
				running_winding += i2.winding
			}
			i += 1

			x1i := int(i1.x)
			x2i := int(i2.x)
			_, f1 := math.modf(i1.x)
			_, f2 := math.modf(i2.x)

			if f1 > 0.5 {
				x1i += 1
				intensities[x1i] += 1.5 - f1
			} else {
				intensities[x1i] += 0.5 - f1
			}
			for x in x1i+1..<x2i { intensities[x] += 1 }
			if f2 > 0.5 {
				intensities[x2i] += 1
				intensities[x2i + 1] += f2 - 0.5
			} else {
				intensities[x2i] += f2 + 0.5
			}
		}
	}

	SAMPLE_COUNT :: 5
	SAMPLE_STEP :: 1.0/(SAMPLE_COUNT + 1)

	bottom_left := linalg.array_cast(to_pixels * glyph.min, int)
	top_right := linalg.array_cast(to_pixels * glyph.max, int)
	intensities := make([]f32, top_right.x + 1, context.temp_allocator)
	for y in bottom_left.y..=top_right.y {
		sy := f32(y) - 0.5
		for _ in 0..<SAMPLE_COUNT {
			sy += SAMPLE_STEP
			sample(glyph.contours, sy, to_pixels, intensities)
		}

		for x in bottom_left.x..=top_right.x {
			intensity := intensities[x]
			if intensity > 0 {
				canvas.pixel(target, {x, y}, intensity/SAMPLE_COUNT * FONT_COLOR)
			}
		}

		slice.zero(intensities)
	}
}

main :: proc() {
	context.logger = logger.get()

	target := canvas.create(CANVAS_WIDTH, CANVAS_HEIGHT, "text.png")
	defer canvas.flush(&target)

	font := parse_ttf(font_data)
	to_pixels := FONT_SIZE / f32(font.units_per_em)
	glyph := font.glyphs[font.offsets[CHARACTER]]

	when PER_PIXEL {
		per_pixel(&target, glyph, to_pixels)
	} else {
		scanline(&target, glyph, to_pixels)
	}

	when ODIN_DEBUG {
		canvas.row(&target, 0, {1, 0, 1})
		canvas.col(&target, 0, {1, 0, 1})
	}
}
