#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <AppKit/AppKit.h>

@interface MetalUI : NSObject
@property (nonatomic, readonly) id<MTLDevice> device;
@property (nonatomic, readonly) id<MTLCommandQueue> commandQueue;
@property (nonatomic, readonly) CAMetalLayer *metalLayer;

- (instancetype)initWithLayer:(CAMetalLayer *)layer;
- (void)render;
@end

@implementation MetalUI
- (instancetype)initWithLayer:(CAMetalLayer *)layer {
    if (self = [super init]) {
        _device = MTLCreateSystemDefaultDevice();
        _metalLayer = layer;
        _metalLayer.device = _device;
        _metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        _commandQueue = [_device newCommandQueue];
    }
    return self;
}

- (void)render {
    id<CAMetalDrawable> drawable = [_metalLayer nextDrawable];
    if (!drawable) return;

    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    MTLRenderPassDescriptor *passDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    passDescriptor.colorAttachments[0].texture = drawable.texture;
    passDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    passDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    passDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);

    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:passDescriptor];
    // Insert rendering commands here if needed
    [encoder endEncoding];

    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
}
@end

