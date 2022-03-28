#ifdef GL_ES
precision mediump float;
#endif

// Phong related variables
uniform sampler2D uSampler;
uniform vec3 uKd;
uniform vec3 uKs;
uniform vec3 uLightPos;
uniform vec3 uCameraPos;
uniform vec3 uLightIntensity;

varying highp vec2 vTextureCoord;
varying highp vec3 vFragPos;
varying highp vec3 vNormal;

// Shadow map related variables
#define NUM_SAMPLES 100
#define BLOCKER_SEARCH_NUM_SAMPLES NUM_SAMPLES
#define PCF_NUM_SAMPLES NUM_SAMPLES
#define NUM_RINGS 10

#define EPS 1e-3
#define PI 3.141592653589793
#define PI2 6.283185307179586

// Custom constants
#define LIGHT_WIDTH 0.06
#define SM_WIDTH (LIGHT_WIDTH / 2.0)
#define MAX_PENUMBRA 0.3

uniform sampler2D uShadowMap;

varying vec4 vPositionFromLight;

highp float rand_1to1(highp float x )
{
    // -1 -1
    return fract(sin(x)*10000.0);
}

highp float rand_2to1(vec2 uv )
{
    // 0 - 1
	const highp float a = 12.9898, b = 78.233, c = 43758.5453;
	highp float dt = dot( uv.xy, vec2( a,b ) ), sn = mod( dt, PI );
	return fract(sin(sn) * c);
}

float unpack(vec4 rgbaDepth)
{
    const vec4 bitShift = vec4(1.0, 1.0 / 256.0, 1.0 / (256.0 * 256.0), 1.0 / (256.0 * 256.0 * 256.0));
    float res = dot(rgbaDepth, bitShift);

    return res;
}

vec2 poissonDisk[NUM_SAMPLES];

void poissonDiskSamples( const in vec2 randomSeed )
{
    float ANGLE_STEP = PI2 * float( NUM_RINGS ) / float( NUM_SAMPLES );
    float INV_NUM_SAMPLES = 1.0 / float( NUM_SAMPLES );

    float angle = rand_2to1( randomSeed ) * PI2;
    float radius = INV_NUM_SAMPLES;
    float radiusStep = radius;

    for( int i = 0; i < NUM_SAMPLES; i ++ )
    {
        poissonDisk[i] = vec2( cos( angle ), sin( angle ) ) * pow( radius, 0.75 );
        radius += radiusStep;
        angle += ANGLE_STEP;
    }
}

void uniformDiskSamples( const in vec2 randomSeed )
{
    float randNum = rand_2to1(randomSeed);
    float sampleX = rand_1to1( randNum ) ;
    float sampleY = rand_1to1( sampleX ) ;

    float angle = sampleX * PI2;
    float radius = sqrt(sampleY);

    for( int i = 0; i < NUM_SAMPLES; i ++ )
    {
        poissonDisk[i] = vec2( radius * cos(angle) , radius * sin(angle) );

        sampleX = rand_1to1( sampleY ) ;
        sampleY = rand_1to1( sampleX ) ;

        angle = sampleX * PI2;
        radius = sqrt(sampleY);
    }
}

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

// filterSize 0 ~ 1
float PCF(sampler2D shadowMap, vec4 shadowCoord, float filterSize)
{
    // variables
    float depthOnScene = shadowCoord.z;
    float depthOnShadowMap;
    int noBlockedCounter = 0;
    vec2 sampleCoords;

    // loop
    for (int i = 0; i < PCF_NUM_SAMPLES; ++i)
    {
        sampleCoords = shadowCoord.xy + filterSize * poissonDisk[i];
        depthOnShadowMap = unpack(texture2D(shadowMap, sampleCoords));

        if (depthOnShadowMap > depthOnScene) // if no blocked. better to subtract bias
            noBlockedCounter++;
    }

    return float(noBlockedCounter) / float(PCF_NUM_SAMPLES);
}

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

float useShadowMap(sampler2D shadowMap, vec4 shadowCoord)
{
    // variables
    float depthOnScene = shadowCoord.z;
    float depthOnShadowMap = unpack(texture2D(shadowMap, shadowCoord.xy));

    if (depthOnScene > depthOnShadowMap) // if in shadow. better to subtract bias
        return 0.0;
    else
        return 1.0;
}

vec3 blinnPhong()
{
    vec3 color = texture2D(uSampler, vTextureCoord).rgb;
    color = pow(color, vec3(2.2));

    vec3 ambient = 0.05 * color;

    vec3 lightDir = normalize(uLightPos);
    vec3 normal = normalize(vNormal);
    float diff = max(dot(lightDir, normal), 0.0);
    vec3 light_atten_coff = uLightIntensity / pow(length(uLightPos - vFragPos), 2.0);
    vec3 diffuse = diff * light_atten_coff * color;

    vec3 viewDir = normalize(uCameraPos - vFragPos);
    vec3 halfDir = normalize((lightDir + viewDir));
    float spec = pow(max(dot(halfDir, normal), 0.0), 32.0);
    vec3 specular = uKs * light_atten_coff * spec;

    vec3 radiance = (ambient + diffuse + specular);
    vec3 phongColor = pow(radiance, vec3(1.0 / 2.2));
    return phongColor;
}

void main()
{
    float visibility;

    vec3 shadowCoord = vPositionFromLight.xyz / vPositionFromLight.w;
    shadowCoord = shadowCoord.xyz * 0.5 + vec3(0.5, 0.5, 0.5); // NDC space

    poissonDiskSamples(shadowCoord.xy); // poisson disk sample

    // visibility = useShadowMap(uShadowMap, vec4(shadowCoord, 1.0)); // shadow mapping
    // visibility = PCF(uShadowMap, vec4(shadowCoord, 1.0), 0.005); // PCF
    visibility = PCSS(uShadowMap, vec4(shadowCoord, 1.0)); // PCSS

    vec3 phongColor = blinnPhong(); // shading

    gl_FragColor = vec4(phongColor * visibility, 1.0);
    // gl_FragColor = vec4(phongColor, 1.0);
}