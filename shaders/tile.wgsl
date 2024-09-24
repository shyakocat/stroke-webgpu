const TILE_WIDTH = 16;
const TILE_HEIGHT = 16;

// warn: vec3<f32> size 12 but align to 16
// density => color.w
struct Entity { transform: mat4x4<f32>, color: vec4<f32>, };
struct Sphere { base: Entity, };                    // Support

struct UBO {            // align(16) size(96)
    screenWidth: u32,
    screenHeight: u32,
    strokeType: u32,                                // 1
    modelViewProjectionMatrix: mat4x4<f32>,
    viewMatrix: mat4x4<f32>,
};

struct StrokeBuffer { count: u32, data: array<f32>, };
struct BinBuffer { id: array<u32>, };


@group(0) @binding(0) var<storage, read_write> binBuffer : BinBuffer;
@group(0) @binding(1) var<storage, read> strokeBuffer : StrokeBuffer;
@group(0) @binding(2) var<uniform> uniforms : UBO;

fn inverse(m: mat4x4f) -> mat4x4f {
    let a00 = m[0][0]; let a01 = m[0][1]; let a02 = m[0][2]; let a03 = m[0][3];
    let a10 = m[1][0]; let a11 = m[1][1]; let a12 = m[1][2]; let a13 = m[1][3];
    let a20 = m[2][0]; let a21 = m[2][1]; let a22 = m[2][2]; let a23 = m[2][3];
    let a30 = m[3][0]; let a31 = m[3][1]; let a32 = m[3][2]; let a33 = m[3][3];

    let b00 = a00 * a11 - a01 * a10;
    let b01 = a00 * a12 - a02 * a10;
    let b02 = a00 * a13 - a03 * a10;
    let b03 = a01 * a12 - a02 * a11;
    let b04 = a01 * a13 - a03 * a11;
    let b05 = a02 * a13 - a03 * a12;
    let b06 = a20 * a31 - a21 * a30;
    let b07 = a20 * a32 - a22 * a30;
    let b08 = a20 * a33 - a23 * a30;
    let b09 = a21 * a32 - a22 * a31;
    let b10 = a21 * a33 - a23 * a31;
    let b11 = a22 * a33 - a23 * a32;

    let det = b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06;

    return mat4x4f(
        a11 * b11 - a12 * b10 + a13 * b09,
        a02 * b10 - a01 * b11 - a03 * b09,
        a31 * b05 - a32 * b04 + a33 * b03,
        a22 * b04 - a21 * b05 - a23 * b03,
        a12 * b08 - a10 * b11 - a13 * b07,
        a00 * b11 - a02 * b08 + a03 * b07,
        a32 * b02 - a30 * b05 - a33 * b01,
        a20 * b05 - a22 * b02 + a23 * b01,
        a10 * b10 - a11 * b08 + a13 * b06,
        a01 * b08 - a00 * b10 - a03 * b06,
        a30 * b04 - a31 * b02 + a33 * b00,
        a21 * b02 - a20 * b04 - a23 * b00,
        a11 * b07 - a10 * b09 - a12 * b06,
        a00 * b09 - a01 * b07 + a02 * b06,
        a31 * b01 - a30 * b03 - a32 * b00,
        a20 * b03 - a21 * b01 + a22 * b00
    ) * (1 / det);
}

@compute @workgroup_size(256)
fn clear(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let index = global_id.x;
    binBuffer.id[index] = 0;
}

