/*
 * ElectropaintRenderer.h
 * Electropaint — Metal renderer
 *
 * Extracted from ElectropaintView.mm
 * GPL v2 or later — see gpl.txt
 */

#import <Cocoa/Cocoa.h>

@interface ElectropaintRenderer : NSObject

- (instancetype)initWithView:(NSView *)view;
- (void)startRendering;
- (void)stopRendering;
- (void)resize:(NSSize)size scale:(CGFloat)scale;
- (void)tick;

@end
