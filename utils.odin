package tinigen

import glm "core:math/linalg/glsl"

import "core:os"
import "core:fmt"
import "core:mem"
import "core:strconv"
import "core:strings"
import	"vendor:cgltf"

Vertex :: struct {
	position: glm.vec3,
	normal:   glm.vec3,
	texcoord: glm.vec2,
}

load_model :: proc(
	filepath: string,
) -> (
	vertices: [dynamic]Vertex,
	indices: [dynamic]u32,
	ok: bool,
) {

	if strings.ends_with(filepath, ".obj") {
		return load_obj(filepath)
	} else if strings.ends_with(filepath, ".gltf") {
		return load_gltf(filepath)
	}
	
	ok = false
	return
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

			if len(parts) == 4 {
				x := strconv.parse_f32(parts[1]) or_return
				y := strconv.parse_f32(parts[2]) or_return
				z := strconv.parse_f32(parts[3]) or_return
				append(&positions, glm.vec3{x, y, z})
			} else {
				pos := [3]f32{}
				j := 0
				for i in 1..<len(parts) {
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
				for i in 1..<len(parts) {
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
				for i in 1..<len(parts) {
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
								case 3: part_index = 1
								case 4: part_index = 3
								case 5: part_index = 4
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

					append(&vertices, Vertex{position, normal, texcoord})
					append(&indices, index)
					index += 1
				}
				
			}
		}
	}

	delete(positions)
	delete(uvs)
	delete(normals)

	ok = true
	return
}

load_gltf :: proc (filepath :string) -> (vertices: [dynamic]Vertex, indices: [dynamic]u32, ok: bool) {

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

	scene := out.scenes[0]
	nodes := scene.nodes

	count := 0
	positions : [^]glm.vec3 = nil
	uvs : [^]glm.vec2 = nil
	normals :[^]glm.vec3 = nil

	for i in 0..<len(nodes) {
		node := nodes[i]

		for j in 0..<len(node.children) {
			child := node.children[j]
			mesh := child.mesh
			if mesh == nil {
				continue
			}
						
			for primitive in mesh.primitives {
				if primitive.type == .triangles {
					model_indices := transmute([^]u16) primitive.indices.buffer_view.buffer.data
					model_indices = mem.ptr_offset(model_indices, primitive.indices.buffer_view.offset / size_of(u16))

					reserve(&indices, primitive.indices.count)
					for x in 0..<primitive.indices.count {
						index := model_indices[x]
						append(&indices, u32(index))
					}

					for attribute in primitive.attributes {
						accessor := attribute.data
						view := accessor.buffer_view
						buffer := view.buffer
						
						if attribute.type == .normal {
							data := transmute([^]glm.vec3) buffer.data
							normals = mem.ptr_offset(data, accessor.offset/ size_of(glm.vec3))
						} else if attribute.type == .texcoord {
							data := transmute([^]glm.vec2) buffer.data
							uvs = mem.ptr_offset(data, accessor.offset/ size_of(glm.vec2))
						} else if attribute.type == .position {
							data := transmute([^]glm.vec3) buffer.data
							positions = mem.ptr_offset(data, accessor.offset / size_of(glm.vec3))
							count = int(accessor.count)
						}
					}
				}
			}
		}
	}

	reserve(&vertices, count)
	for i in 0..<count {
		append(&vertices, Vertex{positions[i], normals[i], uvs[i]})
	}

	cgltf.free(out)

	ok = true
	return
}