@compute @workgroup_size(1, 16, 16)
fn tile(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // global_id.x is primitive id
    // global_id.y is tile width id
    // global_id.z is tile height id
    let TILE_COUNT_X = (uniforms.screenWidth - 1) / TILE_WIDTH + 1;
    let TILE_COUNT_Y = (uniforms.screenHeight - 1) / TILE_HEIGHT + 1;
    if uniforms.strokeType == 1 {   
        // Ellipsoid
        let index = global_id.x * 20u;
        var data: Sphere;
        data.base.transform = mat4x4<f32>(
            strokeBuffer.data[index + 0u], strokeBuffer.data[index + 1u], strokeBuffer.data[index + 2u], strokeBuffer.data[index + 3u],
            strokeBuffer.data[index + 4u], strokeBuffer.data[index + 5u], strokeBuffer.data[index + 6u], strokeBuffer.data[index + 7u],
            strokeBuffer.data[index + 8u], strokeBuffer.data[index + 9u], strokeBuffer.data[index + 10u], strokeBuffer.data[index + 11u],
            strokeBuffer.data[index + 12u], strokeBuffer.data[index + 13u], strokeBuffer.data[index + 14u], strokeBuffer.data[index + 15u]
        );
        data.base.color = vec4<f32>(strokeBuffer.data[index + 16u], strokeBuffer.data[index + 17u], strokeBuffer.data[index + 18u], strokeBuffer.data[index + 19u]);
        // 直接判椭球太难，可以判椭球的包围盒
        let m = uniforms.modelViewProjectionMatrix * data.base.transform;
        var cube = array<vec3<f32>, 8>(
            vec3<f32>(-1.0f, -1.0f, -1.0f), vec3<f32>(-1.0f, -1.0f, 1.0f),
            vec3<f32>(-1.0f, 1.0f, -1.0f), vec3<f32>(-1.0f, 1.0f, 1.0f),
            vec3<f32>(1.0f, -1.0f, -1.0f), vec3<f32>(1.0f, -1.0f, 1.0f),
            vec3<f32>(1.0f, 1.0f, -1.0f), vec3<f32>(1.0f, 1.0f, 1.0f)
        );
        for (var i = 0u; i < 8u; i++) {
            let screenPos = uniforms.modelViewProjectionMatrix * data.base.transform * vec4f(cube[i], 1.0f);
            cube[i] = vec3f(
                (screenPos.x / screenPos.w * 0.5 + 0.5) * uniforms.screenWidth,
                (screenPos.y / screenPos.w * 0.5 + 0.5) * uniforms.screenHeight,
                screenPos.z / screenPos.w
            );
        }
        var cube_min: vec3<f32> = cube[0];
        var cube_max: vec3<f32> = cube[0];
        for (var i = 1u; i < 8u; i++) {
            cube_min = min(cube_min, cube[i]);
            cube_max = max(cube_max, cube[i]);
        }
        let tile_lt = vec2f(global_id.y * TILE_WIDTH, global_id.z * TILE_HEIGHT);
        let tile_rb = vec2f(global_id.y * TILE_WIDTH + TILE_WIDTH, global_id.z * TILE_HEIGHT + TILE_HEIGHT);
        if !(cube_min.x > tile_rb.x || cube_min.y > tile_rb.y || cube_max.x < tile_lt.x || cube_max.y < tile_lt.y) {
            let index = global_id.y * TILE_COUNT_X + global_id.z;
            let indexCnt = (strokeBuffer.count + 1) * index;
            binBuffer.id[indexCnt]++;
            binBuffer.id[indexCnt + binBuffer.id[indexCnt] ] = global_id.x;
        }
    }
}


const SHARED_COUNT = 512;
var<workgroup> listData : array<Sphere, SHARED_COUNT>;  // I'm RTX3060 Laptop, shared memory 48K, smaller is ok

// 16x16 pixels per tile
@compute @workgroup_size(1, 16, 16)
fn rasterize_sphere(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // global_id.x is tile id
    // global_id.y is pixel x coord
    // global_id.z is pixel y coord
    let indexCnt = (strokeBuffer.count + 1) * global_id.x;
    let listCount = binBuffer.id[indexCnt];
    // load to shared memory
    for (let i = global_id.y * 16 + global_id.z; i < listCount; i += 256) {
        listData[i] = strokeBuffer.data[binBuffer.id[indexCnt + i] ];
    }
    workgroupBarrier();
    // per pixel calculate intersection, sort, α-blending
    let TILE_COUNT_X = (uniforms.screenWidth - 1) / TILE_WIDTH + 1;
    let TILE_COUNT_Y = (uniforms.screenHeight - 1) / TILE_HEIGHT + 1;
    let pixelX = (global_id.x / TILE_COUNT_X) * 16 + global_id.y;
    let pixelY = (global_id.x % TILE_COUNT_X) * 16 + global_id.z;
    let mvp_inv = inverse(uniforms.modelViewProjectionMatrix);
    let p1 : vec4f = mvp_inv * vec4f(pixelX / uniforms.screenWidth * 2 - 1, pixelY / uniforms.screenHeight * 2 - 1, 1, 1);
    let p1 : vec3f = p1.xyz / p1.w;
    let p2 : vec4f = mvp_inv * vec4f(0, 0, 0, 1);
    let p2 : vec3f = p2.xyz / p2.w;
    for (var i = 0; i < listCount; i++) {

    }
}