package tinigen

import glm "core:math/linalg/glsl"

import "core:os"
import "core:strconv"
import "core:strings"

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