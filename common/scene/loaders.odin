package scene

import "core:math/linalg"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:path/filepath"
import "vendor:stb/image"
import t "common:types"

// The maximum number of tokens a line can have
// I haven't actually verified this value, but it works with the files I've tried
@(private="file")
MAX_TOKENS :: 5

@(private="file")
Tokenizer :: struct {
	data: string,
	start: int
}

@(private="file")
tokenizer_next :: proc(tokenizer: ^Tokenizer) -> (tokens: [MAX_TOKENS]string, token_count: int, cond: bool) {
	comment := false
	token_start := -1
	for i := tokenizer.start; i < len(tokenizer.data); i += 1 {
		c := tokenizer.data[i]

		switch {
		case c == '\n':
			if token_start != -1 {
				tokens[token_count] = tokenizer.data[token_start:i]
				token_count += 1
			} else if token_count == 0 {
				comment = false
				continue
			}

			tokenizer.start = i + 1
			cond = true
			return
		case comment:
			continue
		case c == '#':
			comment = true
		case c == ' ':
			if token_start != -1 {
				tokens[token_count] = tokenizer.data[token_start:i]
				token_count += 1
				token_start = -1
			}
		case:
			if token_start == -1 do token_start = i
		}
	}

	return
}

load_obj :: proc(path: string) -> Model {
	fatal :: proc(format: string, args: ..any) {
		fmt.fprintfln(os.stderr, format, ..args)
		os.exit(1)
	}

	float :: proc(s: string, loc := #caller_location) -> f32 {
		n, ok := strconv.parse_f32(s)
		if !ok do fatal("%v failed to parse float: %s", loc, s)
		return n
	}

	index :: proc(s: string, l: int, loc := #caller_location) -> int {
		n, ok := strconv.parse_int(s)
		if !ok do fatal("%v failed to parse index: %s", loc, s)
		n += -1 if l > 0 else l
		return n
	}

	vertex :: proc(s: string, lv, lvt, lvn: int) -> (int, int, int) {
		iv, ivt, ivn := -1, -1, -1

		i := 1
		for ; s[i] != '/'; i += 1 {}
		iv = index(s[:i], lv)

		start := i + 1
		for i = start; s[i] != '/'; i += 1 {}
		if i != start do ivt = index(s[start:i], lvt)
		ivn = index(s[i + 1:], lvn)

		return iv, ivt, ivn
	}

	data, ok := os.read_entire_file(path)
	if !ok do fatal("Failed to read %s", path)
	defer delete(data)

	model: Model

	data_string := string(data)
	tokenizer := Tokenizer{data = data_string}
	for tokens, token_count in tokenizer_next(&tokenizer) {
		switch tokens[0] {
		case "v":
			v := t.Vector3{float(tokens[1]), float(tokens[2]), float(tokens[3])}
			if token_count > 4 do v /= float(tokens[4])
			append(&model.vertecies, v)
		case "vn":
			vn := t.Vector3{float(tokens[1]), float(tokens[2]), float(tokens[3])}
			append(&model.normals, vn)
		case "vt":
			vt := t.Vector2f{float(tokens[1]), 1 - float(tokens[2])}
			append(&model.texels, vt)
		case "f":
			lv, lvt, lvn := len(model.vertecies), len(model.texels), len(model.normals)
			a, at, an := vertex(tokens[1], lv, lvt, lvn)
			b, bt, bn := vertex(tokens[2], lv, lvt, lvn)
			c, ct, cn := vertex(tokens[3], lv, lvt, lvn)

			f := Face{
				a, at, an,
				b, bt, bn,
				c, ct, cn
			}
			append(&model.faces, f)
		case "mtllib":
			directory := filepath.dir(path)
			mtl_path := filepath.join({directory, tokens[1]})
			defer {
				delete(directory)
				delete(mtl_path)
			}

			mtl_data, ok := os.read_entire_file(mtl_path)
			if !ok do fatal("Failed to read %s", mtl_path)
			defer delete(mtl_data)
			mtl_string := string(mtl_data)

			mtl_tokenizer := Tokenizer{data = mtl_string}
			for tokens, token_count in tokenizer_next(&mtl_tokenizer) {
				switch tokens[0] {
				case "map_Kd":
					path := tokens[1]
					path_alloc := false
					if path[0] != '/' {
						directory := filepath.dir(mtl_path)
						defer delete(directory)

						path = filepath.join({directory, path})
						path_alloc = true
					}
					c_path := strings.clone_to_cstring(path)
					defer {
						if path_alloc do delete(path)
						delete(c_path)
					}

					width, height: i32 = ---, ---
					data := image.load(c_path, &width, &height, nil, TEXTURE_CHANNELS)
					defer image.image_free(data)

					texture: Texture
					texture.width = int(width)
					texture.height = int(height)
					texture.colors = make([]f32, width * TEXTURE_CHANNELS * height)
					for i := i32(0); i < width * TEXTURE_CHANNELS * height; i += 1 {
						texture.colors[i] = f32(data[i]) / 255
					}
					model.texture = texture
				}
			}
		}
	}

	return model
}

delete_model :: proc(model: Model) {
	delete(model.vertecies)
	delete(model.texels)
	delete(model.normals)
	delete(model.faces)
	switch &texture in model.texture {
	case Texture: delete(texture.colors)
	}
}
