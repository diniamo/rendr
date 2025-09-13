package scene

import "core:math/linalg"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"
import t "common:types"

load_obj :: proc(path: string) -> Model {
	fatal :: proc(format: string, args: ..any) {
		fmt.fprintfln(os.stderr, format, ..args)
		os.exit(1)
	}

	float :: proc(s: string, loc := #caller_location) -> f32 {
		n, ok := strconv.parse_f32(s)
		if !ok do fatal("%v: failed to parse float: %s", loc, s)
		return n
	}

	index :: proc(s: string, l: int, loc := #caller_location) -> int {
		n, ok := strconv.parse_int(s)
		if !ok do fatal("%v: failed to parse index: %s", loc, s)
		n += -1 if l > 0 else l
		return n
	}

	vertex :: proc(s: string, lv, lvn: int, loc := #caller_location) -> (int, int) {
		iv, ivn := -1, -1

		start: int = ---
		for c, i in s {
			if c == '/' {
				iv = index(s[:i], lv)
				start = i + 1
				break
			}
		}

		for {
			if s[start] == '/' {
				start += 1
				break
			}

			start += 1
		}
		ivn = index(s[start:], lvn)

		return iv, ivn
	}

	data, ok := os.read_entire_file(path)
	if !ok do fatal("Failed to read %s", path)
	defer delete(data)
	s := string(data)

	model: Model

	// The maximum number of tokens a line can have
	// I haven't actually verified this value, but it works with the files I've tried
	MAX_TOKENS :: 5

	comment := false
	token_start := -1
	token_count := 0
	tokens: [MAX_TOKENS]string
	for c, i in s {
		switch {
		case c == '\n':
			if token_start != -1 {
				tokens[token_count] = s[token_start:i]
				token_count += 1
			} else if token_count == 0 {
				comment = false
				continue
			}

			switch tokens[0] {
			case "v":
				v := t.Vector3{float(tokens[1]), float(tokens[2]), float(tokens[3])}
				if token_count > 4 do v /= float(tokens[4])
				append(&model.vertecies, v)
			case "vn":
				vn := t.Vector3{float(tokens[1]), float(tokens[2]), float(tokens[3])}
				append(&model.normals, vn)
			case "f":
				lv, lvn := len(model.vertecies), len(model.normals)
				a, an := vertex(tokens[1], lv, lvn)
				b, bn := vertex(tokens[2], lv, lvn)
				c, cn := vertex(tokens[3], lv, lvn)

				f := Face{
					a, an,
					b, bn,
					c, cn
				}
				append(&model.faces, f)
			}

			comment = false
			token_start = -1
			token_count = 0
		case comment:
			continue
		case c == '#':
			comment = true
		case c == ' ':
			if token_start != -1 {
				tokens[token_count] = s[token_start:i]
				token_count += 1
				token_start = -1
			}
		case:
			if token_start == -1 {
				token_start = i
			}
		}
	}

	return model
}

delete_model :: proc(model: Model) {
	delete(model.vertecies)
	delete(model.faces)
}
