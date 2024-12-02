package tinigen

import glm "core:math/linalg/glsl"

import "core:c"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "vendor:cgltf"
import "vendor:stb/image"

Vertex :: struct {
	position: glm.vec3,
	normal:   glm.vec3,
	tangent:  glm.vec4,
	texcoord: glm.vec2,
}

Transform :: struct {
	position: glm.vec3,
	rotation: glm.quat,
	scale:    glm.vec3,
}

Mesh :: struct {
	vertices: [dynamic]Vertex,
	indices:  [dynamic]u32,
	meterial: Material,
	transform: Transform
}

Material :: struct {
	diffuse_texture:            ^Texture2D,
	normal_texture:             ^Texture2D,
	metallic_roughness_texture: ^Texture2D,
}

Scene :: struct {
	materials: [dynamic]Material,
	meshes:     [dynamic]Mesh,
}

load_gltf :: proc(gltf_filepath: string) -> (scene : Scene, ok: bool) {

	gltf_filepath_cstring := strings.clone_to_cstring(gltf_filepath)

	options := cgltf.options{}
	out, result := cgltf.parse_file(options, gltf_filepath_cstring)

	if result != cgltf.result.success {
		ok = false
		return
	}

	result = cgltf.load_buffers(options, out, gltf_filepath_cstring)
	if result != cgltf.result.success {
		ok = false
		return
	}

	relative_path := filepath.dir(gltf_filepath)

	for node_index in 0 ..< len(out.nodes) {
		node := out.nodes[node_index]
		if node.mesh != nil {
			fmt.printfln("Loading Mesh %s", node.name)
			mesh := node.mesh
			m := Mesh{}

			positions: [^]glm.vec3 = nil
			uvs: [^]glm.vec2 = nil
			normals: [^]glm.vec3 = nil
			tangents: [^]glm.vec4 = nil
			
			rotation := glm.quatAxisAngle(glm.vec3{node.rotation[0], node.rotation[1], node.rotation[2]}, node.rotation[3])
			scale := glm.vec3{node.scale[0], node.scale[1], node.scale[2]}
			position := glm.vec3{node.translation[0], node.translation[1], node.translation[2]}

			m.transform = Transform{position, rotation, scale}

			count := 0

			for primitive_index in 0 ..< len(mesh.primitives) {
				primitive := mesh.primitives[primitive_index]
	
				m.meterial = load_material(primitive.material, relative_path) or_return
	
				if primitive.type == .triangles {
					{
						accessor := primitive.indices
						reserve(&m.indices, accessor.count)
	
						if accessor.component_type == .r_16u {
							model_indices := transmute([^]u16)get_accessor_data(accessor)
							for x in 0 ..< accessor.count {
								append(&m.indices, u32(model_indices[x]))
							}
						} else if accessor.component_type == .r_32u {
							model_indices := transmute([^]u32)get_accessor_data(accessor)
							for x in 0 ..< accessor.count {
								append(&m.indices, model_indices[x])
							}
	
							fmt.printfln("Using u32 indices")
						}
	
					}
	
					for attribute in primitive.attributes {
						accessor := attribute.data
						if attribute.type == .normal && accessor.type == .vec3 {
							normals = transmute([^]glm.vec3)get_accessor_data(accessor)
						} else if attribute.type == .texcoord && accessor.type == .vec2 {
							uvs = transmute([^]glm.vec2)get_accessor_data(accessor)
						} else if attribute.type == .position && accessor.type == .vec3 {
							positions = transmute([^]glm.vec3)get_accessor_data(accessor)
							count = int(accessor.count)
						} else if attribute.type == .tangent && accessor.type == .vec4 {
							tangents = transmute([^]glm.vec4)get_accessor_data(accessor)
						}
					}
				} else {
					fmt.printfln("Unsupported primitive type: %v", primitive.type)
				}
	
				// right now we only support one primitive per mesh
				break
			}
	
			if positions == nil {
				fmt.printfln("No position attribute found")
				ok = false
				return
			}
	
			free_normals := (normals == nil)
	
			if normals == nil {
				fmt.printfln("No normal attribute found")
	
				normals_buffer, _ := mem.alloc(size_of(glm.vec3) * count)
				normals = transmute([^]glm.vec3)normals_buffer
				return
			}
	
			free_tangents := (tangents == nil)
	
			if tangents == nil {
				fmt.printfln("No tangent attribute found")
				tangents_buffer, _ := mem.alloc(size_of(glm.vec4) * count)
				tangents = transmute([^]glm.vec4)tangents_buffer
			}

			free_uvs := (uvs == nil)
	
			if uvs == nil {
				fmt.printfln("No texcoord attribute found")
				uvs_buffer, _ := mem.alloc(size_of(glm.vec2) * count)
				uvs = transmute([^]glm.vec2)uvs_buffer
			}
	
			reserve(&m.vertices, count)
			for i in 0 ..< count {
				append(&m.vertices, Vertex{positions[i], normals[i], tangents[i], uvs[i]})
			}
	
			if free_uvs {
				free(uvs)
			}
	
			if free_normals {
				free(normals)
			}
	
			append(&scene.meshes, m)
		}
	}
	

	cgltf.free(out)

	ok = true
	return
}

load_pixel_from_memory :: proc(
	data: [^]byte,
	size: i32,
	desired_channels: i32,
) -> (
	pixels: [^]byte,
	w, h, channels: i32,
	ok: bool,
) {

	width: c.int = 0
	height: c.int = 0
	_desired_channels: c.int = desired_channels
	pixels = image.load_from_memory(data, size, &width, &height, nil, _desired_channels)

	if pixels == nil {
		ok = false
		return
	}

	w = width
	h = height
	channels = desired_channels
	ok = true
	return
}


