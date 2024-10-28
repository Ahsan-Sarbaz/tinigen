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

