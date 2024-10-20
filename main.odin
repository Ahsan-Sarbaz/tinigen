package tinigen

import "core:fmt"

import "base:runtime"

import gl "vendor:OpenGL"
import "vendor:glfw"

import glm "core:math/linalg/glsl"

GL_MAJOR_VERSION :: 4
GL_MINOR_VERSION :: 6
WINDOW_WIDTH :: 1920
WINDOW_HEIGHT :: 1080

running: b32 = true

main :: proc() {

	glfw.WindowHint(glfw.RESIZABLE, 1)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_MAJOR_VERSION)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_MINOR_VERSION)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)

	if (glfw.Init() != glfw.TRUE) {
		fmt.println("Failed to initialize GLFW")
		return
	}
	defer glfw.Terminate()

	window := glfw.CreateWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "tiniGEN", nil, nil)
	defer glfw.DestroyWindow(window)

	if window == nil {
		fmt.println("Unable to create window")
		return
	}

	glfw.MakeContextCurrent(window)
	glfw.SwapInterval(1)
	glfw.SetKeyCallback(window, key_callback)
	glfw.SetFramebufferSizeCallback(window, size_callback)

	gl.load_up_to(int(GL_MAJOR_VERSION), GL_MINOR_VERSION, glfw.gl_set_proc_address)

	gl.DebugMessageCallback(gl_debug_callback, nil)
	gl.Enable(gl.DEBUG_OUTPUT)
	gl.Enable(gl.DEBUG_OUTPUT_SYNCHRONOUS)
	gl.DebugMessageControl(gl.DONT_CARE, gl.DONT_CARE, gl.DONT_CARE, 0, nil, gl.FALSE)
	gl.DebugMessageControl(gl.DEBUG_SOURCE_API, gl.DEBUG_TYPE_ERROR, gl.DONT_CARE, 0, nil, gl.TRUE)


	vs_source := `#version 460
    layout (location = 0) in vec3 aPos;
    layout (location = 1) in vec3 aColor;
    layout (location = 2) in vec3 aNormal;

    uniform mat4 uProjection;
    uniform mat4 uView;
    uniform mat4 uModel;

    out vec3 Color;
    out vec3 Normal;
    void main() {
        gl_Position = uProjection * uView * uModel * vec4(aPos, 1.0);
        Color = aColor;
        Normal = aNormal;
    }
    `

	fs_source := `#version 460
    out vec4 FragColor;
    in vec3 Color;
    in vec3 Normal;
    void main() {
        FragColor = vec4(Color * Normal, 1.0);
    }
    `

	program, ok := gl.load_shaders_source(vs_source, fs_source)
	if !ok {
		return
	}

	cube_vertices := []f32 {
		// front
		-1.0,
		-1.0,
		1.0,
		1,
		1,
		1,
		1.0,
		-1.0,
		1.0,
		1,
		1,
		1,
		1.0,
		1.0,
		1.0,
		1,
		1,
		1,
		-1.0,
		1.0,
		1.0,
		1,
		1,
		1,
		// back
		-1.0,
		-1.0,
		-1.0,
		1,
		1,
		1,
		1.0,
		-1.0,
		-1.0,
		1,
		1,
		1,
		1.0,
		1.0,
		-1.0,
		1,
		1,
		1,
		-1.0,
		1.0,
		-1.0,
		1,
		1,
		1,
	}

	cube_colors := []f32 {
		// front
		0,
		0,
		1,
		1,
		0,
		1,
		0,
		1,
		1,
		0,
		0,
		1,
		1,
		1,
		1,
		1,
		// back
		0,
		1,
		0,
		1,
		1,
		0,
		0,
		1,
		1,
		1,
		1,
		1,
		0,
		0,
		1,
		1,
	}

	cube_vbo := create_buffer(
		u32(len(cube_vertices) * size_of(f32)),
		raw_data(cube_vertices),
		.Static,
	)
	cube_vbo_color := create_buffer(
		u32(len(cube_colors) * size_of(f32)),
		raw_data(cube_colors),
		.Static,
	)

	cube_indices := []u32 {
		0,
		1,
		2,
		2,
		3,
		0,
		1,
		5,
		6,
		6,
		2,
		1,
		7,
		6,
		5,
		5,
		4,
		7,
		4,
		0,
		3,
		3,
		7,
		4,
		4,
		5,
		1,
		1,
		0,
		4,
		3,
		2,
		6,
		6,
		7,
		3,
	}

	cube_ebo := create_buffer(
		u32(len(cube_indices) * size_of(u32)),
		raw_data(cube_indices),
		.Static,
	)

	pipeline := create_pipeline(
		PipelineDescription {
			render_target = create_framebuffer(
				FramebufferDescription {
					width = WINDOW_WIDTH,
					height = WINDOW_HEIGHT,
					attachments = []FramebufferAttachment {
						FramebufferAttachment{type = .Color, format = .RGBA8, handle = 0},
						FramebufferAttachment{type = .Depth, format = .Depth32, handle = 0},
					},
				},
			),
			program = program,
			state = PipelineState {
				cull_face = true,
				cull_mode = .Back,
				front_face = .CounterClockwise,
				depth_test = true,
				blend = true,
				blend_src = .SrcAlpha,
				blend_dst = .OneMinusSrcAlpha,
				back_polygon_mode = .Fill,
				front_polygon_mode = .Fill,
			},
			layout = VertexInputLayout {
				bindings = []VertexInputBinding {
					VertexInputBinding {
						binding = 0,
						stride = 6 * size_of(f32),
						elements = []VertexInputAttribute {
							VertexInputAttribute {
								location = 0,
								format = .Float3,
								normalized = gl.FALSE,
								offset = 0,
							},
							VertexInputAttribute {
								location = 1,
								format = .Float3,
								normalized = gl.FALSE,
								offset = 3 * size_of(f32),
							},
						},
					},
					VertexInputBinding {
						binding = 1,
						stride = 3 * size_of(f32),
						elements = []VertexInputAttribute {
							VertexInputAttribute {
								location = 2,
								format = .Float3,
								normalized = gl.FALSE,
								offset = 0,
							},
						},
					},
				},
			},
		},
	)

	projection := glm.mat4Perspective(
		glm.radians_f32(70.0),
		f32(WINDOW_WIDTH) / f32(WINDOW_HEIGHT),
		0.1,
		1000.0,
	)
	model := glm.identity(glm.mat4)
	view := glm.identity(glm.mat4)

	angle: f32 = 0.0

	frame_start_time := glfw.GetTime()
	frame_end_time := glfw.GetTime()
	frame_elapsed_time := frame_end_time - frame_start_time

	frame_count := 0

	current_window_width, current_window_height := glfw.GetWindowSize(window)

	for (!glfw.WindowShouldClose(window) && running) {
		frame_start_time = glfw.GetTime()

		w, h := glfw.GetWindowSize(window)

		if w != current_window_width || h != current_window_height {
			current_window_width = w
			current_window_height = h
			pipeline_resize(&pipeline, w, h)
			projection = glm.mat4Perspective(glm.radians_f32(70.0), f32(w) / f32(h), 0.1, 1000.0)
		}

		glfw.PollEvents()

		model = glm.mat4Translate({0, 0, -5})
		model *= glm.mat4Rotate({1, 1, 1}, glm.radians_f32(angle))

		angle += 1

		gl.ClearColor(0, 0, 0, 1.0)
		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

		pipeline_begin(&pipeline)
		clear_color := [4]f32{0.2, 0.3, 0.3, 1.0}
		pipeline_clear_render_target(&pipeline, &clear_color[0])
		pipeline_set_vertex_buffer(&pipeline, 0, cube_vbo)
		pipeline_set_vertex_buffer(&pipeline, 1, cube_vbo_color)
		pipeline_set_element_buffer(&pipeline, cube_ebo)
		pipeline_set_uniform_mat4(&pipeline, "uProjection", &projection[0][0])
		pipeline_set_uniform_mat4(&pipeline, "uModel", &model[0][0])
		pipeline_set_uniform_mat4(&pipeline, "uView", &view[0][0])

		gl.DrawElements(gl.TRIANGLES, 36, gl.UNSIGNED_INT, nil)

		pipeline_end(&pipeline)

		pipeline_blit_onto_default(&pipeline, current_window_width, current_window_height)

		glfw.SwapBuffers((window))

		frame_end_time = glfw.GetTime()
		frame_elapsed_time := frame_end_time - frame_start_time

		frame_count += 1

		if (frame_count % 100 == 0) {
			fmt.printfln("Frame time: %f, FPS: %f", frame_elapsed_time, 1.0 / frame_elapsed_time)
		}
	}

}

key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	if key == glfw.KEY_ESCAPE {
		running = false
	}
}

size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	gl.Viewport(0, 0, width, height)
}

gl_debug_callback :: proc "c" (
	source: u32,
	type: u32,
	id: u32,
	severity: u32,
	length: i32,
	message: cstring,
	userParam: rawptr,
) {
	context = runtime.default_context()
	fmt.printfln(
		"Source: %d, Type: %d, ID: %d, Severity: %d, Length: %d, Message: %s",
		source,
		type,
		id,
		severity,
		length,
		message,
	)
}
