const LIGHT_PILLAR_LAMBDA = 1.0f;

struct LightPillar {    // align(8) size(16)
    key: f32,           // density * exp(-lambda * depth)
    depth: f32,
    length: f32,
    density: f32,
    color: vec3<f32>,
};

struct LightPillarBuffer { segments: array<LightPillar>, };
struct SpinLockBuffer { cas: array<atomic<u32>>, };

struct UBO {            // align(16) size(144)
    screenWidth: f32,
    screenHeight: f32,
    strokeType: u32,                                // 1
    modelViewProjectionMatrix: mat4x4<f32>,
    modelViewMatrix: mat4x4<f32>,
};

// warn: vec3<f32> size 12 but align to 16
// density => color.w
struct Entity { transform: mat4x4<f32>, color: vec4<f32>, };    

struct Triangle { verts: array<vec3<f32>, 3>, };
struct Sphere { base: Entity, };                    // Support
struct Cube { base: Entity, };
struct Tetrahedron { base: Entity, };
struct Octahedron { base: Entity, };
struct RoundCube { base: Entity, r: f32, };
struct Triprism { base: Entity, h: f32, };
struct Capsule { base: Entity, h: f32, r: f32, };

struct StrokeBuffer { data: array<f32>, };

struct Argument { left: u32, top: u32, width: u32, height: u32, _1: u32 };

@group(0) @binding(0) var<storage, read_write> outputBuffer : LightPillarBuffer;
@group(0) @binding(1) var<storage, read_write> spinLockBuffer : SpinLockBuffer;
@group(0) @binding(2) var<storage, read> strokeBuffer : StrokeBuffer;
@group(0) @binding(3) var<storage, read_write> argBuffer: array<Argument>;
@group(0) @binding(4) var<uniform> uniforms : UBO;

fn project(v: vec3<f32>) -> vec3<f32> {
    var screenPos = uniforms.modelViewProjectionMatrix * vec4<f32>(v, 1.0);
    screenPos.x = (screenPos.x / screenPos.w * 0.5 + 0.5) * uniforms.screenWidth;
    screenPos.y = (screenPos.y / screenPos.w * 0.5 + 0.5) * uniforms.screenHeight;
    return vec3<f32>(screenPos.x, screenPos.y, screenPos.z / screenPos.w);
}

fn is_off_screen(v: vec3<f32>) -> bool {
    if v.x < 0.0 || v.x > uniforms.screenWidth || v.y < 0.0 || v.y > uniforms.screenHeight {
        return true;
    }
    return false;
}

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

fn depth_test(x: u32, y: u32, l: LightPillar) {
    let index = u32(x + y * u32(uniforms.screenWidth));
    // 用自旋锁来保证深度写入不冲突
    var own: bool;
    loop {
        //own = atomicCompareExchangeWeak(&spinLockBuffer.cas[index], 0u, 1u).exchanged;
        own = true;
        if own {
            if l.key < outputBuffer.segments[index].key { outputBuffer.segments[index] = l; }
            atomicStore(&spinLockBuffer.cas[index], 0u);
            return;
        }
    }
}

