import { mat4, vec3 } from 'gl-matrix'
//@ts-ignore
import fullscreenQuadWGSL from '../shaders/fullscreenQuad.wgsl?raw';
//@ts-ignore
import computeRasterizerWGSL from '../shaders/computeRasterizer.wgsl?raw';
import { loadModel } from './loadModel.ts';
import Stats from 'stats.js';

init();

async function init() {
    const adapter = await navigator.gpu.requestAdapter() as GPUAdapter;
    const device = await adapter.requestDevice();
    const canvas = document.querySelector("canvas") as HTMLCanvasElement;
    const context = canvas.getContext("webgpu") as GPUCanvasContext;
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;

    const devicePixelRatio = window.devicePixelRatio || 1;
    const presentationSize = [
        Math.floor(canvas.clientWidth * devicePixelRatio),
        Math.floor(canvas.clientHeight * devicePixelRatio),
    ];

    const presentationFormat = navigator.gpu.getPreferredCanvasFormat();
    context.configure({
        device,
        format: presentationFormat,
        alphaMode: "opaque"
    });

    const strokeData: Float32Array = await loadModel();

    const { addRasterizerPass, outputColorBuffer } = createRasterizerPass(device, presentationSize, strokeData);
    const { addFullscreenPass } = createFullscreenPass(device, presentationSize, presentationFormat, outputColorBuffer);

    var stats = new Stats();
    stats.showPanel( 0 ); // 0: fps, 1: ms, 2: mb, 3+: custom
    document.body.appendChild( stats.dom );

    function draw() {

        stats.begin()

        const commandEncoder = device.createCommandEncoder();

        addRasterizerPass(commandEncoder);
        addFullscreenPass(context, commandEncoder);

        device.queue.submit([commandEncoder.finish()]);

        stats.end()

        requestAnimationFrame(draw);
    }

    draw();
}

function createFullscreenPass(device: GPUDevice, presentationSize: number[], presentationFormat: GPUTextureFormat, finalColorBuffer: any) {
    const fullscreenQuadBindGroupLayout = device.createBindGroupLayout({
        entries: [
            { binding: 0, visibility: GPUShaderStage.FRAGMENT, buffer: { type: "uniform" } },
            { binding: 1, visibility: GPUShaderStage.FRAGMENT, buffer: { type: "read-only-storage" } }, // color buffer
        ]
    })

    const fullscreenQuadPipeline = device.createRenderPipeline({
        layout: device.createPipelineLayout({ bindGroupLayouts: [fullscreenQuadBindGroupLayout] }),
        vertex: {
            module: device.createShaderModule({ code: fullscreenQuadWGSL }), entryPoint: "vert_main"
        },
        fragment: {
            module: device.createShaderModule({ code: fullscreenQuadWGSL }), entryPoint: "frag_main",
            targets: [{ format: presentationFormat }]
        },
        primitive: { topology: "triangle-list" }
    })

    const uniformBufferSize = 4 * 2;    // screenWidth, screenHeight
    const uniformBuffer = device.createBuffer({
        size: uniformBufferSize,
        usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST
    })

    const fullscreenQuadBindGroup = device.createBindGroup({
        layout: fullscreenQuadBindGroupLayout,
        entries: [
            { binding: 0, resource: { buffer: uniformBuffer } },
            { binding: 1, resource: { buffer: finalColorBuffer } }
        ]
    })

    const renderPassDescriptor: GPURenderPassDescriptor | any = {
        colorAttachments: [{
            view: undefined,
            clearValue: { r: 1.0, g: 1.0, b: 1.0, a: 1.0 },
            loadOp: "clear",
            storeOp: "store"
        }]
    }

    const addFullscreenPass = (context: GPUCanvasContext, commandEncoder: GPUCommandEncoder) => {
        device.queue.writeBuffer(uniformBuffer, 0, new Float32Array([presentationSize[0], presentationSize[1]]));

        renderPassDescriptor.colorAttachments[0].view = context.getCurrentTexture().createView();

        const cmd = commandEncoder.beginRenderPass(renderPassDescriptor)
        cmd.setPipeline(fullscreenQuadPipeline)
        cmd.setBindGroup(0, fullscreenQuadBindGroup)
        cmd.draw(6, 1, 0, 0)
        cmd.end()
    }

    return { addFullscreenPass }
}


