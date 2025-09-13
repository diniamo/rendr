package scene

import "core:math"
import "core:math/rand"
import "core:math/linalg"
import t "common:types"

MAX_OBJECTS :: 5
MAX_LIGHTS :: 3

Scene :: struct {
	camera: Camera,
	objects: [MAX_OBJECTS]Object,
	lights: [MAX_LIGHTS]Light,
}

crate :: proc() -> Scene {
	crate_model := load_obj("assets/crate/crate.obj")

	return {
		camera = {
			transform = {
				position = linalg.matrix4_translate(t.Vector3{0, 0, 0}),
				rotation = linalg.matrix4_rotate(0, t.Vector3{0, 1, 0}),
				scale = linalg.identity(matrix[4, 4]f32)
			}
		},

		objects = {
			0 = Instance{
				transform = {
					position = linalg.matrix4_translate(t.Vector3{0, -1, 2}),
					rotation = linalg.matrix4_rotate(math.PI / 6, t.Vector3{0, 1, 0}),
					scale = linalg.matrix4_scale(f32(0.25))
				},
				model = crate_model,
				material = Material{}
			},
			1 = Instance{
				transform = {
					position = linalg.matrix4_translate(t.Vector3{-1, 0.25, 3}),
					rotation = linalg.matrix4_rotate(-math.PI / 6, t.Vector3{0, 1, 0}),
					scale = linalg.matrix4_scale(f32(0.25))
				},
				model = crate_model,
				material = Material{}
			},
			2 = Instance{
				transform = {
					position = linalg.matrix4_translate(t.Vector3{1, 0.25, 3}),
					rotation = linalg.matrix4_rotate(math.PI / 4, t.Vector3{0, 1, 0}),
					scale = linalg.matrix4_scale(f32(0.25))
				},
				model = crate_model,
				material = Material{}
			},
		},

		lights = {
			0 = Ambient_Light{0.2},
			1 = Point_Light{0.8, {0, 0, 0}}
		}
	}
}

cube :: proc() -> Scene {
	cube_model := load_obj("assets/cube.obj")
	cube_materials := make([]Material, len(cube_model.faces))
	cube_materials[0] = {1, 0, 0} // red
	cube_materials[1] = {0, 1, 0} // green
	cube_materials[2] = {0, 0, 1} // blue
	cube_materials[3] = {1, 1, 0} // yellow
	cube_materials[4] = {0, 1, 1} // cyan
	cube_materials[5] = {1, 0, 1} // magenta
	cube_materials[6] = {1, 0.65, 0} // orange
	cube_materials[7] = {0.502, 0, 0.502} // purple
	cube_materials[8] = {0.2, 0.81, 0.2} // lime
	cube_materials[9] = {0, 0.51, 0.51} // teal
	cube_materials[10] = {0.981, 0.502, 0.45} // salmon
	cube_materials[11] = {0.44, 0.502, 0.565} // slate gray

	return {
		camera = {
			transform = {
				position = linalg.matrix4_translate(t.Vector3{0, 0, 0}),
				rotation = linalg.matrix4_rotate(0, t.Vector3{0, 1, 0}),
				scale = linalg.identity(matrix[4, 4]f32)
			}
		},

		objects = {
			0 = Instance {
				transform = {
					position = linalg.matrix4_translate(t.Vector3{-0.5, -0.5, 2}),
					rotation = linalg.matrix4_rotate(math.PI, t.Vector3{0, 1, 0}),
					scale = linalg.matrix4_scale(f32(1))
				},
				model = cube_model,
				material = cube_materials
			},
			1 = Sphere{{{1, 1, 0}, 1000, 0.5}, {0, -5001, 0}, 5000}
		},

		lights = {
			0 = Ambient_Light{0.2},
			1 = Point_Light{0.8, {1, 0, 2}}
		}
	}
}

example :: proc() -> Scene {
	monkey_model := load_obj("assets/monkey.obj")
	monkey_materials := make([]Material, len(monkey_model.faces))
	for &material in monkey_materials do material.color = {rand.float32(), rand.float32(), rand.float32()}

	return {
		camera = {
			transform = {
				position = linalg.matrix4_translate(t.Vector3{2.5, 0, 1.5}),
				rotation = linalg.matrix4_rotate(-math.PI / 4, t.Vector3{0, 1, 0}),
				scale = linalg.identity(matrix[4, 4]f32)
			}
		},

		objects = {
			0 = Sphere{{{1, 0, 0}, 500, 0.2},  {0, -1, 3},    1},
			1 = Sphere{{{0, 0, 1}, 500, 0.3},  {2, 0, 4},     1},
			2 = Sphere{{{0, 1, 0}, 10, 0.4},   {-2, 0, 4},    1},
			3 = Sphere{{{1, 1, 0}, 1000, 0.5}, {0, -5001, 0}, 5000},
			4 = Instance{
				model = monkey_model,
				transform = {
					position = linalg.matrix4_translate(t.Vector3{0, 0.5, 4}),
					rotation = linalg.matrix4_rotate(math.PI, t.Vector3{0, 1, 0}),
					scale = linalg.matrix4_scale(f32(1))
				},
				material = monkey_materials
			}
		},
		lights = {
			    0 = Ambient_Light{0.2},
			      1 = Point_Light{0.6, {2, 1, 0}},
			2 = Directional_Light{0.2, {1, 4, 4}}
		},
	}
}
