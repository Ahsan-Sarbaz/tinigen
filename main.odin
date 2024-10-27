package tinigen

import "core:fmt"

import "base:runtime"

import gl "vendor:OpenGL"
import "vendor:glfw"

import glm "core:math/linalg/glsl"

import "core:os"
import "core:strconv"
import "core:strings"

GL_MAJOR_VERSION :: 4
GL_MINOR_VERSION :: 6
WINDOW_WIDTH :: 1920
WINDOW_HEIGHT :: 1080

running: b32 = true
zoom_factor: f32 = 1.0

Vertex :: struct {
	position: glm.vec3,
	normal:   glm.vec3,
	texcoord: glm.vec2,
}

load_obj :: proc(
	filepath: string,
) -> (
	vertices: [dynamic]Vertex,
	indices: [dynamic]u32,
	ok: bool,
) {
	data := os.read_entire_file(filepath, context.allocator) or_return
	defer delete(data, context.allocator)

	it := string(data)

	positions := [dynamic]glm.vec3{}
	uvs := [dynamic]glm.vec2{}
	normals := [dynamic]glm.vec3{}

	index: u32 = 0

	for line in strings.split_lines_iterator(&it) {
		if strings.starts_with(line, "v ") {
			parts := strings.split(line, " ")
			x := strconv.parse_f32(parts[1]) or_return
			y := strconv.parse_f32(parts[2]) or_return
			z := strconv.parse_f32(parts[3]) or_return
			append(&positions, glm.vec3{x, y, z})

		} else if strings.starts_with(line, "vt ") {
			parts := strings.split(line, " ")
			u := strconv.parse_f32(parts[1]) or_return
			v := strconv.parse_f32(parts[2]) or_return
			append(&uvs, glm.vec2{u, v})

		} else if strings.starts_with(line, "vn ") {
			parts := strings.split(line, " ")
			nx := strconv.parse_f32(parts[1]) or_return
			ny := strconv.parse_f32(parts[2]) or_return
			nz := strconv.parse_f32(parts[3]) or_return
			append(&normals, glm.vec3{nx, ny, nz})
		} else if strings.starts_with(line, "f ") {
			parts := strings.split(line, " ")

			for i := 1; i <= 3; i += 1 {
				v_t_n := strings.split(parts[i], "/")

				position := glm.vec3{f32(0), f32(0), f32(0)}
				texcoord := glm.vec2{f32(0), f32(0)}
				normal := glm.vec3{f32(0), f32(0), f32(0)}

				v := strconv.parse_i64(v_t_n[0]) or_return
				position = positions[v - 1]

				if len(v_t_n) == 2 {
					if len(v_t_n[1]) > 0 {
						t := strconv.parse_i64(v_t_n[1]) or_return
						texcoord = uvs[t - 1]
					}

				} else if len(v_t_n) == 3 {
					if len(v_t_n[1]) > 0 {
						t := strconv.parse_i64(v_t_n[1]) or_return
						texcoord = uvs[t - 1]
					}

					if len(v_t_n[2]) > 0 {
						n := strconv.parse_i64(v_t_n[2]) or_return
						normal = normals[n - 1]
					}
				}

				append(&vertices, Vertex{position, normal, texcoord})
				append(&indices, index)
				index += 1
			}
		}
	}

	delete(positions)
	delete(uvs)
	delete(normals)

	ok = true
	return
}


