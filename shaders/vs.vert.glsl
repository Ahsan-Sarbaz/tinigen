#version 460
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec3 aNormal;
layout (location = 2) in vec4 aTangent;
layout (location = 3) in vec2 aTexCoords;

layout (std140) uniform UniformBlock {
    mat4 uVP;
    mat4 uProjection;
    mat4 uView;
    vec3 uCameraPos;
};

uniform mat4 uModel;

out vec3 FragPos;
out vec2 TexCoords;
out mat3 TBN;

void main() {
    gl_Position = uVP * uModel * vec4(aPos * 10, 1.0);
    
    vec3 T = normalize(uModel * aTangent).xyz;
    vec3 N = normalize(mat3(uModel) * aNormal);
    T = normalize(T - dot(T, N) * N);
    vec3 B = cross(N, T);

    TBN = mat3(T, B, N);

    FragPos = vec3(uModel * vec4(aPos * 10, 1.0));
    FragPos = TBN * FragPos;

    TexCoords = aTexCoords;
}