package tinigen

import "core:fmt"
import "core:strings"

import gl "vendor:OpenGL"

BufferUsage :: enum {
	Static,
	Dynamic,
	Stream,
}

GpuBuffer :: struct {
	handle: u32,
	size:   u32,
	count:  u32,
	usage:  BufferUsage,
}

create_buffer :: proc(
	count: u32,
	size_per_element: u32,
	data: rawptr,
	usage: BufferUsage,
) -> (
	buffer: GpuBuffer,
) {
	buffer.size = count * size_per_element
	buffer.count = count
	buffer.usage = usage
	flags: u32 = 0

	#partial switch usage {
	case .Dynamic:
		flags = gl.DYNAMIC_STORAGE_BIT
	case .Stream:
		flags = gl.DYNAMIC_STORAGE_BIT | gl.MAP_WRITE_BIT
	}

	gl.CreateBuffers(1, &buffer.handle)
	gl.NamedBufferStorage(buffer.handle, int(buffer.size), data, flags)
	return
}


buffer_sub_data :: proc(buffer: GpuBuffer, offset: u32, data: rawptr) {
	gl.NamedBufferSubData(buffer.handle, int(offset), int(buffer.size), data)
}

CompareFunc :: enum u32 {
	Never        = gl.NEVER,
	Less         = gl.LESS,
	Equal        = gl.EQUAL,
	LessEqual    = gl.LEQUAL,
	Greater      = gl.GREATER,
	NotEqual     = gl.NOTEQUAL,
	GreaterEqual = gl.GEQUAL,
	Always       = gl.ALWAYS,
}

CullMode :: enum {
	Front,
	Back,
	FrontAndBack,
}

FrontFace :: enum {
	Clockwise,
	CounterClockwise,
}

BlendFactor :: enum {
	Zero             = gl.ZERO,
	One              = gl.ONE,
	SrcColor         = gl.SRC_COLOR,
	DstColor         = gl.DST_COLOR,
	OneMinusSrcColor = gl.ONE_MINUS_SRC_COLOR,
	OneMinusDstColor = gl.ONE_MINUS_DST_COLOR,
	SrcAlpha         = gl.SRC_ALPHA,
	DstAlpha         = gl.DST_ALPHA,
	OneMinusSrcAlpha = gl.ONE_MINUS_SRC_ALPHA,
	OneMinusDstAlpha = gl.ONE_MINUS_DST_ALPHA,
}

PolygonMode :: enum {
	Fill  = gl.FILL,
	Line  = gl.LINE,
	Point = gl.POINT,
}

PipelineState :: struct {
	cull_face:          bool,
	cull_mode:          CullMode,
	front_face:         FrontFace,
	depth_test:         bool,
	blend:              bool,
	blend_src:          BlendFactor,
	blend_dst:          BlendFactor,
	front_polygon_mode: PolygonMode,
	back_polygon_mode:  PolygonMode,
}

Pipeline :: struct {
	render_target:     ^Framebuffer,
	program:           u32,
	vertex_input:      VertexInput,
	uniform_locations: map[string]i32,
	state:             PipelineState,
	old_state:         PipelineState,
}

VertexFormat :: enum {
	Float1,
	Float2,
	Float3,
	Float4,
	Int1,
	Int2,
	Int3,
	Int4,
}

VertexInputAttribute :: struct {
	location:   u32,
	format:     VertexFormat,
	normalized: bool,
	offset:     u32,
}

vertex_format_get_size_type :: proc(format: VertexFormat) -> (size: i32, type: u32) {
	switch format {
	case .Float1:
		size = 1
		type = gl.FLOAT
	case .Float2:
		size = 2
		type = gl.FLOAT
	case .Float3:
		size = 3
		type = gl.FLOAT
	case .Float4:
		size = 4
		type = gl.FLOAT
	case .Int1:
		size = 1
		type = gl.INT
	case .Int2:
		size = 2
		type = gl.INT
	case .Int3:
		size = 3
		type = gl.INT
	case .Int4:
		size = 4
		type = gl.INT
	}

	return
}

