package text

import "core:slice"
import "core:log"

Contour :: [][2]f32
Glyph :: struct {
	contours: []Contour,
	min, max: [2]f32
}
Font :: struct {
	glyphs: []Glyph,
	units_per_em: f32,
	offsets: map[rune]int
}

parse_ttf :: proc(data: []byte) -> Font {
	Reader :: struct {
		data: []byte,
		position: int
	}
	read :: proc(reader: ^Reader, $T: typeid) -> T {
		value := slice.to_type(reader.data[reader.position:], T)
		reader.position += size_of(T)
		return value
	}

	check_bit :: proc(value: $T, index: u8) -> bool {
		return (value >> index) & 1 == 1
	}

	font: Font
	reader := Reader{data, 0}

	reader.position += 4 // scalerType
	table_count := int(read(&reader, u16be))
	reader.position += 3 * 2 // rest of the offset subtable

	tables: struct{head, maxp, glyf, loca, cmap: int} = ---
	for _ in 0..<table_count {
		tag := read(&reader, [4]byte)
		reader.position += 4 // checksum

		offset := int(read(&reader, u32be))
		switch tag {
		case "head": tables.head = offset
		case "maxp": tables.maxp = offset
		case "glyf": tables.glyf = offset
		case "loca": tables.loca = offset
		case "cmap": tables.cmap = offset
		}

		reader.position += 4 // length
	}

	// head table
	reader.position = tables.head
	reader.position += 18 // to unitsPerEm
	font.units_per_em = f32(read(&reader, u16be))
	reader.position += 30 // to indexToLocFormat
	index_to_offset_format := int(read(&reader, i16be))

	// maxp table
	reader.position = tables.maxp
	reader.position += 4 // version
	glyph_count := int(read(&reader, u16be))

	// loca table
	reader.position = tables.loca

	glyph_locations := make([]int, glyph_count, context.temp_allocator)
	switch index_to_offset_format {
	case 0: for &location in glyph_locations { location = tables.glyf + 2 * int(read(&reader, u16be)) }
	case 1: for &location in glyph_locations { location = tables.glyf + int(read(&reader, u32be)) }
	}

	font.glyphs = make([]Glyph, glyph_count)
	for i in 0..<glyph_count {
		glyph := &font.glyphs[i]
		reader.position = glyph_locations[i]

		contour_count := int(read(&reader, i16be))
		// TODO: load compound glyphs
		if contour_count <= 0 { continue }
		glyph.contours = make([]Contour, contour_count)

		glyph.min = {f32(read(&reader, i16be)), f32(read(&reader, i16be))}
		glyph.max = {f32(read(&reader, i16be)), f32(read(&reader, i16be))}

		end_indecies := make([]int, contour_count, context.temp_allocator)
		for j in 0..<contour_count { end_indecies[j] = int(read(&reader, u16be)) }

		instruction_length := int(read(&reader, u16be))
		reader.position += instruction_length // instructions

		Point :: struct {
			position: [2]f32,
			flags: u8,
			on_curve: bool
		}
		point_count := int(end_indecies[contour_count - 1] + 1)
		points := make([]Point, point_count, context.temp_allocator)

		for j := 0; j < point_count; {
			flags := read(&reader, u8)

			repeat_count := 1
			if check_bit(flags, 3) { repeat_count += int(read(&reader, u8)) }

			for k in j..<j + repeat_count {
				points[k].flags = flags
				points[k].on_curve = check_bit(flags, 0)
			}
			j += repeat_count
		}

		resolve_points :: proc(reader: ^Reader, points: []Point, field_offset: uintptr, bit_offset: u8) {
			previous: f32 = 0
			for i in 0..<len(points) {
				point := &points[i]

				dx: f32 = 0
				flag_1 := check_bit(point.flags, 1 + bit_offset)
				flag_2 := check_bit(point.flags, 4 + bit_offset)
				if flag_1 {
					dx = f32(read(reader, u8))
					if !flag_2 { dx *= -1 }
				} else {
					if !flag_2 {
						dx = f32(read(reader, i16be))
					}
				}

				current := previous + dx
				(cast(^f32)(uintptr(point) + field_offset))^ = current
				previous = current
			}
		}
		resolve_points(&reader, points, offset_of(Point, position),                0)
		resolve_points(&reader, points, offset_of(Point, position) + size_of(f32), 1)

		a0, a1, a2: ^Point = ---, ---, ---
		// NOTE: used for implied points
		p: Point = ---

		start := 0
		for j in 0..<contour_count {
			start_next := end_indecies[j] + 1
			contour_points := points[start:start_next]
			contour_point_count := start_next - start

			// On-curve points are handled by duplicating the second endpoint
			// TODO: should we really count them?
			// More ideal would be writing as many as we want into a virtual memory-based growing arena
			new_point_count := 0
			p1 := &contour_points[0]
			p2 := &contour_points[1]
			p3 := &contour_points[2]
			dummy := Point{on_curve = true}
			for k := 0; k < contour_point_count; {
				if p2.on_curve {
					k += 1
					p1, p2, p3 = p2, p3, &contour_points[(k + 2) % contour_point_count]
				} else {
					if p3.on_curve {
						k += 2
						p1, p2, p3 = p3, &contour_points[(k + 1) % contour_point_count], &contour_points[(k + 2) % contour_point_count]
					} else {
						k += 1
						p1, p2, p3 = &dummy, p3, &contour_points[(k + 2) % contour_point_count]
					}
				}

				new_point_count += 3
			}
			new_points := make([][2]f32, new_point_count)
			glyph.contours[j] = new_points

			p1 = &contour_points[0]
			p2 = &contour_points[1]
			p3 = &contour_points[2]
			a1, a2, a3: ^Point = ---, ---, ---
			l := 0
			for k := 0; k < contour_point_count; {
				if p2.on_curve {
					a1, a2, a3 = p1, p2, p2

					k += 1
					p1, p2, p3 = p2, p3, &contour_points[(k + 2) % contour_point_count]
				} else {
					if p3.on_curve {
						a1, a2, a3 = p1, p2, p3

						k += 2
						p1, p2, p3 = p3, &contour_points[(k + 1) % contour_point_count], &contour_points[(k + 2) % contour_point_count]
					} else {
						implied := new(Point, context.temp_allocator)
						implied.position = (p2.position + p3.position)/2
						implied.on_curve = true

						a1, a2, a3 = p1, p2, implied

						k += 1
						p1, p2, p3 = implied, p3, &contour_points[(k + 2) % contour_point_count]
					}
				}

				new_points[l]     = a1.position
				new_points[l + 1] = a2.position
				new_points[l + 2] = a3.position
				l += 3
			}
			assert(l == new_point_count)

			start = start_next
		}
	}

	// cmap table
	reader.position = tables.cmap
	reader.position += 2 // version

	selected_id: u16 = 0
	selected_offset: u32be = ---
	ok := false

	subtable_count := u16(read(&reader, u16be))
	for _ in 0..<subtable_count {
		id := u16(read(&reader, u16be))
		if id != 0 {
			reader.position += 2 // platformSpecificID
			reader.position += 4 // offset
			continue
		}

		id = u16(read(&reader, u16be))
		if (id == 0 || id == 1 || id == 3 || id == 4) && (!ok || id > selected_id) {
			selected_id = id
			selected_offset = read(&reader, u32be)
			ok = true
		} else {
			reader.position += 4 // offset
		}
	}

	if !ok { log.fatal("No unicode character map in TTF data") }

	reader.position = tables.cmap + int(selected_offset)

	format := read(&reader, u16be)
	if format != 12 { log.fatal("Unsupported unicode character map format:", format) }

	reader.position += 2 // reserved
	reader.position += 4 // length
	reader.position += 4 // language

	group_count := int(read(&reader, u32be))
	for _ in 0..<group_count {
		chr := u32(read(&reader, u32be))
		end := u32(read(&reader, u32be))
		glyph := int(read(&reader, u32be))

		for chr <= end {
			font.offsets[rune(chr)] = glyph
			chr += 1
			glyph += 1
		}
	}

	return font
}

delete_font :: proc(font: Font) {
	for glyph in font.glyphs {
		for contour in glyph.contours { delete(contour) }
		delete(glyph.contours)
	}
	delete(font.glyphs)
	delete(font.offsets)
}
