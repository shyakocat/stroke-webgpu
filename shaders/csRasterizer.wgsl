struct ColorBuffer {
    pixels: array<atomic<u32>>,
};

struct UBO {
    screenWidth: f32,
    screenHeight: f32,
    modelViewProjectionMatrix: mat4x4<f32>,
};

struct StrokeBuffer {
    triangles: array<vec3<f32>>,
};

@group(0) @binding(0) var<storage, read_write> outputBuffer : ColorBuffer;
@group(0) @binding(1) var<storage, read> strokeBuffer : StrokeBuffer;
@group(0) @binding(2) var<uniform> uniforms : UBO;

@compute @workgroup_size(256, 1)
fn main(@builtin(global_invocation_id) global_id : vec3<u32>) {
    let index = global_id.x * 3u;

    
}