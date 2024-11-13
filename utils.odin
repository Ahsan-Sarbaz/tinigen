package tinigen

import glm "core:math/linalg/glsl"

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"
import "vendor:cgltf"

Vertex :: struct {
	position: glm.vec3,
	normal:   glm.vec3,
	texcoord: glm.vec2,
}

Mesh :: struct {
	vertices: [dynamic]Vertex,
	indices:  [dynamic]u32,
}

load_model :: proc(filepath: string) -> (meshes: [dynamic]Mesh, ok: bool) {

	if strings.ends_with(filepath, ".obj") {
		return load_obj(filepath)
	} else if strings.ends_with(filepath, ".gltf") {
		return load_gltf(filepath)
	}

	ok = false
	return
}

load_obj :: proc(filepath: string) -> (meshes: [dynamic]Mesh, ok: bool) {
	data := os.read_entire_file(filepath, context.allocator) or_return
	defer delete(data, context.allocator)

	it := string(data)

	positions := [dynamic]glm.vec3{}
	uvs := [dynamic]glm.vec2{}
	normals := [dynamic]glm.vec3{}

	mesh := Mesh{}

	index: u32 = 0

	for line in strings.split_lines_iterator(&it) {

		if strings.starts_with(line, "v ") {
			parts := strings.split(line, " ")

			if len(parts) == 4 {
				x := strconv.parse_f32(parts[1]) or_return
				y := strconv.parse_f32(parts[2]) or_return
				z := strconv.parse_f32(parts[3]) or_return
				append(&positions, glm.vec3{x, y, z})
			} else {
				pos := [3]f32{}
				j := 0
				for i in 1 ..< len(parts) {
					part := parts[i]
					if part == "" {
						continue
					}
					pos[j] = strconv.parse_f32(part) or_return
					j += 1
				}
				append(&positions, glm.vec3{pos[0], pos[1], pos[2]})
			}

		} else if strings.starts_with(line, "vt ") {
			parts := strings.split(line, " ")

			if len(parts) == 3 {
				u := strconv.parse_f32(parts[1]) or_return
				v := strconv.parse_f32(parts[2]) or_return
				append(&uvs, glm.vec2{u, v})
			} else {
				// some exporters use vt 0.0 0.0 0.0
				uv := [3]f32{}
				j := 0
				for i in 1 ..< len(parts) {
					part := parts[i]
					if part == "" {
						continue
					}
					uv[j] = strconv.parse_f32(part) or_return
					j += 1
				}
				append(&uvs, glm.vec2{uv[0], uv[1]})
			}

		} else if strings.starts_with(line, "vn ") {
			parts := strings.split(line, " ")

			if len(parts) == 4 {
				nx := strconv.parse_f32(parts[1]) or_return
				ny := strconv.parse_f32(parts[2]) or_return
				nz := strconv.parse_f32(parts[3]) or_return
				append(&normals, glm.vec3{nx, ny, nz})
			} else {
				norm := [3]f32{}
				j := 0
				for i in 1 ..< len(parts) {
					part := parts[i]
					if part == "" {
						continue
					}
					norm[j] = strconv.parse_f32(part) or_return
					j += 1
				}
				append(&normals, glm.vec3{norm[0], norm[1], norm[2]})
			}


		} else if strings.starts_with(line, "f ") {
			parts := strings.split(line, " ")
			vertex_count := len(parts) - 1

			if vertex_count == 3 || vertex_count == 4 {
				vertices_to_process := vertex_count
				if vertex_count == 4 {
					vertices_to_process = 6
				}

				for i := 0; i < vertices_to_process; i += 1 {
					part_index := 1
					if vertex_count == 4 {
						if i >= 3 {
							switch i {
							case 3:
								part_index = 1
							case 4:
								part_index = 3
							case 5:
								part_index = 4
							}
						} else {
							part_index = i + 1
						}
					} else {
						part_index = i + 1
					}

					v_t_n := strings.split(parts[part_index], "/")

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

					append(&mesh.vertices, Vertex{position, normal, texcoord})
					append(&mesh.indices, index)
					index += 1
				}

			}
		}
	}

	delete(positions)
	delete(uvs)
	delete(normals)

	append(&meshes, mesh)

	ok = true
	return
}

load_gltf :: proc(filepath: string) -> (meshes: [dynamic]Mesh, ok: bool) {

	filepath_cstring := strings.clone_to_cstring(filepath)

	options := cgltf.options{}
	out, result := cgltf.parse_file(options, filepath_cstring)

	if result != cgltf.result.success {
		ok = false
		return
	}

	result = cgltf.load_buffers(options, out, filepath_cstring)
	if result != cgltf.result.success {
		ok = false
		return
	}

	for mesh in out.meshes {
		count := 0
		positions: [^]glm.vec3 = nil
		uvs: [^]glm.vec2 = nil
		normals: [^]glm.vec3 = nil

		m := Mesh{}

		for primitive in mesh.primitives {
			if primitive.type == .triangles {
				{
					accessor := primitive.indices
					reserve(&m.indices, accessor.count)

					if accessor.component_type == .r_16u {
						model_indices := transmute([^]u16) get_accessor_data(accessor)
						for x in 0 ..< accessor.count {
							append(&m.indices, u32(model_indices[x]))
						}
					} else if accessor.component_type == .r_32u {
						model_indices := transmute([^]u32) get_accessor_data(accessor)
						for x in 0 ..< accessor.count {
							append(&m.indices, model_indices[x])
						}

						fmt.printfln("Using u32 indices")
					}

				}

				for attribute in primitive.attributes {
					accessor := attribute.data
					if attribute.type == .normal && accessor.type == .vec3 {
						normals = transmute([^]glm.vec3) get_accessor_data(accessor)
					} else if attribute.type == .texcoord && accessor.type == .vec2 {
						uvs = transmute([^]glm.vec2) get_accessor_data(accessor)
					} else if attribute.type == .position && accessor.type == .vec3 {
						positions = transmute([^]glm.vec3) get_accessor_data(accessor)
						count = int(accessor.count)
					}
				}
			} else {
				fmt.printfln("Unsupported primitive type: %v", primitive.type)
			}
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

		free_uvs := (uvs == nil)

		if uvs == nil {
			fmt.printfln("No texcoord attribute found")
			uvs_buffer, _ := mem.alloc(size_of(glm.vec2) * count)
			uvs = transmute([^]glm.vec2)uvs_buffer
		}

		reserve(&m.vertices, count)
		for i in 0 ..< count {
			append(&m.vertices, Vertex{positions[i], normals[i], uvs[i]})
		}

		if free_uvs {
			free(uvs)
		}

		if free_normals {
			free(normals)
		}

		append(&meshes, m)
	}


	cgltf.free(out)

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
