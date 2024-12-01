#version 460

out vec4 FragColor;

in mat3 TBN;
in vec2 TexCoords;
in vec3 FragPos;

uniform sampler2D uAlbedoTexture;         // Albedo (diffuse) map
uniform sampler2D uNormalTexture;         // Normal map
uniform sampler2D uMetallicRoughnessTexture; // Metallic in R, Roughness in G
uniform vec3 uCameraPos;                 // Camera (view) position in world space

const float PI = 3.14159265359;


// Functions for PBR calculations
float DistributionGGX(vec3 N, vec3 H, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;

    float num = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return num / denom;
}

float GeometrySchlickGGX(float NdotV, float roughness) {
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;

    float num = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return num / denom;
}

float GeometrySmith(vec3 N, vec3 V, vec3 L, float roughness) {
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);

    float ggx2 = GeometrySchlickGGX(NdotV, roughness);
    float ggx1 = GeometrySchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}

vec3 FresnelSchlick(float cosTheta, vec3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

void main() {
    vec3 albedo = pow(texture(uAlbedoTexture, TexCoords).rgb, vec3(2.2));
    vec3 normalMap = texture(uNormalTexture, TexCoords).rgb * 2.0 - 1.0;
    vec4 metallicRoughness = texture(uMetallicRoughnessTexture, TexCoords);

    float metallic = metallicRoughness.r;
    float roughness = metallicRoughness.g;
    float ao = metallicRoughness.b;

    vec3 camPos = TBN * uCameraPos;
    vec3 uLightPos = vec3(3.0, 3.0, 0.0);
    vec3 uLightColor = vec3(2.0, 2.0, 2.0);

    vec3 N = normalize(TBN * normalMap);
    vec3 V = normalize(camPos - FragPos);

    vec3 F0 = vec3(0.04); 
    F0 = mix(F0, albedo, metallic);
	           
    // reflectance equation
    vec3 Lo = vec3(0.0);
    // calculate per-light radiance
    vec3 L = normalize(uLightPos - FragPos);
    vec3 H = normalize(V + L);
    float distance    = length(uLightPos - FragPos);
    float attenuation = 1.0 / (distance * distance);
    vec3 radiance     = uLightColor * attenuation;        
    
    // cook-torrance brdf
    float NDF = DistributionGGX(N, H, roughness);        
    float G   = GeometrySmith(N, V, L, roughness);      
    vec3 F    = FresnelSchlick(max(dot(H, V), 0.0), F0);       
    
    vec3 kS = F;
    vec3 kD = vec3(1.0) - kS;
    kD *= 1.0 - metallic;
    
    vec3 numerator    = NDF * G * F;
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
    vec3 specular     = numerator / denominator;  
        
    // add to outgoing radiance Lo
    float NdotL = max(dot(N, L), 0.0);                
    Lo += (kD * albedo / PI + specular) * radiance * NdotL; 
  
    vec3 ambient = vec3(0.03) * albedo * ao;
    vec3 color = ambient + Lo;
	
    color = color / (color + vec3(1.0));
    color = pow(color, vec3(1.0/2.2));  
   
    FragColor = vec4(color, 1.0);
}
