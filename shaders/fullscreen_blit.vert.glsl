#version 460

out vec2 TexCoords;

void main() {

    vec4 quad_postions[6] = {
        vec4(-1.0f,  1.0f, 0.0f, 1.0f),
        vec4( 1.0f,  1.0f, 0.0f, 1.0f),
        vec4(-1.0f, -1.0f, 0.0f, 1.0f),
        vec4(-1.0f, -1.0f, 0.0f, 1.0f),
        vec4( 1.0f,  1.0f, 0.0f, 1.0f),
        vec4( 1.0f, -1.0f, 0.0f, 1.0f)
    };

    vec2 quad_tex_coords[6] = {
        vec2(0.0f, 1.0f),
        vec2(1.0f, 1.0f),
        vec2(0.0f, 0.0f),
        vec2(0.0f, 0.0f),
        vec2(1.0f, 1.0f),
        vec2(1.0f, 0.0f)
    };

    gl_Position = quad_postions[gl_VertexID];
    TexCoords = quad_tex_coords[gl_VertexID];
}