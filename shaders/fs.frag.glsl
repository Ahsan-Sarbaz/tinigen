#version 460

out vec4 FragColor;

in vec3 Normal;
in vec2 TexCoords;

uniform sampler2D uDiffuseTexture;
uniform sampler2D uNormalTexture;
uniform sampler2D uMetallicRoughnessTexture;


void main() {
    vec3 diffuse = texture(uDiffuseTexture, TexCoords).rgb;
    vec3 normal = texture(uNormalTexture, TexCoords).rgb;

    vec4 metallicRoughness = texture(uMetallicRoughnessTexture, TexCoords);

    float metallic = metallicRoughness.r;
    float roughness = metallicRoughness.g;
    float ao = metallicRoughness.a;
    

    vec4 color = vec4((normal + diffuse) * ao, 1.0f);

    // gamma correction
    color.rgb = pow(color.rgb, vec3(1.0f / 2.2f));
    FragColor = color;
}
