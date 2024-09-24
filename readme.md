关于像素点颜色如何渲染

此处给出体渲染公式：

$$
C(r) = \int_{t_n}^{t_f} e^{-\int_{t_n}^t \sigma(r(s))ds}\sigma(r(t))c(r(t),d)dt
$$

离散形式：

$$
I(s) = \sum_{n=1}^N T(n)(1 - e^{-\sigma_n\delta_n})c_i, \quad T(n)\approx e^{\sum_{k=1}^{n-1}-\sigma_k\delta_k}, \quad \delta_i=t_{i+1}-t_i
$$

一个假设的结论（但这里没用到）：多个$\sigma_i,c_i$组合可以用$\sigma_0 = \sum \sigma_i,\quad c_0=\frac{\sum \sigma_i c_i}{\sigma_0}$代替。

我们在光栅化时一般取最近的着色。对于透明物体则需要排序，但是支撑不了如此大的开销。

第一个假设是，只渲染部分物体。越到后面的物体颜色占比越小，所以对物体的**深度**排序，只渲染前n个物体（n=1时即普通光栅化）。

但是考虑到体渲染与光栅化的不同。我们不应单纯地以深度为排序指标，因为可能一个密度大的点颜色占比更高。

第二个假设是，体渲染公式中的$\sigma(r(s))\equiv \lambda$。即假设全空间密度均一，也就是排除了一个深度相关项，我们可以用$\sigma \cdot e^{-\lambda \cdot depth}$作为排序权重。简单而言，密度越大，深度越小，则渲染的优先级越高。如果我们假设空间中除了物体以外空间的密度应为0，则可修改为$\sigma\cdot e^{-\lambda(depth_i-depth_0)}$，其中 $depth_0$为深度最近的一个物体的深度。