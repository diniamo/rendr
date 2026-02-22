package opengl

import "core:fmt"
import "core:os"
import "vendor:glfw"
import gl "vendor:OpenGL"

GL_MAJOR :: 3
GL_MINOR :: 3

WIDTH  :: 800
HEIGHT :: 600

VERTEX_COUNT :: 3

// Interleaved: position, color, position, ...
vertecies := [VERTEX_COUNT * 3 * 2]f32{
	-0.5, -0.5, 0.0,
	 0.0,  1.0, 0.0,

	 0.5, -0.5, 0.0,
	 0.0,  0.0, 1.0,

	 0.0,  0.5, 0.0,
	 1.0,  0.0, 0.0,
}

vertex_shader_source:   cstring = #load("shader.vert")
fragment_shader_source: cstring = #load("shader.frag")

main :: proc() {
	glfw.SetErrorCallback(proc "c" (_: i32, description: cstring) {
		context = {}

		fmt.fprintln(os.stderr, "GLFW:", description)
	})
	glfw.Init()

	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_MAJOR)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_MINOR)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)

	window := glfw.CreateWindow(WIDTH, HEIGHT, "OpenGL Renderer", nil, nil)
	if window == nil { fatal("Failed to open window") }

	glfw.MakeContextCurrent(window)


	gl.load_up_to(GL_MAJOR, GL_MINOR, glfw.gl_set_proc_address)

	gl.Viewport(0, 0, WIDTH, HEIGHT)
	glfw.SetFramebufferSizeCallback(window, resize)

	vbo: u32 = ---
	gl.GenBuffers(1, &vbo)

	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
	gl.BufferData(gl.ARRAY_BUFFER, size_of(vertecies), &vertecies, gl.STATIC_DRAW)

	vertex_shader := gl.CreateShader(gl.VERTEX_SHADER)
	gl.ShaderSource(vertex_shader, 1, &vertex_shader_source, nil)
	gl.CompileShader(vertex_shader)
	check_shader_compilation(vertex_shader)

	fragment_shader := gl.CreateShader(gl.FRAGMENT_SHADER)
	gl.ShaderSource(fragment_shader, 1, &fragment_shader_source, nil)
	gl.CompileShader(fragment_shader)
	check_shader_compilation(fragment_shader)

	shader_program := gl.CreateProgram()
	gl.AttachShader(shader_program, vertex_shader)
	gl.AttachShader(shader_program, fragment_shader)
	gl.LinkProgram(shader_program)
	check_shader_program_linkage(shader_program)
	gl.DeleteShader(vertex_shader)
	gl.DeleteShader(fragment_shader)

	gl.UseProgram(shader_program)

	vao: u32 = ---
	gl.GenVertexArrays(1, &vao)
	gl.BindVertexArray(vao)

	// Vertex attribute index, value count in attribute, datatype, normalize data, stride (value size), data offset
	gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 6 * size_of(f32), 0)
	gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, 6 * size_of(f32), 3 * size_of(f32))
	gl.EnableVertexAttribArray(0)
	gl.EnableVertexAttribArray(1)

	gl.ClearColor(0, 0, 0, 1)

	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()


		gl.Clear(gl.COLOR_BUFFER_BIT)
		gl.DrawArrays(gl.TRIANGLES, 0, VERTEX_COUNT)


		glfw.SwapBuffers(window)
	}
}

resize :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	gl.Viewport(0, 0, width, height)
}

check_shader_compilation :: proc(shader: u32) {
	ok: b32 = ---
	gl.GetShaderiv(shader, gl.COMPILE_STATUS, auto_cast &ok)
	if !ok {
		info: [512]u8 = ---
		n: i32 = ---
		gl.GetShaderInfoLog(shader, len(info), &n, &info[0])

		fatalf("Failed to compile shader: %s", info[:n])
	}
}

check_shader_program_linkage :: proc(program: u32) {
	ok: b32 = ---
	gl.GetProgramiv(program, gl.LINK_STATUS, auto_cast &ok)
	if !ok {
		info: [512]u8 = ---
		n: i32 = ---
		gl.GetProgramInfoLog(program, len(info), &n, &info[0])

		fatalf("Failed to link shader program: %s", info[:n])
	}
}

fatal :: proc(args: ..any) {
	fmt.fprintln(os.stderr, ..args)
	os.exit(1)
}
fatalf :: proc(format: string, args: ..any) {
	fmt.fprintfln(os.stderr, format, ..args)
	os.exit(1)
}
