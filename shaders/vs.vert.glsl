#version 460
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