const TILE_WIDTH = 16;
const TILE_HEIGHT = 16;
const STROKE_MAX_COUNT = 512;

struct LightPillar {
    key: f32,
    depth: f32,
    length: f32,
    density: f32,
    color: vec3<f32>,
};

// warn: vec3<f32> size 12 but align to 16
// density => color.w
struct Entity { transform: mat4x4<f32>, color: vec4<f32>, };
struct Sphere { base: Entity, };                    // Support

struct UBO {            // align(16) size(96)
    screenWidth: u32,
    screenHeight: u32,
    strokeType: u32,                                // 1
    strokeCount: u32,
    modelViewProjectionMatrix: mat4x4<f32>,
    viewMatrix: mat4x4<f32>,
};

struct StrokeBuffer { data: array<f32>, };
struct BinBuffer { id: array<u32>, };
struct BinSizeBuffer { size: array<atomic<u32>>, };
struct ColorBuffer { pixels: array<vec4f>, };


@group(0) @binding(0) var<storage, read_write> binSizeBuffer : BinSizeBuffer;
@group(0) @binding(1) var<storage, read_write> binBuffer : BinBuffer;
@group(0) @binding(2) var<storage, read> strokeBuffer : StrokeBuffer;
@group(0) @binding(3) var<storage, read_write> outputBuffer : ColorBuffer;
@group(0) @binding(4) var<uniform> uniforms : UBO;

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

@compute @workgroup_size(16, 16)
fn clear(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // global_id.x is pixel x
    // global_id.y is pixel y
    if global_id.x > uniforms.screenWidth || global_id.y > uniforms.screenHeight { return; }
    let index = global_id.x + global_id.y * uniforms.screenWidth;
    let TILE_COUNT_X = (uniforms.screenWidth - 1) / TILE_WIDTH + 1;
    let TILE_COUNT_Y = (uniforms.screenHeight - 1) / TILE_HEIGHT + 1;
    if index < TILE_COUNT_X * TILE_COUNT_Y {
        atomicStore(&binSizeBuffer.size[index], 0);
    }
    outputBuffer.pixels[index] = vec4f(0);
}

@compute @workgroup_size(256, 1, 1)
fn tile(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // global_id.x is primitive id
    // global_id.y is tile width id
    // global_id.z is tile height id
    if global_id.x >= uniforms.strokeCount { return; }
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
                (screenPos.x / screenPos.w * 0.5 + 0.5) * f32(uniforms.screenWidth),
                (screenPos.y / screenPos.w * 0.5 + 0.5) * f32(uniforms.screenHeight),
                screenPos.z / screenPos.w
            );
        }
        var cube_min: vec3<f32> = cube[0];
        var cube_max: vec3<f32> = cube[0];
        for (var i = 1u; i < 8u; i++) {
            cube_min = min(cube_min, cube[i]);
            cube_max = max(cube_max, cube[i]);
        }
        let tile_lt = vec2<u32>(global_id.y * TILE_WIDTH, global_id.z * TILE_HEIGHT);
        let tile_rb = vec2<u32>(global_id.y * TILE_WIDTH + TILE_WIDTH, global_id.z * TILE_HEIGHT + TILE_HEIGHT);
        if !(cube_min.x > f32(tile_rb.x) || cube_min.y > f32(tile_rb.y) || cube_max.x < f32(tile_lt.x) || cube_max.y < f32(tile_lt.y)) {
            let index = global_id.y + global_id.z * TILE_COUNT_X;
            let indexBias = uniforms.strokeCount * index;
            binBuffer.id[indexBias + atomicAdd(&binSizeBuffer.size[index], 1)] = global_id.x;
        }
    }
}


// const SHARED_COUNT = 512;
// var<workgroup> listData : array<Sphere, SHARED_COUNT>;  // I'm RTX3060 Laptop, shared memory 48K, smaller is ok

