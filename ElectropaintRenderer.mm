/*
 * ElectropaintRenderer.mm
 * Electropaint — Metal renderer
 *
 * Ported from Kent Rosenkoetter's electropaint.cpp
 * Original Obj-C++ wrapper by Douglas McInnes (2004)
 * Metal conversion (2026)
 *
 * GPL v2 or later — see gpl.txt
 */

#import "ElectropaintRenderer.h"
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <simd/simd.h>

#include <cmath>
#include <climits>
#include <cstdlib>
#include <ctime>
#include <list>
#include <algorithm>


// ---------------------------------------------------------------------------
// C++ animation state (unchanged from original)
// ---------------------------------------------------------------------------

struct color_type {
    CGFloat red, green, blue;
    color_type() : red(1), green(1), blue(1) {}
    color_type(CGFloat r, CGFloat g, CGFloat b) : red(r), green(g), blue(b) {}
    color_type(const color_type &c) : red(c.red), green(c.green), blue(c.blue) {}
};

struct wing_type {
    CGFloat radius, angle, delta_angle, z_delta;
    CGFloat roll, pitch, yaw;
    color_type color, edge_color;
    CGFloat alpha;

    wing_type() : radius(10), angle(0), delta_angle(15), z_delta(0.5),
        roll(0), pitch(0), yaw(0), color(), edge_color(), alpha(1) {}

    wing_type(CGFloat r, CGFloat a, CGFloat da, CGFloat dz,
              CGFloat ro, CGFloat p, CGFloat y,
              const color_type &c, const color_type &ec = color_type(), CGFloat al = 1)
        : radius(r), angle(a), delta_angle(da), z_delta(dz),
          roll(ro), pitch(p), yaw(y), color(c), edge_color(ec), alpha(al) {}
};

struct random_generator_type {
    CGFloat min_value, max_value;
    bool wrap;
    CGFloat max_acceleration, max_speed;
    NSUInteger stability;

    random_generator_type(CGFloat mn, CGFloat mx = 1.0, NSUInteger stab = 50,
                          bool wr = false, CGFloat msp = 0.02, CGFloat macc = 0.005)
        : min_value(mn), max_value(mx), wrap(wr),
          max_acceleration(macc), max_speed(msp), stability(stab),
          value(0), delta(0), count(INT_MAX - 1), rand_state(0) {}

    CGFloat operator()() {
        if (++count > stability) { accel = getNewAccel(); count = 0; }
        delta += accel;
        delta = std::min(delta, max_speed);
        delta = std::max(delta, -max_speed);
        value += delta;
        if (wrap)
            value = remainderf(value - min_value, max_value - min_value) + min_value;
        else {
            value = std::min(value, max_value);
            value = std::max(value, min_value);
        }
        return value;
    }

protected:
    CGFloat value, delta, accel;
    NSUInteger count, rand_state;
    CGFloat getNewAccel() {
        NSUInteger r = rand();
        CGFloat f = r / (RAND_MAX + 1.0f);
        return (f - 0.5f) * 2.0f * max_acceleration;
    }
};

static std::list<wing_type> wings;

static random_generator_type red_movement   (0.0, 1.0,  95);
static random_generator_type green_movement (0.0, 1.0,  40);
static random_generator_type blue_movement  (0.0, 1.0,  70);
static random_generator_type roll_change    (0, 360,  80, true, 0.5,   0.125);
static random_generator_type pitch_change   (0, 360,  40, true, 1.0,   0.125);
static random_generator_type yaw_change     (0, 360,  50, true, 0.75,  0.125);
static random_generator_type radius_change  (-15, 15, 150, false, 0.05,  0.005);
static random_generator_type angle_change   (0, 360, 120, true, 1,     0.025);
static random_generator_type delta_angle_change(0, 360, 80, true, 0.1,  0.01);
static random_generator_type z_delta_change (0.4, 0.7, 200, false, 0.005, 0.0005);


// ---------------------------------------------------------------------------
// Metal vertex / uniform types  (must match Shaders.metal)
// ---------------------------------------------------------------------------

