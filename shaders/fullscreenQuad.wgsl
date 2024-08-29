struct LightPillar {
    key: f32,
    depth: f32,
    length: f32,
    density: f32,
    color: vec3<f32>,
};

struct LightPillarBuffer {
    segments: array<LightPillar>,
};

struct Uniforms {
    screenWidth: f32,
    screenHeight: f32,
};

@group(0) @binding(0) var<uniform> uniforms : Uniforms;
@group(0) @binding(1) var<storage, read> finalColorBuffer : LightPillarBuffer;

struct VertexOutput {
    @builtin(position) Position: vec4<f32>,
};

@vertex 
fn vert_main(@builtin(vertex_index) VertexIndex: u32) -> VertexOutput {
    let pos = array<vec2<f32>, 6>(
        vec2<f32>(1.0, 1.0),
        vec2<f32>(1.0, -1.0),
        vec2<f32>(-1.0, -1.0),
        vec2<f32>(1.0, 1.0),
        vec2<f32>(-1.0, -1.0),
        vec2<f32>(-1.0, 1.0)
    );
    var output: VertexOutput;
    output.Position = vec4<f32>(pos[VertexIndex], 0.0, 1.0);
    return output;
}

@fragment 
fn frag_main(@builtin(position) coord: vec4<f32>) -> @location(0) vec4<f32> {
    let X = floor(coord.x);
    let Y = floor(coord.y);
    let index = u32(X + Y * uniforms.screenWidth);
    let tmp = finalColorBuffer.segments[index];
    //let finalColor = vec4<f32>((1 - exp(-tmp.density * tmp.length)) * tmp.color, 1.0);
    let finalColor = vec4f(tmp.color, 1.0);
    return finalColor;
}