VertexInputRate :: enum {
	Vertex,
	Instance,
}

VertexInputBinding :: struct {
	binding:  u32,
	stride:   i32,
	rate:     VertexInputRate,
	divisor:  u32,
	elements: []VertexInputAttribute,
}

VertexInputLayout :: struct {
	bindings: []VertexInputBinding,
}

VertexInput :: struct {
	layout: VertexInputLayout,
	vao:    u32,
}

create_input_binding :: proc(
	binding_index: u32,
	stride: i32,
	elements: []VertexInputAttribute,
) -> (
	binding: VertexInputBinding,
) {
	binding.binding = binding_index
	binding.stride = stride
	binding.elements = elements
	return
}

create_vertex_input_layout :: proc(bindings: []VertexInputBinding) -> (layout: VertexInputLayout) {
	layout.bindings = bindings
	return
}

create_vertex_input :: proc(layout: VertexInputLayout) -> (input: VertexInput) {
	input.layout = layout

	gl.CreateVertexArrays(1, &input.vao)

	for binding in layout.bindings {
		for element in binding.elements {
			size, type := vertex_format_get_size_type(element.format)
			gl.VertexArrayAttribBinding(input.vao, element.location, binding.binding)
			gl.VertexArrayAttribFormat(
				input.vao,
				element.location,
				size,
				type,
				element.normalized == gl.TRUE ? gl.TRUE : gl.FALSE,
				element.offset,
			)
			gl.EnableVertexArrayAttrib(input.vao, element.location)
		}
	}

	return
}

PipelineDescription :: struct {
	render_target: ^Framebuffer,
	layout:        VertexInputLayout,
	state:         PipelineState,
	program:       u32,
}

create_pipeline :: proc(desc: PipelineDescription) -> (pipeline: Pipeline) {
	pipeline.render_target = desc.render_target
	pipeline.program = desc.program
	pipeline.state = desc.state
	pipeline.vertex_input = create_vertex_input(desc.layout)
	return
}

pipeline_set_vertex_buffer :: proc(pipeline: ^Pipeline, binding: u32, buffer: GpuBuffer) {
	if (pipeline.vertex_input.vao == 0) {
		fmt.println("Invalid vertex input")
		return
	}

	if (int(binding) >= len(pipeline.vertex_input.layout.bindings)) {
		fmt.println("Invalid binding index")
		return
	}

	gl.VertexArrayVertexBuffer(
		pipeline.vertex_input.vao,
		binding,
		buffer.handle,
		0,
		pipeline.vertex_input.layout.bindings[binding].stride,
	)
}

pipeline_set_element_buffer :: proc(pipeline: ^Pipeline, buffer: GpuBuffer) {
	if (pipeline.vertex_input.vao == 0) {
		fmt.println("Invalid vertex input")
		return
	}

	gl.VertexArrayElementBuffer(pipeline.vertex_input.vao, buffer.handle)
}

pipeline_bind_uniform_block :: proc(pipeline: ^Pipeline, name: string, binding: u32, buffer : GpuBuffer,  data : rawptr) {
	location := gl.GetUniformBlockIndex(pipeline.program, strings.unsafe_string_to_cstring(name))
	if (location == gl.INVALID_INDEX) {
		fmt.println("Could not find uniform block", name)
		return
	}
	gl.UniformBlockBinding(pipeline.program, location, binding)
	gl.NamedBufferSubData(buffer.handle, 0, int(buffer.size), data)
	gl.BindBufferBase(gl.UNIFORM_BUFFER, binding, buffer.handle)
}

pipeline_clear_render_target :: proc(
	pipeline: ^Pipeline,
	color: [^]f32,
	depth: f32 = 1.0,
	stencil: i32 = 1,
) {
	if (pipeline.render_target != nil) {
		framebuffer_clear_attachments(pipeline.render_target, color, depth, stencil)
	}
}