struct MetalVertex   { simd_float3 position; };
struct MetalUniforms { simd_float4x4 mvpMatrix; simd_float4 color; };


// ---------------------------------------------------------------------------
// Matrix helpers
// ---------------------------------------------------------------------------

static simd_float4x4 ep_matrix_ortho(float l, float r, float b, float t, float n, float f) {
    float rl = 1.0f / (r - l);
    float tb = 1.0f / (t - b);
    float fn = 1.0f / (f - n);
    simd_float4x4 m = {0};
    m.columns[0] = {2.f*rl,            0,    0, 0};
    m.columns[1] = {0,            2.f*tb,    0, 0};
    m.columns[2] = {0,                 0,  -fn, 0};
    m.columns[3] = {-(r+l)*rl, -(t+b)*tb, -n*fn, 1};
    return m;
}

static simd_float4x4 ep_matrix_look_at(simd_float3 eye, simd_float3 center, simd_float3 up) {
    simd_float3 f = simd_normalize(center - eye);
    simd_float3 s = simd_normalize(simd_cross(f, up));
    simd_float3 u = simd_cross(s, f);
    simd_float4x4 m;
    m.columns[0] = { s.x,  u.x, -f.x, 0};
    m.columns[1] = { s.y,  u.y, -f.y, 0};
    m.columns[2] = { s.z,  u.z, -f.z, 0};
    m.columns[3] = {-simd_dot(s,eye), -simd_dot(u,eye), simd_dot(f,eye), 1};
    return m;
}

static simd_float4x4 ep_matrix_translate(float x, float y, float z) {
    simd_float4x4 m = matrix_identity_float4x4;
    m.columns[3] = {x, y, z, 1};
    return m;
}

static simd_float4x4 ep_matrix_rotate_x(float deg) {
    float a = deg * (M_PI / 180.f), c = cosf(a), s = sinf(a);
    simd_float4x4 m = {0};
    m.columns[0] = {1, 0, 0, 0};
    m.columns[1] = {0, c, s, 0};
    m.columns[2] = {0,-s, c, 0};
    m.columns[3] = {0, 0, 0, 1};
    return m;
}

static simd_float4x4 ep_matrix_rotate_y(float deg) {
    float a = deg * (M_PI / 180.f), c = cosf(a), s = sinf(a);
    simd_float4x4 m = {0};
    m.columns[0] = { c, 0,-s, 0};
    m.columns[1] = { 0, 1, 0, 0};
    m.columns[2] = { s, 0, c, 0};
    m.columns[3] = { 0, 0, 0, 1};
    return m;
}

static simd_float4x4 ep_matrix_rotate_z(float deg) {
    float a = deg * (M_PI / 180.f), c = cosf(a), s = sinf(a);
    simd_float4x4 m = {0};
    m.columns[0] = { c, s, 0, 0};
    m.columns[1] = {-s, c, 0, 0};
    m.columns[2] = { 0, 0, 1, 0};
    m.columns[3] = { 0, 0, 0, 1};
    return m;
}


// ---------------------------------------------------------------------------
// ElectropaintRenderer
// ---------------------------------------------------------------------------

@implementation ElectropaintRenderer {
    __weak NSView              *_view;
    id<MTLDevice>               _device;
    id<MTLCommandQueue>         _commandQueue;
    id<MTLRenderPipelineState>  _fillPipeline;
    id<MTLRenderPipelineState>  _edgePipeline;
    id<MTLBuffer>               _fillVertexBuffer;
    id<MTLBuffer>               _edgeVertexBuffer;
    CAMetalLayer               *_metalLayer;
    simd_float4x4               _projViewMatrix;
    BOOL                        _initialized;
}

- (instancetype)initWithView:(NSView *)view {
    self = [super init];
    if (self) {
        _view = view;
    }
    return self;
}

- (void)startRendering {
    if (_initialized) return;
    [self setupMetal];
}

- (void)stopRendering {
    _initialized = NO;
}

- (void)resize:(NSSize)size scale:(CGFloat)scale {
    if (size.width <= 0 || size.height <= 0) return;
    if (!_metalLayer) return;
    _metalLayer.frame = CGRectMake(0, 0, size.width, size.height);
    _metalLayer.contentsScale = scale;
    _metalLayer.drawableSize = CGSizeMake(size.width * scale, size.height * scale);
    [self updateProjView:size];
}

