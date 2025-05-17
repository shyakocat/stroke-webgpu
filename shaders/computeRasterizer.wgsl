const COMPOSITION_METHOD_OVERLAY = 0;  
const COMPOSITION_METHOD_MAX = 1;
const COMPOSITION_METHOD_SOFTMAX = 2;   // Not Support

const TILE_WIDTH = 16;
const TILE_HEIGHT = 16;                                 // 分片的宽和高，不建议改动
const STROKE_MAX_COUNT = 100;                             // 每个像素采样的个数
const STROKE_MAX_COUNT_ADD_1 = STROKE_MAX_COUNT + 1;    
const STROKE_MAX_COUNT_MUL_2 = STROKE_MAX_COUNT * 2;
const DENSITY_SCALE = 20;                               // 密度缩放因子，需与论文的python训练实现保持一致
const BACKGROUND_COLOR = vec4f(1, 1, 1, 1);
const eps = 1e-5;
const COMPOSITION_METHOD = COMPOSITION_METHOD_OVERLAY;
const COMPOSITION_METHOD_SOFTMAX_TAO = 0.05;

struct LightPillar {
    key: f32,
    depth: f32,
    length: f32,
    density: f32,
    id: u32,
    color: vec3<f32>,
};

// warn: vec3<f32> size 12 but align to 16
// density => color.w
struct Entity { transform: mat4x4<f32>, color: vec4<f32>, shape: u32, id: u32, };
struct Sphere { base: Entity, };                    // Support 球体
struct Cube { base: Entity, };                      // Support 立方体
struct Tetrahedron { base: Entity, };               // Support 四面体
struct Octahedron { base: Entity, };                // Support 八面体
struct Capsule { base: Entity, ra: f32, rb: f32, length: f32, }    // Support 胶囊体
struct Cylinder { base: Entity, };                  // Support 圆柱体