load_pixel_from_file :: proc(
	filepath: string,
	desired_channels: i32,
) -> (
	pixels: [^]byte,
	w, h, channels: i32,
	ok: bool,
) {
	file_data, err := os.read_entire_file(filepath)
	if file_data == nil {
		ok = false
		return
	}

	defer delete(file_data)

	width: c.int = 0
	height: c.int = 0
	_desired_channels: c.int = desired_channels
	pixels = image.load_from_memory(
		raw_data(file_data),
		i32(len(file_data)),
		&width,
		&height,
		nil,
		_desired_channels,
	)

	if pixels == nil {
		ok = false
		return
	}

	w = width
	h = height
	channels = desired_channels
	ok = true
	return
}


load_texture :: proc(
	gltf_texture: ^cgltf.texture,
	relative_path: string,
) -> (
	texture: ^Texture2D,
	ok: bool,
) {
	if gltf_texture.image_ != nil {
		pixels: [^]byte = nil
		width: i32 = 0
		height: i32 = 0
		channels: i32 = 0
		if gltf_texture.image_.uri != nil {
			path := filepath.join({relative_path, string(gltf_texture.image_.uri)})
			pixels, width, height, channels = load_pixel_from_file(path, 4) or_return
		} else if gltf_texture.image_.buffer_view != nil {
			buffer := gltf_texture.image_.buffer_view.buffer
			offset := gltf_texture.image_.buffer_view.offset

			if buffer != nil {
				data := u64(uintptr(buffer.data)) + u64(offset)
				data_ptr := transmute([^]byte)(data)
				pixels, width, height, channels = load_pixel_from_memory(
					data_ptr,
					i32(gltf_texture.image_.buffer_view.size),
					4,
				) or_return
			}
		}

		if pixels != nil {
			texture = create_texture_2d(width, height, .RGBA, .RGBA8, pixels)
			image.image_free(pixels)
		} else {
			ok = false
			return
		}

		
	}

	ok = true
	return
}

load_material :: proc(
	gltf_material: ^cgltf.material,
	relative_path: string,
) -> (
	material: Material,
	ok: bool,
) {

	{
		normal_texture := gltf_material.normal_texture.texture
		if normal_texture != nil {
			material.normal_texture = load_texture(normal_texture, relative_path) or_return
			fmt.printfln(
				"Loaded Normal Map %d x %d",
				material.normal_texture.width,
				material.normal_texture.height,
			)
		}
	}

	if (gltf_material.has_pbr_metallic_roughness) {
		pbr := gltf_material.pbr_metallic_roughness

		{
			base_color_texture := pbr.base_color_texture.texture
			if base_color_texture != nil {
				material.diffuse_texture = load_texture(
					base_color_texture,
					relative_path,
				) or_return
				fmt.printfln(
					"Loaded Base Color Map %d x %d",
					material.diffuse_texture.width,
					material.diffuse_texture.height,
				)
			}
		}

		{
			metallic_roughness_texture := pbr.metallic_roughness_texture.texture
			if metallic_roughness_texture != nil {
				material.metallic_roughness_texture = load_texture(
					metallic_roughness_texture,
					relative_path,
				) or_return
				fmt.printfln(
					"Loaded Metallic Roughness Map %d x %d",
					material.metallic_roughness_texture.width,
					material.metallic_roughness_texture.height,
				)
			}
		}
	}

	ok = true
	return
}

get_accessor_data :: proc(accessor: ^cgltf.accessor) -> rawptr {
	buffer := accessor.buffer_view.buffer
	offset := accessor.offset + accessor.buffer_view.offset
	data := u64(uintptr(buffer.data)) + u64(offset)
	return rawptr(uintptr(data))
}

GpuMesh :: struct {
	vbo: GpuBuffer,
	ebo: GpuBuffer,
}

upload_mesh_to_gpu_single :: proc(mesh: Mesh) -> (out: GpuMesh, ok: bool) {

	model_vbo := create_buffer(
		u32(len(mesh.vertices)),
		size_of(Vertex),
		raw_data(mesh.vertices),
		.Static,
	)
	model_ebo := create_buffer(
		u32(len(mesh.indices)),
		size_of(u32),
		raw_data(mesh.indices),
		.Static,
	)

	out = GpuMesh{model_vbo, model_ebo}

	ok = true
	return
}

upload_mesh_to_gpu_list :: proc(meshes: []Mesh) -> (out: [dynamic]GpuMesh, ok: bool) {
	reserve(&out, len(meshes))
	for mesh in meshes {
		mesh_gpu := upload_mesh_to_gpu_single(mesh) or_return
		append(&out, mesh_gpu)
	}
	ok = true
	return
}

upload_mesh_to_gpu :: proc {
	upload_mesh_to_gpu_list,
	upload_mesh_to_gpu_single,
}

load_cubemap_pixels_from_file :: proc(cube_filepath: [6]string) -> (data: [][^]byte, width, height: i32, ok: bool) {
	data = make([][^]byte, 6)

	for i := 0; i < 6; i+=1 {
		pixels, w, h, channels := load_pixel_from_file(cube_filepath[i], 4) or_return

		if w != h {
			fmt.printfln("Cubemap texture %d has different width and height", i)
			ok = false
			return
		}

		width = w
		height = h

		if pixels == nil {
			ok = false
			return
		}

		data[i] = pixels
	}

	ok = true
	return
}

free_cubemap_pixels :: proc(data: [][^]byte) {
	for i := 0; i < 6; i+=1 {
		image.image_free(data[i])
	}
}
