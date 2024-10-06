# 关于路线选择（及相关BUG）

### 光栅化（未优化，目前）

每个workgroup（webgpu中叫法，同block）开256线程，每个线程处理一个图元。图元先由包围盒得出一个在画布上的矩形范围，枚举该范围内的像素，由眼睛到该像素是一条射线，推导公式计算射线与图元相交点的深度、穿透长度等数据。通过自旋锁作深度写入，目前是写入深度最小的片元（像素）。关于为何用自旋锁，因为画布是一个GPU上的Buffer，且每个像素记录了深度、颜色、密度、长度等信息，一个像素的信息大于32bit，线程安全的写入`AtomicStore`在webgpu上只支持`atomic<u32>`或`atomic<i32>`类型。而某个workgroup的写入无法控制到另外的workgroup（一个sm运行时不能控制另一个sm的锁状态），所以用workgroupBarrier或memoryBarrier没办法控制写入顺序，只能给每个像素加自旋锁。但是自旋锁貌似我在使用api时有问题，导致一用就崩溃，这个是一个BUG，如果不开锁，可能导致最终渲染结果有少许像素闪烁，自旋锁相关代码如下，自认为没有问题。

<img src="C:\Users\shy13\AppData\Roaming\Typora\typora-user-images\image-20240925171307906.png" alt="image-20240925171307906" style="zoom: 50%;" />

此外颜色计算上有相关BUG，正在解决，可能得研读学长的NeRF相关渲染怎么实现的。

### 光栅化（优化，TODO）

诚然上述是一个简单的光栅化方法，对于500个图元的乐高场景实时也绰绰有余，但是其实是有本质上问题的。比如当视角拉进，一个图元占满了整个画布，则其效率与CPU无异。所以一个优化方法是，增加并行度，用IndirectDispatch，给每个像素动态分配一个线程，这样就没问题了。可以做这个优化，但先解决颜色的BUG。

### 仿3DGS做法（实现了一半，发现了问题）

如果说光栅化的做法是在线的，3DGS就类似离线做法，对于整个场景的图元进行预处理。首先将16x16像素的画布作为一个tile，对每个tile内通过包围盒检查哪些图元在这个tile内，维护成一个list。对这个list内的图元以深度做排序，这一点说实话我在读3DGS论文时没明白这样做是为什么，但是如果假设场景中的高斯（图元）很少重叠，则这个优化是可以成立的。一个workgroup内将list读入到shared memory中用以加速，用radix sort O(n)排序，然后对一个tile内每个像素分配一个线程（workgroup=(1, 16, 16)），根据深度直接顺次计算颜色即可，同样3DGS没有考虑重叠是直接累加的。

对比光栅化，3DGS不用加锁，读入shared memory也可以加速。但其实3DGS的优化是有一个前提的，也就是场景中的图元不怎么重叠，这样才能以深度排序。否则必须每个像素都排序，那样每个像素还要维护一个小list，则会爆GPU每个线程的寄存器数量，等同读global memory没法加速。也就是这个加速的前提是**椭球、不怎么重叠**，否则深度可能反了，不是每种图元都可以这么做（三角形显然以重心排序不能这样，四面体≈三角形）。