fn rasterize_sphere(data: Sphere) {
    // m是从单位球变换到裁剪空间
    let m = uniforms.modelViewProjectionMatrix * data.base.transform;
    let m_inv = inverse(m);
    // 从单位球的包围立方体来估算光栅化范围
    var cube = array<vec3<f32>, 8>(
        vec3<f32>(-1.0f, -1.0f, -1.0f), vec3<f32>(-1.0f, -1.0f, 1.0f),
        vec3<f32>(-1.0f, 1.0f, -1.0f), vec3<f32>(-1.0f, 1.0f, 1.0f),
        vec3<f32>(1.0f, -1.0f, -1.0f), vec3<f32>(1.0f, -1.0f, 1.0f),
        vec3<f32>(1.0f, 1.0f, -1.0f), vec3<f32>(1.0f, 1.0f, 1.0f)
    );
    for (var i = 0u; i < 8u; i++) { cube[i] = project((data.base.transform * vec4f(cube[i], 1.0f)).xyz); }
    var cube_min: vec3<f32> = cube[0];
    var cube_max: vec3<f32> = cube[0];
    for (var i = 1u; i < 8u; i++) {
        cube_min = min(cube_min, cube[i]);
        cube_max = max(cube_max, cube[i]);
    }
    let startX = u32(clamp(cube_min.x, 0.0f, uniforms.screenWidth - 1e-3));
    let startY = u32(clamp(cube_min.y, 0.0f, uniforms.screenHeight - 1e-3));
    let endX = u32(clamp(cube_max.x, 0.0f, uniforms.screenWidth - 1e-3));
    let endY = u32(clamp(cube_max.y, 0.0f, uniforms.screenHeight - 1e-3));
    // 通过列一元二次方程，求解。设交点p，则p = u * t + v，列出|p| = 1解得t。
    for (var x: u32 = startX; x <= endX; x = x + 1u) {
        for (var y: u32 = startY; y <= endY; y = y + 1u) {
            //outputBuffer.segments[x + y * u32(uniforms.screenWidth)].color = vec3f(1, 0, 0); continue;
            var _u : vec4f = m_inv * vec4<f32>(f32(x) / uniforms.screenWidth * 2f - 1f, f32(y) / uniforms.screenHeight * 2f - 1f, 1, 1);
            _u /= _u.w;
            var _v : vec4f = m_inv * vec4<f32>(0, 0, 0, 1);
            _v /= _v.w;
            let u : vec3f = (_u - _v).xyz;
            let v : vec3f = _v.xyz;
            let a = dot(u, u);
            let b = 2 * dot(u, v);
            let c = dot(v, v) - 1;
            let delta2 = b * b - 4 * a * c;
            if delta2 < 0 { continue; }
            //outputBuffer.segments[x + y * u32(uniforms.screenWidth)].color = vec3f(delta2 / 1000000); continue;
            let delta = sqrt(delta2);
            let root1 = (-b - delta) / (2 * a);
            let root2 = (-b + delta) / (2 * a);
            let _p1 = u * root1 + v;
            let _p2 = u * root2 + v;
            let p1 = m * vec4f(_p1, 1);
            let p2 = m * vec4f(_p2, 1);
            var d1 = p1.z / p1.w;
            var d2 = p2.z / p2.w;
            if (d1 > d2) { let _d = d1; d1 = d2; d2 = _d; }
            var tmp: LightPillar;
            tmp.color = data.base.color.xyz;
            tmp.density = data.base.color.w;
            tmp.depth = d1;
            tmp.length = d2 - d1;
            //tmp.key = tmp.density * exp(-LIGHT_PILLAR_LAMBDA * tmp.depth);
            tmp.key = tmp.depth;
            depth_test(x, y, tmp);
        }
    }
}

@compute @workgroup_size(256, 1)
fn clear(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let index = global_id.x;
    atomicStore(&spinLockBuffer.cas[index], 0u);
    outputBuffer.segments[index].key = 1e7f;
    outputBuffer.segments[index].density = 0.0f;
    outputBuffer.segments[index].color = vec3f(0.0f, 0.0f, 0.0f);
    outputBuffer.segments[index].depth = 1.1e2f;
    outputBuffer.segments[index].length = 0.0f;
}

@compute @workgroup_size(256, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if uniforms.strokeType == 1 {   // Ellipsoid
        let index = global_id.x * 20u;
        var data: Sphere;
        data.base.transform = mat4x4<f32>(
            strokeBuffer.data[index + 0u], strokeBuffer.data[index + 1u], strokeBuffer.data[index + 2u], strokeBuffer.data[index + 3u],
            strokeBuffer.data[index + 4u], strokeBuffer.data[index + 5u], strokeBuffer.data[index + 6u], strokeBuffer.data[index + 7u],
            strokeBuffer.data[index + 8u], strokeBuffer.data[index + 9u], strokeBuffer.data[index + 10u], strokeBuffer.data[index + 11u],
            strokeBuffer.data[index + 12u], strokeBuffer.data[index + 13u], strokeBuffer.data[index + 14u], strokeBuffer.data[index + 15u]
        );
        data.base.color = vec4<f32>(strokeBuffer.data[index + 16u], strokeBuffer.data[index + 17u], strokeBuffer.data[index + 18u], strokeBuffer.data[index + 19u]);
        rasterize_sphere(data);
    }
}