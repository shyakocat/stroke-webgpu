struct Uniforms {
    screenWidth: f32,
    screenHeight: f32,
    enableFXAA: u32,
};

struct ColorBuffer { pixels: array<vec4f>, };

@group(0) @binding(0) var<uniform> uniforms : Uniforms;
@group(0) @binding(1) var<storage, read> outputBuffer : ColorBuffer;

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

fn raw2D(x: i32, y: i32) -> vec4f {
    if x < 0 || y < 0 || x >= i32(uniforms.screenWidth) || y >= i32(uniforms.screenHeight) { return vec4f(0); }
    let index = x + y * i32(uniforms.screenWidth);
    return outputBuffer.pixels[index];
}

fn sample2D(p: vec2f) -> vec4f {
    return raw2D(i32(p[0] * uniforms.screenWidth), i32(p[1] * uniforms.screenHeight));
}

const FXAA_REDUCE_MIN = (1.0 / 128.0);
const FXAA_REDUCE_MUL = (1.0 / 8.0);
const FXAA_SPAN_MAX = 8.0;

fn fxaa(x: i32, y: i32) -> vec4f {
    var color: vec4f;
    let inverseVP = vec2f(1.0 / uniforms.screenWidth, 1.0 / uniforms.screenHeight);
    let rgbNW: vec3f = raw2D(x - 1, y - 1).xyz;
    let rgbNE: vec3f = raw2D(x + 1, y - 1).xyz;
    let rgbSW: vec3f = raw2D(x - 1, y + 1).xyz;
    let rgbSE: vec3f = raw2D(x + 1, y + 1).xyz;
    let texColor: vec4f = raw2D(x, y);
    let rgbM: vec3f = texColor.xyz;
    let luma = vec3f(0.299, 0.587, 0.114);
    let lumaNW = dot(rgbNW, luma);
    let lumaNE = dot(rgbNE, luma);
    let lumaSW = dot(rgbSW, luma);
    let lumaSE = dot(rgbSE, luma);
    let lumaM = dot(rgbM, luma);
    let lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
    let lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));

    var dir: vec2f;
    dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
    dir.y = ((lumaNW + lumaSW) - (lumaNE + lumaSE));

    let dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * (0.25 * FXAA_REDUCE_MUL), FXAA_REDUCE_MIN);

    let rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
    dir = min(vec2f(FXAA_SPAN_MAX, FXAA_SPAN_MAX), max(vec2f(-FXAA_SPAN_MAX, -FXAA_SPAN_MAX), dir * rcpDirMin)) * inverseVP;

    let fragCoord = vec2f(f32(x), f32(y));
    let rgbA = 0.5 * (sample2D(fragCoord * inverseVP + dir * (1.0 / 3.0 - 0.5)).xyz + sample2D(fragCoord * inverseVP + dir * (2.0 / 3.0 - 0.5)).xyz);
    let rgbB = rgbA * 0.5 + 0.25 * (sample2D(fragCoord * inverseVP + dir * -0.5).xyz + sample2D(fragCoord * inverseVP + dir * 0.5).xyz);

    let lumaB = dot(rgbB, luma);
    if (lumaB < lumaMin) || (lumaB > lumaMax) {
        color = vec4(rgbA, texColor.a);
    } else {
        color = vec4(rgbB, texColor.a);
    }
    return color;
}

@fragment
fn frag_main(@builtin(position) coord: vec4<f32>) -> @location(0) vec4<f32> {
    let X = i32(floor(coord.x));
    let Y = i32(floor(coord.y));
    if uniforms.enableFXAA != 0 { return fxaa(X, Y); }
    return sample2D(coord.xy);
}