struct ColorBuffer {
    pixels: array<atomic<u32>>,
};

struct UBO {
    screenWidth: f32,
    screenHeight: f32,
    modelViewProjectionMatrix: mat4x4<f32>,
    strokeType: u32,
};

// warn: vec3<f32> size 12 but align to 16
struct Entity { transform: mat4x4<f32>, color: vec4<f32>, }; // density => color.w

struct Triangle { verts: array<vec3<f32>, 3>, };
struct Sphere { base: Entity, }; 
struct Cube { base: Entity, };
struct Tetrahedron { base: Entity, };
struct Octahedron { base: Entity, };
struct RoundCube { base: Entity, r: f32, };
struct Triprism { base: Entity, h: f32, };
struct Capsule { base: Entity, h: f32, r: f32, };

struct StrokeBuffer { data: array<f32>, };

@group(0) @binding(0) var<storage, read_write> outputColorBuffer : ColorBuffer;
@group(0) @binding(1) var<storage, read> strokeBuffer : StrokeBuffer;
@group(0) @binding(2) var<uniform> uniforms : UBO;


fn color_pixel(x: u32, y: u32, r: u32, g: u32, b: u32) {
    let pixelIndex = u32(x + y * u32(uniforms.screenWidth)) * 3u;

    atomicMin(&outputColorBuffer.pixels[pixelIndex + 0u], r);
    atomicMin(&outputColorBuffer.pixels[pixelIndex + 1u], g);
    atomicMin(&outputColorBuffer.pixels[pixelIndex + 2u], b);
}

// From: https://github.com/ssloy/tinyrenderer/wiki/Lesson-2:-Triangle-rasterization-and-back-face-culling
fn barycentric(v1: vec3<f32>, v2: vec3<f32>, v3: vec3<f32>, p: vec2<f32>) -> vec3<f32> {
    let u = cross(
        vec3<f32>(v3.x - v1.x, v2.x - v1.x, v1.x - p.x),
        vec3<f32>(v3.y - v1.y, v2.y - v1.y, v1.y - p.y)
    );

    if abs(u.z) < 1.0 {
        return vec3<f32>(-1.0, 1.0, 1.0);
    }

    return vec3<f32>(1.0 - (u.x + u.y) / u.z, u.y / u.z, u.x / u.z);
}

fn draw_triangle(v1: vec3<f32>, v2: vec3<f32>, v3: vec3<f32>) {
    let startX = u32(min(min(v1.x, v2.x), v3.x));
    let startY = u32(min(min(v1.y, v2.y), v3.y));
    let endX = u32(max(max(v1.x, v2.x), v3.x));
    let endY = u32(max(max(v1.y, v2.y), v3.y));

    for (var x: u32 = startX; x <= endX; x = x + 1u) {
        for (var y: u32 = startY; y <= endY; y = y + 1u) {
            let bc = barycentric(v1, v2, v3, vec2<f32>(f32(x), f32(y)));
            if bc.x < 0.0 || bc.y < 0.0 || bc.z < 0.0 {
                continue;
            }
            let color = (bc.x * v1.z + bc.y * v2.z + bc.z * v3.z) * 50.0 - 400.0;
            let R = color;
            let G = color;
            let B = color;
            color_pixel(x, y, u32(R), u32(G), u32(B));
        }
    }
}


fn draw_line(v1: vec3<f32>, v2: vec3<f32>) {
    let p1: vec2<f32> = v1.xy;
    let p2: vec2<f32> = v2.xy;

    let dist = i32(distance(p1, p2));
    for (var i = 0; i < dist; i = i + 1) {
        let x = u32(v1.x + f32(v2.x - v1.x) * (f32(i) / f32(dist)));
        let y = u32(v1.x + f32(v2.y - v1.y) * (f32(i) / f32(dist)));
        color_pixel(x, y, 255u, 255u, 255u);
    }
}

fn project(v: vec3<f32>) -> vec3<f32> {
    var screenPos = uniforms.modelViewProjectionMatrix * vec4<f32>(v, 1.0);
    screenPos.x = (screenPos.x / screenPos.w + 0.5) * uniforms.screenWidth;
    screenPos.y = (screenPos.y / screenPos.w + 0.5) * uniforms.screenHeight;
    return vec3<f32>(screenPos.x, screenPos.y, screenPos.w);
}

fn is_off_screen(v: vec3<f32>) -> bool {
    if v.x < 0.0 || v.x > uniforms.screenWidth || v.y < 0.0 || v.y > uniforms.screenHeight {
        return true;
    }
    return false;
}

@compute @workgroup_size(256, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if uniforms.strokeType == 0 {
        let index = global_id.x * 12u;

        var v1 = vec3<f32>(strokeBuffer.data[index + 0u], strokeBuffer.data[index + 1u], strokeBuffer.data[index + 2u]);
        var v2 = vec3<f32>(strokeBuffer.data[index + 4u], strokeBuffer.data[index + 5u], strokeBuffer.data[index + 6u]);
        var v3 = vec3<f32>(strokeBuffer.data[index + 8u], strokeBuffer.data[index + 9u], strokeBuffer.data[index + 10u]);

        v1 = project(v1);
        v2 = project(v2);
        v3 = project(v3);

        draw_triangle(v1, v2, v3);
    }
    
}


@compute @workgroup_size(256, 1)
fn clear(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let index = global_id.x * 3u;

    atomicStore(&outputColorBuffer.pixels[index + 0u], 255u);
    atomicStore(&outputColorBuffer.pixels[index + 1u], 255u);
    atomicStore(&outputColorBuffer.pixels[index + 2u], 255u);
}