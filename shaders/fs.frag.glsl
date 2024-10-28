#version 460

out vec4 FragColor;

in vec3 Normal;
in vec2 TexCoords;

void main() {
    FragColor = vec4(Normal, 1.0f);
}