pipeline_begin :: proc(pipeline: ^Pipeline) {
	gl.UseProgram(pipeline.program)
	gl.BindVertexArray(pipeline.vertex_input.vao)

	pipeline.old_state.blend = gl.IsEnabled(gl.BLEND)

	if (pipeline.state.blend) {
		gl.Enable(gl.BLEND)
		gl.BlendFunc(u32(pipeline.state.blend_src), u32(pipeline.state.blend_dst))
	} else {
		gl.Disable(gl.BLEND)
	}

	pipeline.old_state.depth_test = gl.IsEnabled(gl.DEPTH_TEST)

	if (pipeline.state.depth_test) {
		gl.Enable(gl.DEPTH_TEST)
	} else {
		gl.Disable(gl.DEPTH_TEST)
	}

	switch (pipeline.state.cull_mode) {
	case .Front:
		gl.CullFace(gl.FRONT)
	case .Back:
		gl.CullFace(gl.BACK)
	case .FrontAndBack:
		gl.CullFace(gl.FRONT_AND_BACK)
	}

	pipeline.old_state.cull_face = gl.IsEnabled(gl.CULL_FACE)
	if (pipeline.state.cull_face) {
		gl.Enable(gl.CULL_FACE)
	} else {
		gl.Disable(gl.CULL_FACE)
	}


	gl.PolygonMode(gl.FRONT, u32(pipeline.state.front_polygon_mode))
	gl.PolygonMode(gl.BACK, u32(pipeline.state.back_polygon_mode))

	if (pipeline.render_target != nil) {
		gl.BindFramebuffer(gl.FRAMEBUFFER, pipeline.render_target.handle)
		gl.Viewport(0, 0, pipeline.render_target.width, pipeline.render_target.height)
	}
}

pipeline_end :: proc(pipeline: ^Pipeline) {
	if (pipeline.render_target != nil) {
		gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
	}

	if (pipeline.old_state.blend) {
		gl.Enable(gl.BLEND)
	} else {
		gl.Disable(gl.BLEND)
	}

	if (pipeline.old_state.depth_test) {
		gl.Enable(gl.DEPTH_TEST)
	} else {
		gl.Disable(gl.DEPTH_TEST)
	}

	if (pipeline.old_state.cull_face) {
		gl.Enable(gl.CULL_FACE)
	} else {
		gl.Disable(gl.CULL_FACE)
	}

	gl.UseProgram(0)
	gl.BindVertexArray(0)
}


pipeline_set_uniform_mat4 :: proc(pipeline: ^Pipeline, name: string, value: [^]f32) {
	loc, ok := pipeline.uniform_locations[name]
	if (!ok) {
		loc = gl.GetUniformLocation(pipeline.program, strings.unsafe_string_to_cstring(name))
		if (loc == -1) {
			fmt.println("Could not find uniform variable", name)
			return
		}

		pipeline.uniform_locations[name] = loc
	}

	gl.ProgramUniformMatrix4fv(pipeline.program, loc, 1, gl.FALSE, value)
}

pipeline_set_uniform_vec4 :: proc(pipeline: ^Pipeline, name: string, value: [^]f32) {
	loc, ok := pipeline.uniform_locations[name]
	if (!ok) {
		loc = gl.GetUniformLocation(pipeline.program, strings.unsafe_string_to_cstring(name))
		if (loc == -1) {
			fmt.println("Could not find uniform variable", name)
			return
		}

		pipeline.uniform_locations[name] = loc
	}

	gl.ProgramUniform4fv(pipeline.program, loc, 1, value)
}

pipeline_set_uniform_vec3 :: proc(pipeline: ^Pipeline, name: string, value: [^]f32) {
	loc, ok := pipeline.uniform_locations[name]
	if (!ok) {
		loc = gl.GetUniformLocation(pipeline.program, strings.unsafe_string_to_cstring(name))
		if (loc == -1) {
			fmt.println("Could not find uniform variable", name)
			return
		}

		pipeline.uniform_locations[name] = loc
	}

	gl.ProgramUniform3fv(pipeline.program, loc, 1, value)
}

