package scene

import os "core:os/os2"
import "core:strings"
import "core:strconv"
import t "common:types"

load_obj :: proc(path: string) -> Model {
	invalid :: #force_inline proc(ok: bool) {
		if !ok do panic("Invalid .obj file")
	}

	index :: proc(index, length: int) -> int {
		if index > 0 {
			return index - 1
		} else {
			return length + index
		}
	}

	data, err := os.read_entire_file(path, context.allocator)
	if err != nil do panic("Failed to read .obj file")
	defer delete(data)

	s := string(data)

	model: Model
	for line in strings.split_lines_iterator(&s) {
		line := line

		type, ok := strings.split_by_byte_iterator(&line, ' '); invalid(ok)
		switch type {
		case "v":
			part_x, part_y, part_z: string = ---, ---, ---
			part_x, ok = strings.split_by_byte_iterator(&line, ' '); invalid(ok)
			part_y, ok = strings.split_by_byte_iterator(&line, ' '); invalid(ok)
			part_z, ok = strings.split_by_byte_iterator(&line, ' '); invalid(ok)
			part_w, has_w := strings.split_by_byte_iterator(&line, ' ')

			x, y, z: f32 = ---, ---, ---
			x, ok = strconv.parse_f32(part_x); invalid(ok)
			y, ok = strconv.parse_f32(part_y); invalid(ok)
			z, ok = strconv.parse_f32(part_z); invalid(ok)

			if has_w {
				w, ok := strconv.parse_f32(part_w); invalid(ok)

				x /= w
				y /= w
				z /= w
			}

			append(&model.vertecies, t.Vector3{x, y, z})
		case "f":
			part_1, part_2, part_3: string = ---, ---, ---
			part_1, ok = strings.split_by_byte_iterator(&line, ' '); invalid(ok)
			part_2, ok = strings.split_by_byte_iterator(&line, ' '); invalid(ok)
			part_3, ok = strings.split_by_byte_iterator(&line, ' '); invalid(ok)

			v1_string, v2_string, v3_string: string = ---, ---, ---
			v1_string, ok = strings.split_by_byte_iterator(&part_1, '/'); invalid(ok)
			v2_string, ok = strings.split_by_byte_iterator(&part_2, '/'); invalid(ok)
			v3_string, ok = strings.split_by_byte_iterator(&part_3, '/'); invalid(ok)

			v1, v2, v3: int
			v1, ok = strconv.parse_int(v1_string, 10); invalid(ok)
			v2, ok = strconv.parse_int(v2_string, 10); invalid(ok)
			v3, ok = strconv.parse_int(v3_string, 10); invalid(ok)

			vc := len(model.vertecies)
			append(&model.faces, Face{
				a = index(v1, vc),
				b = index(v2, vc),
				c = index(v3, vc)
			})
		}
	}

	return model
}

delete_model :: proc(model: Model) {
	delete(model.vertecies)
	delete(model.faces)
}