- (void)tick {
    if (!_initialized) return;
    wings.pop_back();
    wings.push_front(wing_type(
        radius_change(), angle_change(), delta_angle_change(), z_delta_change(),
        roll_change(), pitch_change(), yaw_change(),
        color_type(red_movement(), green_movement(), blue_movement())));
    [self renderFrame];
}

// ---------------------------------------------------------------------------
// Metal setup
// ---------------------------------------------------------------------------

- (void)setupMetal {
    NSView *view = _view;
    if (!view) return;

    _device = MTLCreateSystemDefaultDevice();
    if (!_device) { NSLog(@"[Electropaint] No Metal device"); return; }

    _commandQueue = [_device newCommandQueue];

    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSError *err = nil;
    id<MTLLibrary> lib = [_device newDefaultLibraryWithBundle:bundle error:&err];
    if (!lib) {
        NSLog(@"[Electropaint] Metal library error: %@", err);
        return;
    }

    id<MTLFunction> vert = [lib newFunctionWithName:@"vertexMain"];
    id<MTLFunction> frag = [lib newFunctionWithName:@"fragmentMain"];

    MTLVertexDescriptor *vd = [MTLVertexDescriptor vertexDescriptor];
    vd.attributes[0].format      = MTLVertexFormatFloat3;
    vd.attributes[0].offset      = 0;
    vd.attributes[0].bufferIndex = 0;
    vd.layouts[0].stride         = sizeof(MetalVertex);
    vd.layouts[0].stepFunction   = MTLVertexStepFunctionPerVertex;

    MTLRenderPipelineDescriptor *rpd = [[MTLRenderPipelineDescriptor alloc] init];
    rpd.vertexFunction   = vert;
    rpd.fragmentFunction = frag;
    rpd.vertexDescriptor = vd;
    rpd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

    rpd.colorAttachments[0].blendingEnabled = NO;
    _fillPipeline = [_device newRenderPipelineStateWithDescriptor:rpd error:&err];
    if (!_fillPipeline) { NSLog(@"[Electropaint] fillPipeline error: %@", err); return; }

    rpd.colorAttachments[0].blendingEnabled             = YES;
    rpd.colorAttachments[0].rgbBlendOperation           = MTLBlendOperationAdd;
    rpd.colorAttachments[0].alphaBlendOperation         = MTLBlendOperationAdd;
    rpd.colorAttachments[0].sourceRGBBlendFactor        = MTLBlendFactorSourceAlpha;
    rpd.colorAttachments[0].destinationRGBBlendFactor   = MTLBlendFactorOne;
    rpd.colorAttachments[0].sourceAlphaBlendFactor      = MTLBlendFactorOne;
    rpd.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOne;
    _edgePipeline = [_device newRenderPipelineStateWithDescriptor:rpd error:&err];
    if (!_edgePipeline) { NSLog(@"[Electropaint] edgePipeline error: %@", err); return; }

    MetalVertex fillVerts[] = {{{-1,-1,0}}, {{1,-1,0}}, {{-1,1,0}}, {{1,1,0}}};
    MetalVertex edgeVerts[] = {{{-1,-1,0}}, {{1,-1,0}}, {{1,1,0}}, {{-1,1,0}}, {{-1,-1,0}}};

    _fillVertexBuffer = [_device newBufferWithBytes:fillVerts
                                             length:sizeof(fillVerts)
                                            options:MTLResourceStorageModeShared];
    _edgeVertexBuffer = [_device newBufferWithBytes:edgeVerts
                                             length:sizeof(edgeVerts)
                                            options:MTLResourceStorageModeShared];

    [view setWantsLayer:YES];
    CAMetalLayer *ml = [CAMetalLayer layer];
    ml.device           = _device;
    ml.pixelFormat      = MTLPixelFormatBGRA8Unorm;
    ml.framebufferOnly  = YES;
    ml.frame            = view.bounds;
    CGFloat scale       = view.window ? view.window.backingScaleFactor : 2.0;
    ml.contentsScale    = scale;
    ml.drawableSize     = CGSizeMake(view.bounds.size.width * scale,
                                     view.bounds.size.height * scale);
    [view.layer addSublayer:ml];
    _metalLayer = ml;

    srand((unsigned int)time(NULL));
    wing_type newwing(radius_change(), angle_change(), delta_angle_change(), z_delta_change(),
                      roll_change(), pitch_change(), yaw_change(),
                      color_type(red_movement(), green_movement(), blue_movement()));
    wings.resize(40, newwing);

    [self updateProjView:view.bounds.size];
    _initialized = YES;
    NSLog(@"[Electropaint] Metal setup complete, device=%@", _device.name);
}

