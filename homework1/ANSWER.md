# Homework 1

1. [Shadow Mapping](#Shadow Mapping)
2. [Percentage Closer Filtering(PCF)](#Percentage Closer Filtering)
3. [Percentage Closer Soft Shadows(PCSS)](#Percentage Closer Soft Shadows)



## Shadow Mapping

在作业框架中 WebGLRender.js 中，可以看到渲染的两个 pass。

第一个 pass 绘制了 shadow map 到指定缓冲中，第二个 pass 使用 shadow map 进行渲染。

```javascript
render(){
		// ...

        for(letl =0;l <this.lights.length;l++) {
                // ...

                // Shadow pass
                if(this.lights[l].entity.hasShadowMap ==true) {
                        for(leti =0;i <this.shadowMeshes.length;i++) {
                                this.shadowMeshes[i].draw(this.camera);
                        }
                }

                // Camera pass
                for(leti =0;i <this.meshes.length;i++) {
                        this.gl.useProgram(this.meshes[i].shader.program.glShaderProgram);
                        this.gl.uniform3fv(this.meshes[i].shader.program.uniforms.uLightPos,this.lights[l].entity.lightPos);
                        this.meshes[i].draw(this.camera);
                }
        }
}

```

Shadow Map 的实现比较简单，在 phongFragment.glsl 中 main 函数处，先将 Light Space 下的 vPositionFromLight 转换到 NDC Space，然后传入 useShadowMap 函数（参数 shadowCoord）。

useShadowMap 函数中，判断当前 Fragment 的 shadowCoord，与同 xy 坐标的 Shadow map 上的值相比，是否更大即可，更大意味着当前 Fragment 在阴影中。

```glsl
void main()
{
        float visibility;

        vec3 shadowCoord = vPositionFromLight.xyz / vPositionFromLight.w;
        shadowCoord = shadowCoord.xyz * 0.5 + vec3(0.5, 0.5, 0.5); // NDC space

        visibility = useShadowMap(uShadowMap, vec4(shadowCoord, 1.0)); // shadow mapping

        vec3 phongColor = blinnPhong(); // shading

        gl_FragColor = vec4(phongColor * visibility, 1.0);
}

float useShadowMap(sampler2D shadowMap, vec4 shadowCoord)
{
        // variables
        float depthOnScene = shadowCoord.z;
        float depthOnShadowMap =unpack(texture2D(shadowMap, shadowCoord.xy));

        if (depthOnScene > depthOnShadowMap) // if in shadow. better to subtract bias
                return 0.0;
        else
                return 1.0;
}
```

效果：

![shadow mappings](https://github.com/zionFisher/GAMES202-Homework-With-Answers/blob/main/homework1/img/shadow%20map.png)



## Percentage Closer Filtering

使用 PCF 首先需要在阴影坐标的附近进行采样，作业框架提供了采样函数 poissonDiskSamples，有关泊松采样的相关知识可以参考：[泊松盘采样算法](https://www.zhihu.com/question/276554643)

我们先在 main 函数中，对阴影坐标进行采样，然后调用 PCF 函数即可。

```glsl
void main()
{
        float visibility;

        vec3 shadowCoord = vPositionFromLight.xyz / vPositionFromLight.w;
        shadowCoord = shadowCoord.xyz * 0.5+ vec3(0.5, 0.5, 0.5);// NDC space

        poissonDiskSamples(shadowCoord.xy);// poisson disk sample

        visibility = PCF(uShadowMap, vec4(shadowCoord, 1.0), 0.005); // PCF

        vec3 phongColor = blinnPhong();// shading

        gl_FragColor = vec4(phongColor * visibility, 1.0);
        // gl_FragColor = vec4(phongColor, 1.0);
}
```

此处对 PCF 函数做出了一定修改，定义了 filterSize 参数用于控制采样范围。

PCF 函数中，需要判断当前 shadowCoord 附近的所有采样点是否被遮挡（Blocked）了，统计没有被遮挡的采样点数量，其总数除以采样点总数就是当前片元的可见度（visibility）。

```glsl
// filterSize 0 ~ 1
float PCF(sampler2D shadowMap, vec4 shadowCoord, floatfilterSize)
{
        // variables
        float depthOnScene = shadowCoord.z;
        float depthOnShadowMap;
        int noBlockedCounter = 0;
        vec2 sampleCoords;

        // loop
        for(int i = 0; i < PCF_NUM_SAMPLES; ++i)
        {
                sampleCoords = shadowCoord.xy + filterSize * poissonDisk[i];
                depthOnShadowMap = unpack(texture2D(shadowMap, sampleCoords));

                if(depthOnShadowMap > depthOnScene)// if no blocked. better to subtract bias
                        noBlockedCounter++;
        }

        returnfloat(noBlockedCounter) / float(PCF_NUM_SAMPLES);
}
```

效果：

![PCF](https://github.com/zionFisher/GAMES202-Homework-With-Answers/blob/main/homework1/img/PCF.png)

可以更改 filterSize 参数以获得不同效果，filterSize 越大，阴影越模糊。



## Percentage Closer Soft Shadows
main 函数中调用 PCSS 函数：
```glsl
void main()
{
    float visibility;

    vec3 shadowCoord = vPositionFromLight.xyz / vPositionFromLight.w;
    shadowCoord = shadowCoord.xyz * 0.5 + vec3(0.5, 0.5, 0.5); // NDC space

    poissonDiskSamples(shadowCoord.xy); // poisson disk sample

    visibility = PCSS(uShadowMap, vec4(shadowCoord, 1.0)); // PCSS

    vec3 phongColor = blinnPhong(); // shading

    gl_FragColor = vec4(phongColor * visibility, 1.0);
    // gl_FragColor = vec4(phongColor, 1.0);
}
```
findBlocker 函数用于确定 blocker 平均深度
```glsl
float findBlocker(sampler2D shadowMap, vec2 uv, float zReceiver)
{
    // variables
    int blockedCounter = 0;
    float blockedDepthSum = 0.0;
    float depthOnShadowMap;
    vec2 sampleCoords;

    // loop
    for (int i = 0; i < BLOCKER_SEARCH_NUM_SAMPLES; ++i)
    {
        sampleCoords = uv + poissonDisk[i] * SM_WIDTH;
        depthOnShadowMap = unpack(texture2D(shadowMap, sampleCoords));

        if (depthOnShadowMap < EPS) // background case
            depthOnShadowMap = 1.0;

        if (depthOnShadowMap < zReceiver) // if blocked. better to subtract bias
        {
            blockedCounter++;
            blockedDepthSum += depthOnShadowMap;
        }
    }

    if (float(blockedCounter) < EPS) // no blocker case
        return 0.0;

	return blockedDepthSum / float(blockedCounter); // avg blocker size
}
```
其中 SM_WIDTH 为 shadow map 大小，我手工设置为了 LIGHT_WIDTH 的一半，而 LIGHT_WIDTH 为 0.06（不宜设置过大，因为这是归一化坐标，取值范围是0~1）。

在 PCSS 函数中，先计算平均 blocker 深度，然后计算半影大小，最后使用 PCF 计算 visibility。 MAX_PENUMBRA 是最大半影大小。
```glsl
float PCSS(sampler2D shadowMap, vec4 shadowCoord)
{
    vec2 sampleCoords = shadowCoord.xy;
    float receiverDepth = shadowCoord.z;

    // STEP 1: avgblocker depth
    float avgBlockedDepth = findBlocker(shadowMap, sampleCoords, receiverDepth);
    if (avgBlockedDepth < EPS) // no blocker case
        return 1.0;

    // STEP 2: penumbra size
    float penumbraSize = (receiverDepth - avgBlockedDepth) * float(LIGHT_WIDTH) / avgBlockedDepth;
    penumbraSize = min(penumbraSize, MAX_PENUMBRA);

    // STEP 3: filtering
    return PCF(shadowMap, shadowCoord, penumbraSize);
}
```
效果：
![PCSS](https://github.com/zionFisher/GAMES202-Homework-With-Answers/blob/main/homework1/img/PCSS.png)

可以将 NUM_SAMPLES 取更大值获得更好的效果。
NUM_SAMPLES = 100 时：
![PCSS 100](https://github.com/zionFisher/GAMES202-Homework-With-Answers/blob/main/homework1/img/PCSS100.png)