import "@webgpu/types";

import fullscreenQuadWGSL from '../shaders/fullscreenQuad.wgsl?raw';
import computeRasterizerWGSL from '../shaders/computeRasterizer.wgsl?raw';
import { loadModel } from './loadModel.ts';

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

    const strokeData = await loadModel();

    const { addRasterizerPass, outputColorBuffer } = createRasterizerPass(device, presentationSize, strokeData);
    const { addFullscreenPass } = createFullscreenPass(device, presentationSize, presentationFormat, outputColorBuffer);

    function draw() {
        const commandEncoder = device.createCommandEncoder();

        addRasterizerPass(commandEncoder);
        addFullscreenPass(context, commandEncoder);

        device.queue.submit([commandEncoder.finish()]);

        requestAnimationFrame(draw);
    }

    draw();
}

function createFullscreenPass(device: GPUDevice, presentationSize: number[], presentationFormat: GPUTextureFormat, finalColorBuffer : any) {
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
        device.queue.writeBuffer(
            uniformBuffer,
            0,
            new Float32Array([presentationSize[0], presentationSize[1]]));

        renderPassDescriptor.colorAttachments[0].view = context.getCurrentTexture().createView();

        const cmd = commandEncoder.beginRenderPass(renderPassDescriptor)
        cmd.setPipeline(fullscreenQuadPipeline)
        cmd.setBindGroup(0, fullscreenQuadBindGroup)
        cmd.draw(6, 1, 0, 0)
        cmd.end()
    }

    return { addFullscreenPass }
}