main :: proc() {

	model_filepath := "stanford-bunny.obj"

	vertices, indices, loaded := load_obj(model_filepath)

	if !loaded {
		fmt.printfln("Failed to load %s", model_filepath)
		return
	}

	fmt.printfln("Loaded %d vertices %d indices", len(vertices), len(indices))

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
	glfw.SetScrollCallback(window, scroll_callback)
	glfw.SetFramebufferSizeCallback(window, size_callback)

	gl.load_up_to(int(GL_MAJOR_VERSION), GL_MINOR_VERSION, glfw.gl_set_proc_address)

	gl.DebugMessageCallback(gl_debug_callback, nil)
	gl.Enable(gl.DEBUG_OUTPUT)
	gl.Enable(gl.DEBUG_OUTPUT_SYNCHRONOUS)
	gl.DebugMessageControl(gl.DONT_CARE, gl.DONT_CARE, gl.DONT_CARE, 0, nil, gl.FALSE)
	gl.DebugMessageControl(gl.DEBUG_SOURCE_API, gl.DEBUG_TYPE_ERROR, gl.DONT_CARE, 0, nil, gl.TRUE)


	vs_source := `#version 460
    layout (location = 0) in vec3 aPos;
	layout (location = 1) in vec3 aNormal;
	layout (location = 2) in vec2 aTexCoords;
	
    uniform mat4 uProjection;
    uniform mat4 uView;
    uniform mat4 uModel;

	out vec3 Normal;
	out vec2 TexCoords;
	
    void main() {
        gl_Position = uProjection * uView * uModel * vec4(aPos, 1.0);
		Normal = mat3(uModel) * aNormal;
		// Normal = aNormal;
		TexCoords = aTexCoords;
    }
    `


	fs_source := `#version 460
    out vec4 FragColor;

	in vec3 Normal;
	in vec2 TexCoords;

    void main() {
        FragColor = vec4(Normal, 1.0f);
    }
    `


	program, ok := gl.load_shaders_source(vs_source, fs_source)
	if !ok {
		return
	}

	model_vbo := create_buffer(u32(len(vertices) * size_of(Vertex)), raw_data(vertices), .Static)
	model_ebo := create_buffer(u32(len(indices) * size_of(u32)), raw_data(indices), .Static)

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
						stride = size_of(Vertex),
						elements = []VertexInputAttribute {
							VertexInputAttribute {
								location = 0,
								format = .Float3,
								normalized = gl.FALSE,
								offset = u32(offset_of(Vertex, position)),
							},
							VertexInputAttribute {
								location = 1,
								format = .Float3,
								normalized = gl.FALSE,
								offset = u32(offset_of(Vertex, normal)),
							},
							VertexInputAttribute {
								location = 2,
								format = .Float2,
								normalized = gl.FALSE,
								offset = u32(offset_of(Vertex, texcoord)),
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
	frame_elapsed_time : f32 = 0.0
	frame_count := 0

	current_window_width, current_window_height := glfw.GetWindowSize(window)

	cam_x : f32= 0.0
	cam_y : f32= 0.0

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

		// view = glm.mat4Translate({0, 0, -(zoom_factor * frame_elapsed_time)})
		view = glm.mat4LookAt({cam_x, cam_y, zoom_factor * 0.4}, {cam_x, cam_y, 0}, {0, 1, 0})
		model = glm.mat4Rotate({0, 1, 0}, glm.radians_f32(angle))

		if glfw.GetKey(window, glfw.KEY_W) == glfw.PRESS {
			cam_y += 0.1 * frame_elapsed_time
		} else if glfw.GetKey(window, glfw.KEY_S) == glfw.PRESS {
			cam_y -= 0.1 * frame_elapsed_time
		} else if glfw.GetKey(window, glfw.KEY_A) == glfw.PRESS {
			cam_x -= 0.1 * frame_elapsed_time
		} else if glfw.GetKey(window, glfw.KEY_D) == glfw.PRESS {
			cam_x += 0.1 * frame_elapsed_time
		}

		angle += 1

		gl.ClearColor(0, 0, 0, 1.0)
		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

		pipeline_begin(&pipeline)
		clear_color := [4]f32{0.2, 0.3, 0.3, 1.0}
		pipeline_clear_render_target(&pipeline, &clear_color[0])
		pipeline_set_vertex_buffer(&pipeline, 0, model_vbo)

		// pipeline_set_vertex_buffer(&pipeline, 1, cube_vbo_color)
		pipeline_set_element_buffer(&pipeline, model_ebo)
		pipeline_set_uniform_mat4(&pipeline, "uProjection", &projection[0][0])
		pipeline_set_uniform_mat4(&pipeline, "uModel", &model[0][0])
		pipeline_set_uniform_mat4(&pipeline, "uView", &view[0][0])

		gl.DrawElements(gl.TRIANGLES, i32(len(indices)), gl.UNSIGNED_INT, nil)

		pipeline_end(&pipeline)

		pipeline_blit_onto_default(&pipeline, current_window_width, current_window_height)

		glfw.SwapBuffers((window))

		frame_end_time = glfw.GetTime()
		frame_elapsed_time = f32(frame_end_time - frame_start_time)

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

scroll_callback :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
	zoom_factor += f32(yoffset)	
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
