package text

import "core:slice"
import "core:fmt"
import "core:os"
import t "common:types"

Point :: struct {
	position: t.Vector2f,
	on_curve: bool,
	index: f32
}
Glyph :: struct {
	points: []Point,
	end_indecies: []int,
	min, max: t.Vector2f
}
Font :: struct {
	glyphs: []Glyph,
	units_per_em: int,
	character_map: map[rune]int
}

load_ttf :: proc(path: string) -> Font {
	fatal :: proc(format: string, args: ..any) {
		fmt.fprintfln(os.stderr, format, ..args)
		os.exit(1)
	}

	Reader :: struct {
		data: []byte,
		position: u32be
	}
	read :: proc(reader: ^Reader, $T: typeid) -> T {
		value := slice.to_type(reader.data[reader.position:], T)
		reader.position += size_of(T)
		return value
	}
	read_bytes :: proc(reader: ^Reader, $N: u32be) -> [N]byte {
		bytes: [N]byte = ---
		for i in 0..<N do bytes[i] = reader.data[reader.position + i]
		reader.position += N
		return bytes
	}

	check_bit :: proc(value: $T, index: u8) -> bool {
		return (value >> index) & 1 == 1
	}

	data, ok := os.read_entire_file(path)
	if !ok do fatal("Failed to read %s", path)
	defer delete(data)

	font: Font
	reader := Reader{data, 0}

	reader.position += 4 // scalerType
	num_tables := read(&reader, u16be)
	reader.position += 3 * 2 // Rest of the offset subtable

	tables: map[[4]byte]u32be
	for _ in 0..<num_tables {
		tag := read_bytes(&reader, 4)
		reader.position += 4 // checksum
		tables[tag] = read(&reader, u32be)
		reader.position += 4 // length
	}

	reader.position = tables["head"]
	reader.position += 18 // To unitsPerEm
	font.units_per_em = int(read(&reader, u16be))
	reader.position += 30 // To indexToLocFormat
	index_to_offset_format := read(&reader, i16be)

	reader.position = tables["maxp"]
	reader.position += 4 // version
	num_glyphs := read(&reader, u16be)

	glyph_table_offset := tables["glyf"]
	glyph_locations := make([]u32be, num_glyphs)
	defer delete(glyph_locations)

	reader.position = tables["loca"]
	for i in 0..<num_glyphs {
		offset: u32be = ---
		switch index_to_offset_format {
		case 0: offset = 2 * u32be(read(&reader, u16be))
		case 1: offset = read(&reader, u32be)
		}

		glyph_locations[i] = glyph_table_offset + offset
	}

	font.glyphs = make([]Glyph, num_glyphs)
	for i in 0..<num_glyphs {
		reader.position = glyph_locations[i]
		glyph := &font.glyphs[i]

		num_contours := read(&reader, i16be)
		// TODO: load compound glyphs
		// (=0 is a simple glyph, but we don't need to do anything in that case)
		if num_contours <= 0 do continue

		glyph.min = {f32(read(&reader, i16be)), f32(read(&reader, i16be))}
		glyph.max = {f32(read(&reader, i16be)), f32(read(&reader, i16be))}

		glyph.end_indecies = make([]int, num_contours)
		for j in 0..<num_contours do glyph.end_indecies[j] = int(read(&reader, u16be))

		instruction_length := read(&reader, u16be)
		reader.position += u32be(instruction_length) * 1 // instructions

		num_points := glyph.end_indecies[num_contours - 1] + 1
		glyph.points = make([]Point, num_points)

		point_flags: [512]u8 = ---
		point_flag_count := 0

		for j := 0; j < num_points; {
			flags := read(&reader, u8)

			repeat_count := 1
			if check_bit(flags, 3) do repeat_count += int(read(&reader, u8))

			for k in j..<j + repeat_count {
				point_flags[point_flag_count] = flags
				point_flag_count += 1

				glyph.points[k].on_curve = check_bit(flags, 0)
			}
			glyph.points[j].index = f32(j)
			j += repeat_count
		}

		previous: f32 = 0
		for j in 0..<num_points {
			flags := point_flags[j]
			point := &glyph.points[j]

			point.position.x = previous
			if check_bit(flags, 1) {
				dx := f32(read(&reader, u8))
				if check_bit(flags, 4) do point.position.x += dx
				else                   do point.position.x -= dx
				previous = point.position.x
			} else {
				if !check_bit(flags, 4) {
					dx := f32(read(&reader, i16be))
					point.position.x += dx
					previous = point.position.x
				}
			}
		}
		previous = 0
		for j in 0..<num_points {
			flags := point_flags[j]
			point := &glyph.points[j]

			point.position.y = previous
			if check_bit(flags, 2) {
				dy := f32(read(&reader, u8))
				if check_bit(flags, 5) do point.position.y += dy
				else                   do point.position.y -= dy
				previous = point.position.y
			} else {
				if !check_bit(flags, 5) {
					dy := f32(read(&reader, i16be))
					point.position.y += dy
					previous = point.position.y
				}
			}
		}
	}

	cmap_offset := tables["cmap"]
	reader.position = cmap_offset
	reader.position += 2 // version

	selected_id: u16be = 0
	selected_offset: u32be = ---
	ok = false

	num_subtables := read(&reader, u16be)
	for _ in 0..<num_subtables {
		id := read(&reader, u16be)
		if id != 0 {
			reader.position += 2 // platformSpecificID
			reader.position += 4 // offset
			continue
		}

		id = read(&reader, u16be)
		if (id == 0 || id == 1 || id == 3 || id == 4) && (!ok || id > selected_id) {
			selected_id = id
			selected_offset = read(&reader, u32be)
			ok = true
		} else {
			reader.position += 4 // offset
		}
	}

	if !ok do fatal("No unicode character map in %s", path)

	reader.position = cmap_offset + selected_offset

	format := read(&reader, u16be)
	if format != 12 do fatal("Unsupported unicode character map format: %d", format)

	reader.position += 2 // reserved
	reader.position += 4 // length
	reader.position += 4 // language

	num_groups := read(&reader, u32be)
	for _ in 0..<num_groups {
		chr := read(&reader, u32be)
		end := read(&reader, u32be)
		glyph := int(read(&reader, u32be))

		for chr <= end {
			font.character_map[rune(chr)] = glyph
			chr += 1
			glyph += 1
		}
	}

	return font
}

delete_font :: proc(font: Font) {
	delete(font.glyphs)
	delete(font.character_map)
}