pipeline_set_uniform_int :: proc(pipeline: ^Pipeline, name: string, value: i32) {
	loc, ok := pipeline.uniform_locations[name]
	if (!ok) {
		loc = gl.GetUniformLocation(pipeline.program, strings.unsafe_string_to_cstring(name))
		if (loc == -1) {
			fmt.println("Could not find uniform variable", name)
			return
		}

		pipeline.uniform_locations[name] = loc
	}

	gl.ProgramUniform1i(pipeline.program, loc, value)
}

pipeline_blit_onto_default :: proc(pipeline: ^Pipeline, dstWidth: i32, dstHeight: i32) {
	gl.BindFramebuffer(gl.READ_FRAMEBUFFER, pipeline.render_target.handle)
	gl.BindFramebuffer(gl.DRAW_FRAMEBUFFER, 0)
	gl.ReadBuffer(gl.COLOR_ATTACHMENT0)

	gl.BlitFramebuffer(
		0,
		0,
		pipeline.render_target.width,
		pipeline.render_target.height,
		0,
		0,
		dstWidth,
		dstHeight,
		gl.COLOR_BUFFER_BIT,
		gl.NEAREST,
	)
}

pipeline_bind_texture2d :: proc(pipeline: ^Pipeline, name: string, unit: i32, texture: ^Texture2D) {
	gl.BindTextureUnit(u32(unit), texture.handle)
	pipeline_set_uniform_int(pipeline, name, unit)
}

FramebufferAttachmentType :: enum {
	Color,
	Depth,
	Stencil,
	DepthStencil,
}

PixelFormat :: enum {
	R32F             = gl.R32F,
	R32I             = gl.R32I,
	R32UI            = gl.R32UI,
	RG32F            = gl.RG32F,
	RG32I            = gl.RG32I,
	RG32UI           = gl.RG32UI,
	RGBA8I           = gl.RGBA8I,
	RGBA8UI          = gl.RGBA8UI,
	RGBA             = gl.RGBA,
	RGBA8            = gl.RGBA8,
	RGBA16F          = gl.RGBA16F,
	RGBA32F          = gl.RGBA32F,
	RGBA32I          = gl.RGBA32I,
	RGBA32UI         = gl.RGBA32UI,
	RGBA16I          = gl.RGBA16I,
	RGBA16UI         = gl.RGBA16UI,
	Depth16          = gl.DEPTH_COMPONENT16,
	Depth24          = gl.DEPTH_COMPONENT24,
	Depth32          = gl.DEPTH_COMPONENT32,
	Depth32F         = gl.DEPTH_COMPONENT32F,
	Stencil1         = gl.STENCIL_INDEX1,
	Stencil4         = gl.STENCIL_INDEX4,
	Stencil8         = gl.STENCIL_INDEX8,
	Stencil16        = gl.STENCIL_INDEX16,
	Depth24Stencil8  = gl.DEPTH24_STENCIL8,
	Depth32FStencil8 = gl.DEPTH32F_STENCIL8,
}

FramebufferAttachment :: struct {
	type:   FramebufferAttachmentType,
	format: PixelFormat,
	handle: u32,
	width:  i32,
	height: i32,
}

Framebuffer :: struct {
	handle:      u32,
	width:       i32,
	height:      i32,
	attachments: []FramebufferAttachment,
}

FramebufferDescription :: struct {
	width:       i32,
	height:      i32,
	attachments: []FramebufferAttachment,
}

create_framebuffer_attachment :: proc(attachment: ^FramebufferAttachment, width, height: i32) {
	attachment.width = width
	attachment.height = height

	gl.CreateTextures(gl.TEXTURE_2D, 1, &attachment.handle)
	gl.TextureStorage2D(
		attachment.handle,
		1,
		u32(attachment.format),
		attachment.width,
		attachment.height,
	)
}

