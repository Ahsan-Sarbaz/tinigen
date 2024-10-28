#version 460 core

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(binding = 0, rgba32f) uniform image2D inputImage;
layout(binding = 1, rgba32f) uniform image2D outputImage;

void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    ivec2 texSize = imageSize(inputImage);

    vec3 kernelX[3] = {
        vec3(-1,  0,  1),
        vec3(-2,  0,  2),
        vec3(-1,  0,  1)
    };
    
    vec3 kernelY[3] = {
        vec3(-1, -2, -1),
        vec3( 0,  0,  0),
        vec3( 1,  2,  1)
    };

    vec3 sumX = vec3(0.0);
    vec3 sumY = vec3(0.0);

    for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
            ivec2 neighborPos = pos + ivec2(i, j);
            neighborPos = clamp(neighborPos, ivec2(0), texSize - ivec2(1));
            
            vec3 color = imageLoad(inputImage, neighborPos).rgb;
            sumX += color * kernelX[i + 1][j + 1];
            sumY += color * kernelY[i + 1][j + 1];
        }
    }

    float edgeMagnitude = length(sumX) + length(sumY);

    vec4 edgeColor = vec4(vec3(edgeMagnitude), 1.0);
    imageStore(outputImage, pos, edgeColor);
}