// 16x16 pixels per tile
@compute @workgroup_size(1, 1, 16)
fn rasterize_sphere(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // global_id.x is tile width id
    // global_id.y is tile height id
    // global_id.z is pixel id
    let TILE_COUNT_X = (uniforms.screenWidth - 1) / TILE_WIDTH + 1;
    let TILE_COUNT_Y = (uniforms.screenHeight - 1) / TILE_HEIGHT + 1;
    let tileId = global_id.x + global_id.y * TILE_COUNT_X;
    let indexBias = uniforms.strokeCount * tileId;
    let listCount = atomicLoad(&binSizeBuffer.size[tileId]);
    if listCount == 0 { return; }
    // // load to shared memory
    // for (let i = global_id.y * 16 + global_id.z; i < listCount; i += 256) {
    //     listData[i] = strokeBuffer.data[binBuffer.id[indexBias + i] ];
    // }
    // workgroupBarrier();
    // // per pixel calculate intersection, sort, α-blending
    var frags: array<LightPillar, STROKE_MAX_COUNT>;
    var frags_id: array<u32, STROKE_MAX_COUNT>;
    let pixelX = global_id.x * 16 + (global_id.z / TILE_WIDTH);
    let pixelY = global_id.y * 16 + (global_id.z % TILE_HEIGHT);
    let pixelId = pixelX + pixelY * uniforms.screenWidth;
    if pixelX > uniforms.screenWidth || pixelY > uniforms.screenHeight { return; }
    //outputBuffer.pixels[pixelId] = vec4f(f32(listCount) / f32(uniforms.strokeCount), 0, 0, 1); return;
    for (var i: u32 = 0; i < listCount; i++) {
        let index = binBuffer.id[indexBias + i] * 20u;
        var data: Sphere;
        data.base.transform = mat4x4<f32>(
            strokeBuffer.data[index + 0u], strokeBuffer.data[index + 1u], strokeBuffer.data[index + 2u], strokeBuffer.data[index + 3u],
            strokeBuffer.data[index + 4u], strokeBuffer.data[index + 5u], strokeBuffer.data[index + 6u], strokeBuffer.data[index + 7u],
            strokeBuffer.data[index + 8u], strokeBuffer.data[index + 9u], strokeBuffer.data[index + 10u], strokeBuffer.data[index + 11u],
            strokeBuffer.data[index + 12u], strokeBuffer.data[index + 13u], strokeBuffer.data[index + 14u], strokeBuffer.data[index + 15u]
        );
        data.base.color = vec4<f32>(strokeBuffer.data[index + 16u], strokeBuffer.data[index + 17u], strokeBuffer.data[index + 18u], strokeBuffer.data[index + 19u]);
        let m = uniforms.modelViewProjectionMatrix * data.base.transform;
        let m_inv = inverse(m);
        var _u: vec4f = m_inv * vec4<f32>(f32(pixelX) / f32(uniforms.screenWidth) * 2f - 1f, f32(pixelY) / f32(uniforms.screenHeight) * 2f - 1f, 1, 1);
        _u /= _u.w;
        var _v: vec4f = m_inv * vec4<f32>(0, 0, 0, 1);
        _v /= _v.w;
        let u: vec3f = (_u - _v).xyz;
        let v: vec3f = _v.xyz;
        let a = dot(u, u);
        let b = 2 * dot(u, v);
        let c = dot(v, v) - 1;
        let delta2 = b * b - 4 * a * c;
        if delta2 < 0 { frags[i].key = 1e7; continue; }
        let delta = sqrt(delta2);
        let root1 = (-b - delta) / (2 * a);
        let root2 = (-b + delta) / (2 * a);
        let _p1 = u * root1 + v;
        let _p2 = u * root2 + v;
        let p1 = m * vec4f(_p1, 1);
        let p2 = m * vec4f(_p2, 1);
        var d1 = p1.z / p1.w;
        var d2 = p2.z / p2.w;
        if d1 > d2 { let _d = d1; d1 = d2; d2 = _d; }
        var tmp: LightPillar;
        tmp.color = data.base.color.xyz;
        tmp.density = data.base.color.w;
        tmp.depth = d1;
        tmp.length = d2 - d1;
        //tmp.key = tmp.density * exp(-LIGHT_PILLAR_LAMBDA * tmp.depth);
        tmp.key = tmp.depth;
        frags[i] = tmp;
    }
    for (var i: u32 = 0; i < listCount; i++) {
        frags_id[i] = i;
    }
    for (var i: u32 = 0; i < listCount; i++) {
        for (var j = i + 1; j < listCount; j++) {
            if frags[frags_id[j] ].key < frags[frags_id[i] ].key {
                var t = frags_id[i];
                frags_id[i] = frags_id[j];
                frags_id[j] = t;
            }
        }
    }
    outputBuffer.pixels[pixelId] = vec4f(frags[frags_id[0] ].color, 1.0f);
}