function createRasterizerPass(device: GPUDevice, presentationSize: number[], strokeData: Float32Array) {
    const [WIDTH, HEIGHT] = presentationSize
    const COLOR_CHANNELS = 3

    const NUMBER_PRE_ELEMENT = 3 * 3    // triangle, 3 vertex, 3 f32 per vertex
    const strokeCount = strokeData.length / NUMBER_PRE_ELEMENT
    const strokeBuffer = device.createBuffer({
        size: strokeData.byteLength,
        usage: GPUBufferUsage.STORAGE,
        mappedAtCreation: true,
    })
    new Float32Array(strokeBuffer.getMappedRange()).set(strokeData);
    strokeBuffer.unmap();

    const outputColorBufferSize = Uint32Array.BYTES_PER_ELEMENT * (WIDTH * HEIGHT) * COLOR_CHANNELS;
    const outputColorBuffer = device.createBuffer({ size: outputColorBufferSize, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC })

    const UBOBufferSize =
        4 * 2 +     // screenWidth, screenHeight
        4 * 16 +    // MVP
        8           // extra padding for alignment
    const UBOBuffer = device.createBuffer({ size: UBOBufferSize, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST })

    const bindGroupLayout = device.createBindGroupLayout({
        entries: [
            { binding: 0, visibility: GPUShaderStage.COMPUTE, buffer: { type: "storage" } },
            { binding: 1, visibility: GPUShaderStage.COMPUTE, buffer: { type: "read-only-storage" } },
            { binding: 2, visibility: GPUShaderStage.COMPUTE, buffer: { type: "uniform" } },
        ]
    })
    const bindGroup = device.createBindGroup({
        layout: bindGroupLayout,
        entries: [
            { binding: 0, resource: { buffer: outputColorBuffer } },
            { binding: 1, resource: { buffer: strokeBuffer } },
            { binding: 2, resource: { buffer: UBOBuffer } }
        ]
    })

    const computeRasterizerModule = device.createShaderModule({ code: computeRasterizerWGSL })
    const rasterizerPipeline = device.createComputePipeline({
        layout: device.createPipelineLayout({ bindGroupLayouts: [bindGroupLayout] }),
        compute: { module: computeRasterizerModule, entryPoint: "main" }
    })
    const clearPipeline = device.createComputePipeline({
        layout: device.createPipelineLayout({ bindGroupLayouts: [bindGroupLayout] }),
        compute: { module: computeRasterizerModule, entryPoint: "clear" }
    })

    const aspect = WIDTH / HEIGHT
    const projectionMatrix = mat4.create()
    mat4.perspective(projectionMatrix, 0.4 * Math.PI, aspect, 1, 100.0)

    const addRasterizerPass = (commandEncoder: GPUCommandEncoder) => {
        const now = Date.now() / 1000
        const viewMatrix = mat4.create()
        mat4.translate(viewMatrix, viewMatrix, vec3.fromValues(4, 2, -10))
        const modelMatrix = mat4.create()
        mat4.rotate(modelMatrix, modelMatrix, now, vec3.fromValues(0, 1, 0))
        mat4.rotate(modelMatrix, modelMatrix, Math.PI / 2, vec3.fromValues(1, 0, 0))
        const modelViewProjectionMatrix = <Float32Array>mat4.create()
        mat4.multiply(modelViewProjectionMatrix, viewMatrix, modelMatrix)
        mat4.multiply(modelViewProjectionMatrix, projectionMatrix, modelViewProjectionMatrix)

        const uniformData = [WIDTH, HEIGHT]
        const uniformTypeArray = new Float32Array(uniformData)
        device.queue.writeBuffer(UBOBuffer, 0, uniformTypeArray.buffer)
        device.queue.writeBuffer(UBOBuffer, 16, modelViewProjectionMatrix.buffer)

        const cmd = commandEncoder.beginComputePass()
        let totalTimesToRun = Math.ceil((WIDTH * HEIGHT) / 256)
        // Clear pass
        cmd.setPipeline(clearPipeline)
        cmd.setBindGroup(0, bindGroup)
        cmd.dispatchWorkgroups(totalTimesToRun)
        // Rasterizer pass
        totalTimesToRun = Math.ceil((strokeCount) / 256)
        cmd.setPipeline(rasterizerPipeline)
        cmd.setBindGroup(0, bindGroup)
        cmd.dispatchWorkgroups(totalTimesToRun)
        cmd.end()
    }

    return { addRasterizerPass, outputColorBuffer }
}