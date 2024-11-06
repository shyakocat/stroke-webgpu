# Stroke-webgpu

[Stroke-webgpu](https://github.com/shyakocat/stroke-webgpu) is a realtime viewer of [Neural3DStrokes](https://github.com/buaavrcg/Neural3DStrokes) which written in webgpu. It implement rasterization of primitives in compute shader. It can render scenes whose 3DGS gaussians is replaced with various stroke (such as ellipsoid, cube, tetrahedron, octahedron, capsule, cubic bezier…).

[Stroke-webgpu](https://github.com/shyakocat/stroke-webgpu) 是一个[Neural3DStrokes](https://github.com/buaavrcg/Neural3DStrokes) 的WebGPU实时实现，使用计算着色器，可以光栅化不同的图元（诸如椭球、长方体、四面体、八面体、三次贝塞尔曲线等）。

# Run

First of all, initialize the environment. 安装环境。

```shell
npm install
```

For a realtime viewer, run following commands. 实时渲染，运行以下脚本。

```shell
npm run dev
```

For output test images, run following commands to deploy a server, default write to `test/outputs`.  Only for windows. 输出测试图像，运行以下脚本。仅适配Windows系统。

```shell
npm run serve
```

# Problem

+ performence issues about cubic bezier (fps 10x than other elements).

# Options

+ `shaders/computeRasterizer.wgsl`: `STROKE_MAX_COUNT`, samples per pixel. 每像素采样数。
+ `src/loadModel.ts`: `import modelData from ...`, strokes scene path. 场景路径。
+ `index.html`: `<canvas style="width: ...px; height: ...px"></canvas>`, render resolution. 分辨率。
+ `serve/server.ts`: `RENDER_OUTPUT`, test render output path. 测试输出路径。
+ `src/loadModel.ts`: `PARITION_COUNT`, count of cubic bezier transform into capsules. 贝塞尔曲线分段数。
+ `shaders/computeRasterizer.wgsl`: `BACKGROUND_COLOR`, background color. 背景颜色。