struct UBO {            // align(16) size(96)
    screenWidth: u32,
    screenHeight: u32,
    strokeCount: u32,
    modelViewProjectionMatrix: mat4x4<f32>,
    modelViewMatrix: mat4x4<f32>,
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

fn sqr(x: f32) -> f32 { return x * x; }

fn getEntity(index: u32) -> Entity {
    var e: Entity;
    e.transform = mat4x4<f32>(
        strokeBuffer.data[index + 0u], strokeBuffer.data[index + 1u], strokeBuffer.data[index + 2u], strokeBuffer.data[index + 3u],
        strokeBuffer.data[index + 4u], strokeBuffer.data[index + 5u], strokeBuffer.data[index + 6u], strokeBuffer.data[index + 7u],
        strokeBuffer.data[index + 8u], strokeBuffer.data[index + 9u], strokeBuffer.data[index + 10u], strokeBuffer.data[index + 11u],
        strokeBuffer.data[index + 12u], strokeBuffer.data[index + 13u], strokeBuffer.data[index + 14u], strokeBuffer.data[index + 15u]
    );
    e.color = vec4<f32>(strokeBuffer.data[index + 16u], strokeBuffer.data[index + 17u], strokeBuffer.data[index + 18u], strokeBuffer.data[index + 19u]);
    e.shape = u32(strokeBuffer.data[index + 20u]);
    e.id = u32(strokeBuffer.data[index + 21u]);
    return e;
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
    outputBuffer.pixels[index] = BACKGROUND_COLOR;
}

@compute @workgroup_size(256, 1, 1)
fn tile(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // global_id.x is primitive id
    // global_id.y is tile width id
    // global_id.z is tile height id
    if global_id.x >= uniforms.strokeCount { return; }
    let TILE_COUNT_X = (uniforms.screenWidth - 1) / TILE_WIDTH + 1;
    let TILE_COUNT_Y = (uniforms.screenHeight - 1) / TILE_HEIGHT + 1;
    let index: u32 = global_id.x * 25u;
    var base: Entity;
    base = getEntity(index);
    // 直接判图元太难，可以判图元的包围盒
    let m = uniforms.modelViewProjectionMatrix * base.transform;
    var cubes: array<vec3<f32>, 8>;
    if base.shape == 1 || base.shape == 2 || base.shape == 3 || base.shape == 4 || base.shape == 6 { 
        // Ellipsode or Box or Tetrahedron or Octahedron
        cubes = array<vec3<f32>, 8>(
            vec3<f32>(-1.0f, -1.0f, -1.0f), vec3<f32>(-1.0f, -1.0f, 1.0f),
            vec3<f32>(-1.0f, 1.0f, -1.0f), vec3<f32>(-1.0f, 1.0f, 1.0f),
            vec3<f32>(1.0f, -1.0f, -1.0f), vec3<f32>(1.0f, -1.0f, 1.0f),
            vec3<f32>(1.0f, 1.0f, -1.0f), vec3<f32>(1.0f, 1.0f, 1.0f)
        );
    } else if base.shape == 5 { 
        // Capsule
        let r = max(strokeBuffer.data[index + 22u], strokeBuffer.data[index + 23u]);
        let l = strokeBuffer.data[index + 24u] * 0.5;
        let h = l + r;
        cubes = array<vec3<f32>, 8>(
            vec3<f32>(-r, -r, -h), vec3<f32>(-r, -r, h),
            vec3<f32>(-r, r, -h), vec3<f32>(-r, r, h),
            vec3<f32>(r, -r, -h), vec3<f32>(r, -r, h),
            vec3<f32>(r, r, -h), vec3<f32>(r, r, h)
        );
    }
    for (var i = 0u; i < 8u; i++) {
        let screenPos = uniforms.modelViewProjectionMatrix * base.transform * vec4f(cubes[i], 1.0f);
        cubes[i] = vec3f(
            (screenPos.x / screenPos.w * 0.5 + 0.5) * f32(uniforms.screenWidth),
            (screenPos.y / screenPos.w * 0.5 + 0.5) * f32(uniforms.screenHeight),
            screenPos.z / screenPos.w
        );
    }
    var cube_min: vec3<f32> = cubes[0];
    var cube_max: vec3<f32> = cubes[0];
    for (var i = 1u; i < 8u; i++) {
        cube_min = min(cube_min, cubes[i]);
        cube_max = max(cube_max, cubes[i]);
    }
    let tile_lt = vec2<u32>(global_id.y * TILE_WIDTH, global_id.z * TILE_HEIGHT);
    let tile_rb = vec2<u32>(global_id.y * TILE_WIDTH + TILE_WIDTH, global_id.z * TILE_HEIGHT + TILE_HEIGHT);
    if !(cube_min.x > f32(tile_rb.x) || cube_min.y > f32(tile_rb.y) || cube_max.x < f32(tile_lt.x) || cube_max.y < f32(tile_lt.y)) {
        let tileId = global_id.y + global_id.z * TILE_COUNT_X;
        let indexBias = uniforms.strokeCount * tileId;
        binBuffer.id[indexBias + atomicAdd(&binSizeBuffer.size[tileId], 1)] = global_id.x;
    }
}



// const SHARED_COUNT = 512;
// var<workgroup> listData : array<Sphere, SHARED_COUNT>;  // I'm RTX3060 Laptop, shared memory 48K, smaller is ok

struct Pair { key: f32, value: u32, };

fn inverse3x3(matrix: mat3x3<f32>) -> mat3x3<f32> {
    // 获取矩阵元素
    let a00 = matrix[0][0];
    let a01 = matrix[0][1];
    let a02 = matrix[0][2];
    let a10 = matrix[1][0];
    let a11 = matrix[1][1];
    let a12 = matrix[1][2];
    let a20 = matrix[2][0];
    let a21 = matrix[2][1];
    let a22 = matrix[2][2];

    // 计算行列式
    let determinant = a00 * (a11 * a22 - a12 * a21) - a01 * (a10 * a22 - a12 * a20) + a02 * (a10 * a21 - a11 * a20);

    // 如果行列式为0，则矩阵不可逆
    // if determinant == 0.0 {
    //     return mat3x3<f32>(
    //         vec3<f32>(0.0, 0.0, 0.0),
    //         vec3<f32>(0.0, 0.0, 0.0),
    //         vec3<f32>(0.0, 0.0, 0.0)
    //     );
    // }

    // 计算矩阵的余子式矩阵
    let cofactor = mat3x3<f32>(
        vec3<f32>((a11 * a22 - a12 * a21), -(a01 * a22 - a02 * a21), (a01 * a12 - a02 * a11)),
        vec3<f32>(-(a10 * a22 - a12 * a20), (a00 * a22 - a02 * a20), -(a00 * a12 - a02 * a10)),
        vec3<f32>((a10 * a21 - a11 * a20), -(a00 * a21 - a01 * a20), (a00 * a11 - a01 * a10))
    );

    // 转置余子式矩阵并除以行列式
    return transpose(cofactor) * (1 / determinant);
}

fn barycentricMatrix(triangles: array<vec3f, 3>) -> mat3x3f {
    let OA = triangles[1] - triangles[0];
    let OB = triangles[2] - triangles[0];
    return inverse3x3(transpose(mat3x3f(OA, OB, cross(OA, OB))));
}


struct QuadraticEquationResult { hasAnswer: bool, answer: vec2<f32>,  };
fn solve_quadratic_eqation(a: f32, b: f32, c: f32) -> QuadraticEquationResult {
    var ret: QuadraticEquationResult;
    let delta2 = b * b - 4 * a * c;
    if delta2 < 0 { ret.hasAnswer = false; return ret; }
    let delta = sqrt(delta2);
    let root1 = (-b - delta) / (2 * a);
    let root2 = (-b + delta) / (2 * a);
    ret.hasAnswer = true;
    ret.answer = vec2f(root1, root2);
    return ret;
}

// 16x16 pixels per tile
@compute @workgroup_size(1, 1, 64)
fn rasterize(@builtin(global_invocation_id) global_id: vec3<u32>) {
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
    let pixelX = global_id.x * 16 + (global_id.z / TILE_WIDTH);
    let pixelY = global_id.y * 16 + (global_id.z % TILE_HEIGHT);
    let pixelId = pixelX + pixelY * uniforms.screenWidth;
    if pixelX > uniforms.screenWidth || pixelY > uniforms.screenHeight { return; }
    //outputBuffer.pixels[pixelId] = vec4f(f32(listCount) / f32(uniforms.strokeCount), 0, 0, 1); return;
    //outputBuffer.pixels[pixelId] = vec4f(1, 0, 0, 1); return;
    var samples: array<LightPillar, STROKE_MAX_COUNT_ADD_1>;
    var sampleCount: u32 = 0;
    for (var i: u32 = 0; i < listCount; i++) {
        let index = binBuffer.id[indexBias + i] * 25u;
        let e : Entity = getEntity(index);
        var tmp: LightPillar;
        tmp.id = e.id;
        tmp.color = e.color.xyz;
        tmp.density = e.color.w;
        if e.shape == 1 {
            // Ellipsoid
            var data: Sphere;
            data.base = e;
            let m = uniforms.modelViewProjectionMatrix * data.base.transform;
            let m_inv = inverse(m);
            var _u: vec4f = m_inv * vec4<f32>(f32(pixelX) / f32(uniforms.screenWidth) * 2f - 1f, f32(pixelY) / f32(uniforms.screenHeight) * 2f - 1f, 1, 1);
            _u /= _u.w;
            var _v: vec4f = m_inv * vec4<f32>(0, 0, 0, 1);
            _v /= _v.w;
            let u: vec3f = (_u - _v).xyz;
            let v: vec3f = _v.xyz;
            let ret = solve_quadratic_eqation(dot(u, u), 2 * dot(u, v), dot(v, v) - 1);
            if !(ret.hasAnswer) { continue; }
            let _p1 = u * ret.answer.x + v;
            let _p2 = u * ret.answer.y + v;
            let p1 = uniforms.modelViewMatrix * data.base.transform * vec4f(_p1, 1);
            let p2 = uniforms.modelViewMatrix * data.base.transform * vec4f(_p2, 1);
            var d1 = -p1.z / p1.w;
            var d2 = -p2.z / p2.w;
            if d1 > d2 { let _d = d1; d1 = d2; d2 = _d; }
            tmp.depth = d1;
            tmp.length = d2 - d1;
            //tmp.key = tmp.density * exp(-LIGHT_PILLAR_LAMBDA * tmp.depth);
            tmp.key = tmp.depth;
        }
        else if e.shape == 2 {
            // Cube
            let surfaces = array<vec4f, 6>(
                vec4f(0.0f, 1.0f, 0.0f, -1.0f), vec4f(0.0f, 1.0f, 0.0f, 1.0f),
                vec4f(0.0f, 0.0f, 1.0f, -1.0f), vec4f(0.0f, 0.0f, 1.0f, 1.0f),
                vec4f(1.0f, 0.0f, 0.0f, -1.0f), vec4f(1.0f, 0.0f, 0.0f, 1.0f),
            );
            var data: Cube;
            data.base = e;
            let m = uniforms.modelViewProjectionMatrix * data.base.transform;
            let m_inv = inverse(m);
            var _u: vec4f = m_inv * vec4<f32>(f32(pixelX) / f32(uniforms.screenWidth) * 2f - 1f, f32(pixelY) / f32(uniforms.screenHeight) * 2f - 1f, 1, 1);
            _u /= _u.w;
            var _v: vec4f = m_inv * vec4<f32>(0, 0, 0, 1);
            _v /= _v.w;
            let u: vec3f = (_u - _v).xyz;
            let v: vec3f = _v.xyz;
            var solutionCount: u32 = 0;
            var solutions = array<f32, 2>();
            for (var j: u32 = 0; j < 6; j++) {
                let s = surfaces[j];
                if abs(dot(s.xyz, u)) < eps { continue; }
                let t = (-s.w - dot(s.xyz, v)) / dot(s.xyz, u);
                let p = u * t + v;
                // let w = dot(s, vec4f(p, 1.0f));
                // outputBuffer.pixels[pixelId] = vec4f(vec3f(w), 1.0f); return;
                // outputBuffer.pixels[pixelId] = vec4f((p + 10) / 20, 1.0f); return;
                if abs(p.x) > 1 + eps || abs(p.y) > 1 + eps || abs(p.z) > 1 + eps { continue; }
                solutions[solutionCount] = t;
                solutionCount++;
                if solutionCount == 2 { break; }
            }
            //outputBuffer.pixels[pixelId] = vec4f(vec3f(f32(solutionCount) / 6), 1.0f); return;
            if solutionCount != 2 { continue; }
            let _p1 = u * solutions[0] + v;
            let _p2 = u * solutions[1] + v;
            let p1 = uniforms.modelViewMatrix * data.base.transform * vec4f(_p1, 1);
            let p2 = uniforms.modelViewMatrix * data.base.transform * vec4f(_p2, 1);
            var d1 = -p1.z / p1.w;
            var d2 = -p2.z / p2.w;
            if d1 > d2 { let _d = d1; d1 = d2; d2 = _d; }
            tmp.depth = d1;
            tmp.length = d2 - d1;
            //tmp.key = tmp.density * exp(-LIGHT_PILLAR_LAMBDA * tmp.depth);
            tmp.key = tmp.depth;
        }
        else if e.shape == 3 {
            // Tetrahedron
            let triangles = array<array<vec3f, 3>, 4>(
                array<vec3f, 3>(vec3f(-1, 1, -1), vec3f(1, -1, -1), vec3f(-1, -1, 1)),
                array<vec3f, 3>(vec3f(-1, 1, -1), vec3f(1, -1, -1), vec3f(1, 1, 1)),
                array<vec3f, 3>(vec3f(-1, 1, -1), vec3f(-1, -1, 1), vec3f(1, 1, 1)),
                array<vec3f, 3>(vec3f(1, -1, -1), vec3f(-1, -1, 1), vec3f(1, 1, 1)),
            );
            let m_tris = array<mat3x3f, 4>(
                barycentricMatrix(triangles[0]),
                barycentricMatrix(triangles[1]),
                barycentricMatrix(triangles[2]),
                barycentricMatrix(triangles[3]),
            );
            var data: Tetrahedron;
            data.base = e;
            let m = uniforms.modelViewProjectionMatrix * data.base.transform;
            let m_inv = inverse(m);
            var _u: vec4f = m_inv * vec4<f32>(f32(pixelX) / f32(uniforms.screenWidth) * 2f - 1f, f32(pixelY) / f32(uniforms.screenHeight) * 2f - 1f, 1, 1);
            _u /= _u.w;
            var _v: vec4f = m_inv * vec4<f32>(0, 0, 0, 1);
            _v /= _v.w;
            let u: vec3f = (_u - _v).xyz;
            let v: vec3f = _v.xyz;
            var solutionCount: u32 = 0;
            var solutions = array<f32, 2>();
            for (var j: u32 = 0; j < 4; j++) {
                // 推导：c = M^-1 * (P - O);   c = (M^-1 * u) t + M^-1*(v - O)
                let Mi = m_tris[j];
                let O = triangles[j][0];
                let m_c1 = Mi * u;
                let m_c2 = Mi * (v - O);
                let t = -m_c2.z / m_c1.z;
                let p = u * t + v;
                let coef = Mi * (p - O);
                if !(coef[0] > -eps && coef[1] > -eps && coef[0] + coef[1] < 1 + eps) { continue; }
                solutions[solutionCount] = t;
                solutionCount++;
                if solutionCount == 2 { break; }
            }
            //outputBuffer.pixels[pixelId] = vec4f(vec3f(f32(solutionCount) / 4), 1.0f); return;
            if solutionCount != 2 { continue; }
            let _p1 = u * solutions[0] + v;
            let _p2 = u * solutions[1] + v;
            let p1 = uniforms.modelViewMatrix * data.base.transform * vec4f(_p1, 1);
            let p2 = uniforms.modelViewMatrix * data.base.transform * vec4f(_p2, 1);
            var d1 = -p1.z / p1.w;
            var d2 = -p2.z / p2.w;
            if d1 > d2 { let _d = d1; d1 = d2; d2 = _d; }
            tmp.depth = d1;
            tmp.length = d2 - d1;
            //tmp.key = tmp.density * exp(-LIGHT_PILLAR_LAMBDA * tmp.depth);
            tmp.key = tmp.depth;
        }
        else if e.shape == 4 {
            // Octahedron
            let P1 = vec3f(1, 0, 0);
            let P2 = vec3f(-1, 0, 0);
            let P3 = vec3f(0, -1, 0);
            let P4 = vec3f(0, 1, 0);
            let P5 = vec3f(0, 0, 1);
            let P6 = vec3f(0, 0, -1);
            let triangles = array<array<vec3f, 3>, 8>(
                array<vec3f, 3>(P1, P3, P5), array<vec3f, 3>(P1, P3, P6),
                array<vec3f, 3>(P1, P4, P5), array<vec3f, 3>(P1, P4, P6),
                array<vec3f, 3>(P2, P3, P5), array<vec3f, 3>(P2, P3, P6),
                array<vec3f, 3>(P2, P4, P5), array<vec3f, 3>(P2, P4, P6),
            );
            let m_tris = array<mat3x3f, 8>(
                barycentricMatrix(triangles[0]), barycentricMatrix(triangles[1]),
                barycentricMatrix(triangles[2]), barycentricMatrix(triangles[3]),
                barycentricMatrix(triangles[4]), barycentricMatrix(triangles[5]),
                barycentricMatrix(triangles[6]), barycentricMatrix(triangles[7]),
            );
            var data: Octahedron;
            data.base = e;
            let m = uniforms.modelViewProjectionMatrix * data.base.transform;
            let m_inv = inverse(m);
            var _u: vec4f = m_inv * vec4<f32>(f32(pixelX) / f32(uniforms.screenWidth) * 2f - 1f, f32(pixelY) / f32(uniforms.screenHeight) * 2f - 1f, 1, 1);
            _u /= _u.w;
            var _v: vec4f = m_inv * vec4<f32>(0, 0, 0, 1);
            _v /= _v.w;
            let u: vec3f = (_u - _v).xyz;
            let v: vec3f = _v.xyz;
            var solutionCount: u32 = 0;
            var solutions = array<f32, 2>();
            for (var j: u32 = 0; j < 8; j++) {
                // 推导：c = M^-1 * (P - O);   c = (M^-1 * u) t + M^-1*(v - O)
                let Mi = m_tris[j];
                let O = triangles[j][0];
                let m_c1 = Mi * u;
                let m_c2 = Mi * (v - O);
                let t = -m_c2.z / m_c1.z;
                let p = u * t + v;
                let coef = Mi * (p - O);
                if !(coef[0] > -eps && coef[1] > -eps && coef[0] + coef[1] < 1 + eps) { continue; }
                solutions[solutionCount] = t;
                solutionCount++;
                if solutionCount == 2 { break; }
            }
            //outputBuffer.pixels[pixelId] = vec4f(vec3f(f32(solutionCount) / 4), 1.0f); return;
            if solutionCount != 2 { continue; }
            let _p1 = u * solutions[0] + v;
            let _p2 = u * solutions[1] + v;
            let p1 = uniforms.modelViewMatrix * data.base.transform * vec4f(_p1, 1);
            let p2 = uniforms.modelViewMatrix * data.base.transform * vec4f(_p2, 1);
            var d1 = -p1.z / p1.w;
            var d2 = -p2.z / p2.w;
            if d1 > d2 { let _d = d1; d1 = d2; d2 = _d; }
            tmp.depth = d1;
            tmp.length = d2 - d1;
            //tmp.key = tmp.density * exp(-LIGHT_PILLAR_LAMBDA * tmp.depth);
            tmp.key = tmp.depth;
        }
        else if e.shape == 5 {
            var data: Capsule;
            data.base = e;
            data.ra = strokeBuffer.data[index + 22u];
            data.rb = strokeBuffer.data[index + 23u];
            data.length = strokeBuffer.data[index + 24u];
            let ra = data.ra;
            let rb = data.rb;
            let l = data.length;
            let m = uniforms.modelViewProjectionMatrix * data.base.transform;
            let m_inv = inverse(m);
            var _u: vec4f = m_inv * vec4<f32>(f32(pixelX) / f32(uniforms.screenWidth) * 2f - 1f, f32(pixelY) / f32(uniforms.screenHeight) * 2f - 1f, 1, 1);
            _u /= _u.w;
            var _v: vec4f = m_inv * vec4<f32>(0, 0, 0, 1);
            _v /= _v.w;
            let u: vec3f = (_u - _v).xyz;
            let v: vec3f = _v.xyz;
            let A = vec3f(0, 0, -data.length * 0.5);
            let B = vec3f(0, 0, data.length * 0.5);
            let AB = vec3f(0, 0, data.length);
            var solutionCount: u32 = 0;
            var solutions: array<f32, 6>;
            // 判断中间圆柱体
            // Solve:  x^2 + y^2 = r(z)^2
                {
                let ret = solve_quadratic_eqation(
                    dot(u.xy, u.xy) - sqr((rb - ra) * u.z / l),
                    2 * dot(u.xy, v.xy) + (ra - rb) * u.z * (l * (ra + rb) + 2 * (rb - ra) * v.z) / (l * l),
                    dot(v.xy, v.xy) - sqr(l * (ra + rb) + 2 * (rb - ra) * v.z) / (4 * l * l)
                );
                if ret.hasAnswer {
                    let _p1 = u * (ret.answer.x) + v;
                    let _p2 = u * (ret.answer.y) + v;
                    let _t1 = dot(_p1 - A, AB) / dot(AB, AB);
                    let _t2 = dot(_p2 - A, AB) / dot(AB, AB);
                    if 0 <= _t1 && _t1 <= 1 { solutions[solutionCount] = ret.answer.x; solutionCount++; }
                    if 0 <= _t2 && _t2 <= 1 { solutions[solutionCount] = ret.answer.y; solutionCount++; }
                }
            }
            // 判断靠近A端
                {
                let ret = solve_quadratic_eqation(dot(u, u), 2 * dot(u, v - A), dot(v - A, v - A) - ra * ra);
                if ret.hasAnswer {
                    let _p1 = u * (ret.answer.x) + v;
                    let _p2 = u * (ret.answer.y) + v;
                    let _t1 = dot(_p1 - A, AB) / dot(AB, AB);
                    let _t2 = dot(_p2 - A, AB) / dot(AB, AB);
                    if _t1 < 0 { solutions[solutionCount] = ret.answer.x; solutionCount++; }
                    if _t2 < 0 { solutions[solutionCount] = ret.answer.y; solutionCount++; }
                }
            }
            // 判断靠近B端
                {
                let ret = solve_quadratic_eqation(dot(u, u), 2 * dot(u, v - B), dot(v - B, v - B) - rb * rb);
                if ret.hasAnswer {
                    let _p1 = u * (ret.answer.x) + v;
                    let _p2 = u * (ret.answer.y) + v;
                    let _t1 = dot(_p1 - A, AB) / dot(AB, AB);
                    let _t2 = dot(_p2 - A, AB) / dot(AB, AB);
                    if _t1 > 1 { solutions[solutionCount] = ret.answer.x; solutionCount++; }
                    if _t2 > 1 { solutions[solutionCount] = ret.answer.y; solutionCount++; }
                }
            }
            if solutionCount < 2 { continue; }
            let _p1 = u * solutions[0] + v;
            let _p2 = u * solutions[1] + v;
            let p1 = uniforms.modelViewMatrix * data.base.transform * vec4f(_p1, 1);
            let p2 = uniforms.modelViewMatrix * data.base.transform * vec4f(_p2, 1);
            var d1 = -p1.z / p1.w;
            var d2 = -p2.z / p2.w;
            if d1 > d2 { let _d = d1; d1 = d2; d2 = _d; }
            tmp.depth = d1;
            tmp.length = d2 - d1;
            //tmp.key = tmp.density * exp(-LIGHT_PILLAR_LAMBDA * tmp.depth);
            tmp.key = tmp.depth;
        }
        else if e.shape == 6 {
            var data: Cylinder;
            data.base = e;
            let m = uniforms.modelViewProjectionMatrix * data.base.transform;
            let m_inv = inverse(m);
            var _u: vec4f = m_inv * vec4<f32>(f32(pixelX) / f32(uniforms.screenWidth) * 2f - 1f, f32(pixelY) / f32(uniforms.screenHeight) * 2f - 1f, 1, 1);
            _u /= _u.w;
            var _v: vec4f = m_inv * vec4<f32>(0, 0, 0, 1);
            _v /= _v.w;
            let u: vec3f = (_u - _v).xyz;
            let v: vec3f = _v.xyz;
            var solutionCount: u32 = 0;
            var solutions: array<f32, 4>;
            // 圆柱面
            {
                let ret = solve_quadratic_eqation(dot(u.xy, u.xy), 2 * dot(u.xy, v.xy), dot(v.xy, v.xy) - 1);
                if ret.hasAnswer {
                    let _p1 = u * (ret.answer.x) + v;
                    let _p2 = u * (ret.answer.y) + v;
                    if -1 <= _p1.z && _p1.z <= 1 { solutions[solutionCount] = ret.answer.x; solutionCount++; }
                    if -1 <= _p2.z && _p2.z <= 1 { solutions[solutionCount] = ret.answer.y; solutionCount++; }
                }
            }
            // 顶面和底面
            {
                let _t = (1 - v.z) / u.z;
                let _p = u * _t + v;
                if dot(_p.xy, _p.xy) <= 1 { solutions[solutionCount] = _t; solutionCount++; }
            }
            {
                let _t = (-1 - v.z) / u.z;
                let _p = u * _t + v;
                if dot(_p.xy, _p.xy) <= 1 { solutions[solutionCount] = _t; solutionCount++; }
            }
            if solutionCount < 2 { continue; }
            let _p1 = u * solutions[0] + v;
            let _p2 = u * solutions[1] + v;
            let p1 = uniforms.modelViewMatrix * data.base.transform * vec4f(_p1, 1);
            let p2 = uniforms.modelViewMatrix * data.base.transform * vec4f(_p2, 1);
            var d1 = -p1.z / p1.w;
            var d2 = -p2.z / p2.w;
            if d1 > d2 { let _d = d1; d1 = d2; d2 = _d; }
            tmp.depth = d1;
            tmp.length = d2 - d1;
            //tmp.key = tmp.density * exp(-LIGHT_PILLAR_LAMBDA * tmp.depth);
            tmp.key = tmp.depth;
        }
        var pos = sampleCount;
        if sampleCount < STROKE_MAX_COUNT { sampleCount++; }
        while pos > 0 {
            if tmp.key < samples[pos - 1].key { samples[pos] = samples[pos - 1]; pos--; } else { break; }
        }
        samples[pos] = tmp;
    }
    if sampleCount == 0 { return; }
    var frags: array<LightPillar, STROKE_MAX_COUNT_MUL_2>;
    var pairs: array<Pair, STROKE_MAX_COUNT_MUL_2>;
    var bitset: array<bool, STROKE_MAX_COUNT>;
    var buf: array<u32, STROKE_MAX_COUNT>;
    for (var i: u32 = 0; i < sampleCount; i++) {
        bitset[i] = false;
        pairs[i * 2    ].key = samples[i].depth;
        pairs[i * 2    ].value = i;
        pairs[i * 2 + 1].key = samples[i].depth + samples[i].length;
        pairs[i * 2 + 1].value = i;
    }
    for (var i: u32 = 0; i < sampleCount * 2; i++) {
        for (var j: u32 = i + 1; j < sampleCount * 2; j++) {
            if pairs[i].key > pairs[j].key { var t = pairs[i]; pairs[i] = pairs[j]; pairs[j] = t; }
        }
    }
    var fragCount: u32 = 0;
    if COMPOSITION_METHOD == COMPOSITION_METHOD_MAX {
        for (var i: u32 = 0; i < sampleCount * 2; i++) {
            if i > 0 {
                var k: i32 = -1;
                for (var j: i32 = 0; j < i32(sampleCount); j++) {
                    if bitset[j] && (k == -1 || samples[j].density > samples[k].density) { k = j; }
                }
                if k != -1 {
                    frags[fragCount].density = samples[k].density;
                    frags[fragCount].color = samples[k].color;
                    frags[fragCount].depth = pairs[i - 1].key;
                    frags[fragCount].length = pairs[i].key - pairs[i - 1].key;
                    fragCount++;
                }
            }
            bitset[pairs[i].value] = !bitset[pairs[i].value];
        }
    } else if COMPOSITION_METHOD == COMPOSITION_METHOD_SOFTMAX {
        for (var i: u32 = 0; i < sampleCount * 2; i++) {
            if i > 0 {
                var sum: f32 = 0;
                var frag: LightPillar;
                frag.depth = pairs[i - 1].key;
                frag.length = pairs[i].key - pairs[i - 1].key;
                frag.density = 0;
                frag.color = vec3f(0);
                for (var j: u32 = 0; j < sampleCount; j++) {
                    if bitset[j] {
                        let alpha = 1.0f;
                        let w = exp(alpha / COMPOSITION_METHOD_SOFTMAX_TAO);
                        sum += w;
                        frag.color += w * samples[j].color;
                        frag.density += w * samples[j].density;
                    }
                }
                if sum > 0 {
                    frag.color /= sum;
                    frag.density /= sum;
                    frags[fragCount] = frag;
                    fragCount++;
                }
            }
            bitset[pairs[i].value] = !bitset[pairs[i].value];
        }
    } else if COMPOSITION_METHOD == COMPOSITION_METHOD_OVERLAY {
        for (var i: u32 = 0; i < sampleCount * 2; i++) {
            if i > 0 {
                var k: i32 = -1;
                for (var j: i32 = 0; j < i32(sampleCount); j++) {
                    if bitset[j] && (k == -1 || samples[j].id > samples[k].id) { k = j; }
                }
                if k != -1 {
                    frags[fragCount].density = samples[k].density;
                    frags[fragCount].color = samples[k].color;
                    frags[fragCount].depth = pairs[i - 1].key;
                    frags[fragCount].length = pairs[i].key - pairs[i - 1].key;
                    fragCount++;
                }
            }
            bitset[pairs[i].value] = !bitset[pairs[i].value];
        }
    }
    if fragCount == 0 { return; }
    // I(s) = \sum_{n=1}^N    T(n) * (1 - exp(-sigma_n * delta_n)) * c_n    
    // where T(n) = exp(-\sum_k=1^{n-1}  sigma_k * delta_k)   delta_n = t_{n+1} = t_n
    var irradiance: vec3f = vec3f(0);
    var occlusion: f32 = 0;
    for (var i: u32 = 0; i < fragCount; i++) {
        let sigma = frags[i].density * DENSITY_SCALE;
        let delta = frags[i].length;
        let c = frags[i].color;
        irradiance += exp(occlusion) * (1 - exp(-sigma * delta)) * c;
        occlusion += -sigma * delta;
    }
    irradiance += exp(occlusion) * BACKGROUND_COLOR.xyz;
    //irradiance /= 1 - exp(occlusion);   // ref: https://arxiv.org/abs/2311.15637
    outputBuffer.pixels[pixelId] = vec4f(irradiance, 1.0f);
    //outputBuffer.pixels[pixelId] = vec4f(vec3f(-frags[4].length * 20), 1.0f);
    //outputBuffer.pixels[pixelId] = vec4f(frags[0].color, 1.0f);
    //outputBuffer.pixels[pixelId] = vec4f(vec3f(f32(fragCount) / 10), 1.0f);
}