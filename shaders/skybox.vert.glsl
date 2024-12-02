#version 460

layout (std140) uniform UniformBlock {
    mat4 uVP;
    mat4 uProjection;
    mat4 uView;
    vec3 uCameraPos;
};

out vec3 TexCoords;

vec3 cube_positions[36] = vec3[](
    // Front face
    vec3(-1.0, -1.0,  1.0), vec3( 1.0, -1.0,  1.0), vec3( 1.0,  1.0,  1.0),
    vec3(-1.0, -1.0,  1.0), vec3( 1.0,  1.0,  1.0), vec3(-1.0,  1.0,  1.0),

    // Back face
    vec3(-1.0, -1.0, -1.0), vec3(-1.0,  1.0, -1.0), vec3( 1.0,  1.0, -1.0),
    vec3(-1.0, -1.0, -1.0), vec3( 1.0,  1.0, -1.0), vec3( 1.0, -1.0, -1.0),

    // Left face
    vec3(-1.0, -1.0, -1.0), vec3(-1.0, -1.0,  1.0), vec3(-1.0,  1.0,  1.0),
    vec3(-1.0, -1.0, -1.0), vec3(-1.0,  1.0,  1.0), vec3(-1.0,  1.0, -1.0),

    // Right face
    vec3( 1.0, -1.0, -1.0), vec3( 1.0,  1.0, -1.0), vec3( 1.0,  1.0,  1.0),
    vec3( 1.0, -1.0, -1.0), vec3( 1.0,  1.0,  1.0), vec3( 1.0, -1.0,  1.0),

    // Top face
    vec3(-1.0,  1.0, -1.0), vec3(-1.0,  1.0,  1.0), vec3( 1.0,  1.0,  1.0),
    vec3(-1.0,  1.0, -1.0), vec3( 1.0,  1.0,  1.0), vec3( 1.0,  1.0, -1.0),

    // Bottom face
    vec3(-1.0, -1.0, -1.0), vec3( 1.0, -1.0, -1.0), vec3( 1.0, -1.0,  1.0),
    vec3(-1.0, -1.0, -1.0), vec3( 1.0, -1.0,  1.0), vec3(-1.0, -1.0,  1.0)
);


void main() {
    vec3 pos = cube_positions[gl_VertexID];
    TexCoords = pos;

    vec4 position = uProjection * mat4(mat3(uView)) * vec4(pos, 1.0);
    gl_Position = position.xyww;
}