create_framebuffer :: proc(desc: FramebufferDescription) -> (framebuffer: ^Framebuffer) {
	framebuffer = new(Framebuffer)

	framebuffer.width = desc.width
	framebuffer.height = desc.height
	framebuffer.attachments = desc.attachments

	gl.CreateFramebuffers(1, &framebuffer.handle)

	color_attachments := 0

	for &attachment in framebuffer.attachments {

		create_framebuffer_attachment(&attachment, framebuffer.width, framebuffer.height)

		type := u32(0)
		switch attachment.type {
		case .Depth:
			type = gl.DEPTH_ATTACHMENT
		case .Stencil:
			type = gl.STENCIL_ATTACHMENT
		case .DepthStencil:
			type = gl.DEPTH_STENCIL_ATTACHMENT
		case .Color:
			type = gl.COLOR_ATTACHMENT0 + u32(color_attachments)
			gl.NamedFramebufferDrawBuffer(framebuffer.handle, type)
			color_attachments += 1
		}

		gl.NamedFramebufferTexture(framebuffer.handle, type, attachment.handle, 0)
	}

	if gl.CheckNamedFramebufferStatus(framebuffer.handle, gl.FRAMEBUFFER) !=
	   gl.FRAMEBUFFER_COMPLETE {
		fmt.println("Failed to create framebuffer")
	}

	return
}

framebuffer_destroy :: proc(framebuffer: ^Framebuffer) {
	gl.DeleteFramebuffers(1, &framebuffer.handle)

	for &attachment in framebuffer.attachments {
		gl.DeleteTextures(1, &attachment.handle)
	}

	free(framebuffer)
}

framebuffer_clear_attachments :: proc(
	framebuffer: ^Framebuffer,
	color: [^]f32,
	depth: f32,
	stencil: i32,
) {
	color_attachments := 0

	for attachment in framebuffer.attachments {
		switch attachment.type {
		case .Depth:
			clear_value := f32(depth)
			gl.ClearNamedFramebufferfv(framebuffer.handle, gl.DEPTH, 0, &clear_value)
		case .Stencil:
			clear_value := u32(stencil)
			gl.ClearNamedFramebufferuiv(framebuffer.handle, gl.STENCIL, 0, &clear_value)
		case .DepthStencil:
			gl.ClearNamedFramebufferfi(framebuffer.handle, gl.DEPTH_STENCIL, 0, depth, stencil)
		case .Color:
			gl.ClearNamedFramebufferfv(framebuffer.handle, gl.COLOR, i32(color_attachments), color)
			color_attachments += 1
		}
	}
}

pipeline_resize :: proc(pipeline: ^Pipeline, width, height: i32) {
	if (pipeline.render_target != nil) {
		framebuffer_destroy(pipeline.render_target)
		pipeline.render_target = create_framebuffer(
			FramebufferDescription {
				width = width,
				height = height,
				attachments = pipeline.render_target.attachments,
			},
		)
	}
}

Texture2D :: struct {
	handle: u32,
	width:  i32,
	height: i32,
	format: PixelFormat,
}

create_texture_2d :: proc(
	width, height: i32,
	format: PixelFormat,
	storage_format: PixelFormat,
	data: [^]u8,
) -> (
	texture: ^Texture2D,
) {
	texture = new(Texture2D)
	texture.width = width
	texture.height = height
	texture.format = format

	gl.CreateTextures(gl.TEXTURE_2D, 1, &texture.handle)
	gl.TextureStorage2D(texture.handle, 1, u32(storage_format), width, height)

	if data != nil {
		gl.TextureSubImage2D(
			texture.handle,
			0,
			0,
			0,
			width,
			height,
			u32(format),
			gl.UNSIGNED_BYTE,
			data,
		)
	}
	return
}

VertexArrayObject :: struct {
	handle: u32,
}

create_vertex_array_object :: proc() -> (vao: ^VertexArrayObject) {
	vao = new(VertexArrayObject)
	gl.CreateVertexArrays(1, &vao.handle)
	return
}
