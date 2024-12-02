package tinigen

import "core:fmt"

import "base:runtime"
import "core:time"

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

main :: proc() {
	if ok := main_with_ok(); !ok {
		os.exit(1)
	}
}

main_with_ok :: proc() -> (ok: bool) {


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

	model_filepath := "models/WaterBottle.glb"

	start := time.now()
	scene, loaded := load_gltf(model_filepath)

	if !loaded {
		fmt.printfln("Failed to load %s", model_filepath)
		return
	}

	fmt.printfln("Loaded %s in %f seconds", model_filepath, time.since(start))
	for mesh in scene.meshes {
		fmt.printfln("Loaded %d vertices %d indices", len(mesh.vertices), len(mesh.indices))
	}

	vs_filepath := "./shaders/vs.vert.glsl"
	fs_filepath := "./shaders/fs.frag.glsl"

	program := gl.load_shaders_file(vs_filepath, fs_filepath) or_return

	gpu_meshes := upload_mesh_to_gpu(scene.meshes[:]) or_return

	skybox_program := gl.load_shaders_file(
		"./shaders/skybox.vert.glsl",
		"./shaders/skybox.frag.glsl",
	) or_return

	pipeline_skybox_stage_desc := PipelineStageDescription {
		program = skybox_program,
		state = PipelineState {
			cull_face = true,
			cull_mode = .Front,
			front_face = .CounterClockwise,
			depth_test = true,
			blend = true,
			blend_src = .SrcAlpha,
			blend_dst = .OneMinusSrcAlpha,
			back_polygon_mode = .Fill,
			front_polygon_mode = .Fill,
			depth_func = .LessEqual,
		}
	}

	pipeline_pbr_stage_desc := PipelineStageDescription {
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
			depth_func = .Less,
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
							format = .Float4,
							normalized = gl.FALSE,
							offset = u32(offset_of(Vertex, tangent)),
						},
						VertexInputAttribute {
							location = 3,
							format = .Float2,
							normalized = gl.FALSE,
							offset = u32(offset_of(Vertex, texcoord)),
						},
					},
				},
			},
		},
	}

	pipeline := create_pipeline(
		PipelineDescription {
			render_target = create_framebuffer(
				FramebufferDescription {
					width = WINDOW_WIDTH,
					height = WINDOW_HEIGHT,
					attachments = []FramebufferAttachment {
						FramebufferAttachment{type = .Color, format = .RGBA32F, handle = 0},
						FramebufferAttachment{type = .Depth, format = .Depth32, handle = 0},
					},
				},
			),
			stages = []PipelineStageDescription {
				pipeline_skybox_stage_desc,
				pipeline_pbr_stage_desc,
			}
		},
	)

	pipeline_skybox_stage := &pipeline.stages[0]
	pipeline_pbr_stage := &pipeline.stages[1]

	projection := glm.mat4Perspective(
		glm.radians_f32(70.0),
		f32(WINDOW_WIDTH) / f32(WINDOW_HEIGHT),
		0.1,
		10000.0,
	)
	view := glm.identity(glm.mat4)

	frame_start_time := glfw.GetTime()
	frame_end_time := glfw.GetTime()
	frame_elapsed_time: f32 = 0.0
	frame_count := 0

	current_window_width, current_window_height := glfw.GetWindowSize(window)

	cam_x: f32 = 0.0
	cam_y: f32 = 0.0
	cam_z: f32 = 0.0

	cam_angle_x: f32 = 0.0
	cam_angle_y: f32 = 0.0

	fullscreen_blit_program := gl.load_shaders_file(
		"./shaders/fullscreen_blit.vert.glsl",
		"./shaders/fullscreen_blit.frag.glsl",
	) or_return

	sobel_effect_program := gl.load_compute_file("./shaders/effects/sobel.comp.glsl") or_return

	sobel_effect_out_texture := create_texture_2d(
		WINDOW_WIDTH,
		WINDOW_HEIGHT,
		.RGBA,
		.RGBA32F,
		nil,
	)

	running = true

	UniformBlock :: struct {
		view_proj: glm.mat4,
		projection: glm.mat4,
		view: glm.mat4,
		camera_pos: glm.vec3,
	}

	uniform_buffer := create_buffer(1, size_of(UniformBlock), nil, .Dynamic)

	sky : ^Cubemap2D = nil

	{
		cubemap_pixel, cubemap_width, cubemap_height := load_cubemap_pixels_from_file({
			"./textures/skybox/right.jpg",
			"./textures/skybox/left.jpg",
			"./textures/skybox/top.jpg",
			"./textures/skybox/bottom.jpg",
			"./textures/skybox/front.jpg",
			"./textures/skybox/back.jpg",
		}) or_return
	
		sky = create_cubemap_2d(
			cubemap_width, 
			cubemap_height,
			.RGBA,
			.RGBA8,
			cubemap_pixel,
		)

		free_cubemap_pixels(cubemap_pixel)

		if sky == nil {
			running = false
			return
		}
	}

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
		camera := glm.vec3{cam_x, cam_y, zoom_factor + cam_z}
		view = glm.mat4LookAt(camera, {cam_x, cam_y, cam_z - 1}, {0, 1, 0})
		view *= glm.mat4Rotate(glm.vec3{1, 0, 0}, glm.radians_f32(cam_angle_x))
		view *= glm.mat4Rotate(glm.vec3{0, 1, 0}, glm.radians_f32(cam_angle_y))

		if glfw.GetKey(window, glfw.KEY_W) == glfw.PRESS {
			cam_z -= 1 * frame_elapsed_time
		}
		if glfw.GetKey(window, glfw.KEY_S) == glfw.PRESS {
			cam_z += 1 * frame_elapsed_time
		}
		if glfw.GetKey(window, glfw.KEY_A) == glfw.PRESS {
			cam_x -= 1 * frame_elapsed_time
		}
		if glfw.GetKey(window, glfw.KEY_D) == glfw.PRESS {
			cam_x += 1 * frame_elapsed_time
		}
		if glfw.GetKey(window, glfw.KEY_Q) == glfw.PRESS {
			cam_y -= 1 * frame_elapsed_time
		}
		if glfw.GetKey(window, glfw.KEY_E) == glfw.PRESS {
			cam_y += 1 * frame_elapsed_time
		}

		if glfw.GetKey(window, glfw.KEY_LEFT) == glfw.PRESS {
			cam_angle_y += 90 * frame_elapsed_time
		}
		if glfw.GetKey(window, glfw.KEY_RIGHT) == glfw.PRESS {
			cam_angle_y -= 90 * frame_elapsed_time
		}
		if glfw.GetKey(window, glfw.KEY_UP) == glfw.PRESS {
			cam_angle_x += 90 * frame_elapsed_time
		}
		if glfw.GetKey(window, glfw.KEY_DOWN) == glfw.PRESS {
			cam_angle_x -= 90 * frame_elapsed_time
		}


		gl.ClearColor(0, 0, 0, 1.0)
		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

		pipeline_begin(&pipeline)
		clear_color := [4]f32{0.2, 0.3, 0.3, 1.0}
		pipeline_clear_render_target(&pipeline, &clear_color[0])

		uniform_block := UniformBlock {
			view_proj = projection * view,
			projection = projection,
			view = view,
			camera_pos = camera,
		}

		pipeline_stage_begin(pipeline_skybox_stage)
		pipeline_stage_bind_uniform_block(pipeline_skybox_stage, "UniformBlock", 0, uniform_buffer, &uniform_block)
		pipeline_stage_bind_cube_map(pipeline_skybox_stage, "uSkybox", 0, sky)

		gl.DrawArrays(gl.TRIANGLES, 0, 36)

		pipeline_stage_end(pipeline_skybox_stage)

		pipeline_stage_begin(pipeline_pbr_stage)
		pipeline_stage_bind_uniform_block(pipeline_pbr_stage, "UniformBlock", 0, uniform_buffer, &uniform_block)

		for mesh, index in gpu_meshes {

			transform_matrix := glm.mat4Scale(scene.meshes[index].transform.scale)
			transform_matrix *= glm.mat4FromQuat(scene.meshes[index].transform.rotation)
			transform_matrix *= glm.mat4Translate(scene.meshes[index].transform.position)

			pipeline_stage_set_uniform_mat4(pipeline_pbr_stage, "uModel", &transform_matrix[0][0])

			pipeline_stage_set_vertex_buffer(pipeline_pbr_stage, 0, mesh.vbo)
			pipeline_stage_set_element_buffer(pipeline_pbr_stage, mesh.ebo)

			if scene.meshes[index].meterial.diffuse_texture != nil {
				pipeline_stage_bind_texture2d(
					pipeline_pbr_stage,
					"uAlbedoTexture",
					0,
					scene.meshes[index].meterial.diffuse_texture,
				)
			}
			if scene.meshes[index].meterial.normal_texture != nil {
				pipeline_stage_bind_texture2d(
					pipeline_pbr_stage,
					"uNormalTexture",
					1,
					scene.meshes[index].meterial.normal_texture,
				)
			}

			if scene.meshes[index].meterial.metallic_roughness_texture != nil {
				pipeline_stage_bind_texture2d(
					pipeline_pbr_stage,
					"uMetallicRoughnessTexture",
					2,
					scene.meshes[index].meterial.metallic_roughness_texture,
				)
			}

			gl.DrawElements(gl.TRIANGLES, i32(mesh.ebo.count), gl.UNSIGNED_INT, nil)
		}

		pipeline_stage_end(pipeline_pbr_stage)

		pipeline_end(&pipeline)

		// gl.UseProgram(sobel_effect_program)


		// gl.BindImageTexture(0, pipeline.render_target.handle, 0, gl.FALSE, 0, gl.READ_ONLY, u32(pipeline.render_target.attachments[0].format))
		// gl.BindImageTexture(1, sobel_effect_out_texture.handle, 0, gl.FALSE, 0, gl.WRITE_ONLY, u32(sobel_effect_out_texture.format))
		// gl.DispatchCompute(WINDOW_WIDTH/8, WINDOW_HEIGHT/8, 1)

		// i don't know what should i do here
		// gl.MemoryBarrier(gl.SHADER_IMAGE_ACCESS_BARRIER_BIT)

		gl.UseProgram(fullscreen_blit_program)
		gl.BindTexture(gl.TEXTURE_2D, pipeline.render_target.attachments[0].handle)
		gl.DrawArrays(gl.TRIANGLES, 0, 6)

		// pipeline_blit_onto_default(&pipeline, current_window_width, current_window_height)
	
		glfw.SwapBuffers((window))

		frame_end_time = glfw.GetTime()
		frame_elapsed_time = f32(frame_end_time - frame_start_time)

		frame_count += 1

		if (frame_count % 100 == 0) {
			fmt.printfln("Frame time: %f, FPS: %f", frame_elapsed_time, 1.0 / frame_elapsed_time)
		}
	}

	glfw.DestroyWindow(window)

	glfw.Terminate()

	ok = true
	return
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
