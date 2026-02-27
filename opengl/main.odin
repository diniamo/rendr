package opengl

import "core:fmt"
import "core:os"
import sdl "vendor:sdl3"
import gl "vendor:OpenGL"

GL_MAJOR :: 3
GL_MINOR :: 3

VERTEX_COUNT :: 3

vertecies := [VERTEX_COUNT * 3 * 2]f32{
	// position        color
	-0.5, -0.5, 0.0,   0.0, 1.0, 0.0,
	 0.5, -0.5, 0.0,   0.0, 0.0, 1.0,
	 0.0,  0.5, 0.0,   1.0, 0.0, 0.0,
}

vertex_shader_source:   cstring = #load("shader.vert")
fragment_shader_source: cstring = #load("shader.frag")

main :: proc() {
	ok := sdl.Init({})
	if !ok { fatal("Failed to initialize SDL:", sdl.GetError()) }

	sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, GL_MAJOR)
	sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, GL_MINOR)
	sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, auto_cast sdl.GLProfile{.CORE})

	window := sdl.CreateWindow("OpenGL Renderer", 0, 0, {.OPENGL, .RESIZABLE})
	if window == nil { fatal("Failed to open window:", sdl.GetError()) }

	gl_context := sdl.GL_CreateContext(window)
	if gl_context == nil { fatal("Failed to create OpenGL context:", sdl.GetError()) }

	sdl.GL_MakeCurrent(window, gl_context)

	// 0  - immediate
	// 1  - v-sync
	// -1 - adaptive sync
	sdl.GL_SetSwapInterval(1)


	gl.load_up_to(GL_MAJOR, GL_MINOR, sdl.gl_set_proc_address)

	vbo: u32 = ---
	gl.GenBuffers(1, &vbo)

	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
	gl.BufferData(gl.ARRAY_BUFFER, size_of(vertecies), &vertecies, gl.STATIC_DRAW)

	shader_program := create_shader_program(&vertex_shader_source, &fragment_shader_source)
	gl.UseProgram(shader_program)

	vao: u32 = ---
	gl.GenVertexArrays(1, &vao)
	gl.BindVertexArray(vao)

	// Vertex attribute index, value count in attribute, datatype, normalize data, stride (value size), data offset
	gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 6 * size_of(f32), 0)
	gl.EnableVertexAttribArray(0)

	gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, 6 * size_of(f32), 3 * size_of(f32))
	gl.EnableVertexAttribArray(1)

	gl.ClearColor(0, 0, 0, 1)

	main_loop: for {
		for event: sdl.Event = ---; sdl.PollEvent(&event); {
			#partial switch event.type {
			case .WINDOW_RESIZED:
				width := event.window.data1
				height := event.window.data2

				gl.Viewport(0, 0, width, height)
			case .QUIT, .WINDOW_CLOSE_REQUESTED:
				break main_loop
			}
		}


		gl.Clear(gl.COLOR_BUFFER_BIT)
		gl.DrawArrays(gl.TRIANGLES, 0, VERTEX_COUNT)


		sdl.GL_SwapWindow(window)
	}
}

create_shader_program :: proc(vertex_shader_sources, fragment_shader_sources: [^]cstring) -> u32 {
	create_shader :: proc(type: u32, sources: [^]cstring) -> u32 {
		shader := gl.CreateShader(type)
		gl.ShaderSource(shader, 1, sources, nil)
		gl.CompileShader(shader)

		ok: b32
		gl.GetShaderiv(shader, gl.COMPILE_STATUS, auto_cast &ok)
		if !ok {
			info: [512]u8 = ---
			n: i32
			gl.GetShaderInfoLog(shader, len(info), &n, &info[0])

			fatalf("Failed to compile shader: %s", info[:n])
		}

		return shader
	}

	vertex_shader := create_shader(gl.VERTEX_SHADER, vertex_shader_sources)
	defer gl.DeleteShader(vertex_shader)

	fragment_shader := create_shader(gl.FRAGMENT_SHADER, fragment_shader_sources)
	defer gl.DeleteShader(fragment_shader)

	shader_program := gl.CreateProgram()
	gl.AttachShader(shader_program, vertex_shader)
	gl.AttachShader(shader_program, fragment_shader)
	gl.LinkProgram(shader_program)

	ok: b32
	gl.GetProgramiv(shader_program, gl.LINK_STATUS, auto_cast &ok)
	if !ok {
		info: [512]u8 = ---
		n: i32
		gl.GetProgramInfoLog(shader_program, len(info), &n, &info[0])

		fatalf("Failed to link shader program: %s", info[:n])
	}

	return shader_program
}

fatal :: proc(args: ..any) {
	fmt.fprintln(os.stderr, ..args)
	os.exit(1)
}
fatalf :: proc(format: string, args: ..any) {
	fmt.fprintfln(os.stderr, format, ..args)
	os.exit(1)
}