- (void)updateProjView:(NSSize)size {
    float w = size.width, h = (size.height > 0 ? size.height : 1);
    float xmult = (w > h) ? w/h : 1.0f;
    float ymult = (h > w) ? h/w : 1.0f;

    simd_float4x4 view = ep_matrix_look_at((simd_float3){0,50,50},
                                            (simd_float3){0, 0,13},
                                            (simd_float3){0, 0, 1});
    simd_float4x4 proj = ep_matrix_ortho(-20*xmult, 20*xmult,
                                          -20*ymult, 20*ymult,
                                          35, 105);
    _projViewMatrix = matrix_multiply(proj, view);
}

// ---------------------------------------------------------------------------
// Render
// ---------------------------------------------------------------------------

- (void)renderFrame {
    if (!_initialized) return;

    id<CAMetalDrawable> drawable = [_metalLayer nextDrawable];
    if (!drawable) return;

    MTLRenderPassDescriptor *rpd = [MTLRenderPassDescriptor renderPassDescriptor];
    rpd.colorAttachments[0].texture     = drawable.texture;
    rpd.colorAttachments[0].loadAction  = MTLLoadActionClear;
    rpd.colorAttachments[0].clearColor  = MTLClearColorMake(0, 0, 0, 1);
    rpd.colorAttachments[0].storeAction = MTLStoreActionStore;

    id<MTLCommandBuffer>        cmd     = [_commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [cmd renderCommandEncoderWithDescriptor:rpd];

    MTLViewport vp = {0, 0,
        (double)drawable.texture.width, (double)drawable.texture.height, 0, 1};
    [encoder setViewport:vp];

    simd_float4x4 pv = _projViewMatrix;
    float z_accum = 0.0f;
    int   count   = 0;

    for (const wing_type &wing : wings) {
        z_accum += wing.z_delta;

        simd_float4x4 model =
            matrix_multiply(ep_matrix_translate(0, 0, z_accum),
            matrix_multiply(ep_matrix_rotate_z(wing.angle + count * wing.delta_angle),
            matrix_multiply(ep_matrix_translate(wing.radius, 0, 0),
            matrix_multiply(ep_matrix_rotate_z(-wing.yaw),
            matrix_multiply(ep_matrix_rotate_y(-wing.pitch),
                            ep_matrix_rotate_x(wing.roll))))));

        simd_float4x4 mvp = matrix_multiply(pv, model);

        MetalUniforms fu = {mvp, {(float)wing.color.red,
                                  (float)wing.color.green,
                                  (float)wing.color.blue, 1.f}};
        [encoder setRenderPipelineState:_fillPipeline];
        [encoder setVertexBuffer:_fillVertexBuffer offset:0 atIndex:0];
        [encoder setVertexBytes:&fu length:sizeof(fu) atIndex:1];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];

        MetalUniforms eu = {mvp, {1.f, 1.f, 1.f, 1.f}};
        [encoder setRenderPipelineState:_edgePipeline];
        [encoder setVertexBuffer:_edgeVertexBuffer offset:0 atIndex:0];
        [encoder setVertexBytes:&eu length:sizeof(eu) atIndex:1];
        [encoder drawPrimitives:MTLPrimitiveTypeLineStrip vertexStart:0 vertexCount:5];

        count++;
    }

    [encoder endEncoding];
    [cmd presentDrawable:drawable];
    [cmd commit];
}

@end
