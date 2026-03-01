#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

struct Uniforms {
    float4x4 mvpMatrix;
    float4   color;
};

vertex VertexOut vertexMain(VertexIn in [[stage_in]],
                            constant Uniforms &u [[buffer(1)]]) {
    VertexOut out;
    out.position = u.mvpMatrix * float4(in.position, 1.0);
    out.color    = u.color;
    return out;
}

fragment float4 fragmentMain(VertexOut in [[stage_in]]) {
    return in.color;
}
