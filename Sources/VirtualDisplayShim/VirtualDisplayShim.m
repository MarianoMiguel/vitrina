#import "VirtualDisplayShim.h"

// The CGVirtualDisplay* class declarations below describe Apple's private
// virtual display API. They are adapted (reduced to what Vitrina needs) from
// reverse-engineered declarations originally published by Khaos Tian in
// VirtualDisplayExp (2021) and carried by DeskPad
// (https://github.com/Stengo/DeskPad, MIT License, Copyright (c) 2021 Paul
// Stengel), whose approach to creating a shareable virtual monitor this shim
// follows.

@interface CGVirtualDisplayDescriptor : NSObject
@property(nonatomic) uint32_t vendorID;
@property(nonatomic) uint32_t productID;
@property(nonatomic) uint32_t serialNum;
@property(nonatomic) uint32_t maxPixelsWide;
@property(nonatomic) uint32_t maxPixelsHigh;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) CGPoint redPrimary;
@property(nonatomic) CGPoint greenPrimary;
@property(nonatomic) CGPoint bluePrimary;
@property(nonatomic) CGPoint whitePoint;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, copy) NSString *name;
@end

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(double)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property(nonatomic) BOOL hiDPI;
@property(nonatomic, copy) NSArray<CGVirtualDisplayMode *> *modes;
@end

@interface CGVirtualDisplay : NSObject
@property(nonatomic, readonly) CGDirectDisplayID displayID;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

@interface DSTVirtualDisplay ()
@property(nonatomic, strong) CGVirtualDisplay *display;
@property(nonatomic, readwrite) NSUInteger width;
@property(nonatomic, readwrite) NSUInteger height;
@property(nonatomic) NSUInteger maxWidth;
@property(nonatomic) NSUInteger maxHeight;
@end

@implementation DSTVirtualDisplay

- (nullable instancetype)initWithName:(NSString *)name
                                width:(NSUInteger)width
                               height:(NSUInteger)height
                             maxWidth:(NSUInteger)maxWidth
                            maxHeight:(NSUInteger)maxHeight
                       pixelsPerInch:(NSUInteger)pixelsPerInch
                              highDPI:(BOOL)highDPI {
    self = [super init];
    if (!self) {
        return nil;
    }

    Class descriptorClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class displayClass = NSClassFromString(@"CGVirtualDisplay");

    if (!descriptorClass || !displayClass) {
        return nil;
    }

    CGVirtualDisplayDescriptor *descriptor = [[descriptorClass alloc] init];
    descriptor.queue = dispatch_get_main_queue();
    descriptor.name = name;
    descriptor.maxPixelsWide = (uint32_t)maxWidth;
    descriptor.maxPixelsHigh = (uint32_t)maxHeight;
    descriptor.vendorID = 0x445354;
    descriptor.productID = 1;
    descriptor.serialNum = arc4random();
    descriptor.sizeInMillimeters = CGSizeMake(25.4 * width / pixelsPerInch, 25.4 * height / pixelsPerInch);

    descriptor.whitePoint = CGPointMake(0.3125, 0.3291);
    descriptor.redPrimary = CGPointMake(0.6797, 0.3203);
    descriptor.greenPrimary = CGPointMake(0.2559, 0.6983);
    descriptor.bluePrimary = CGPointMake(0.1494, 0.0557);

    CGVirtualDisplay *display = [[displayClass alloc] initWithDescriptor:descriptor];
    if (!display) {
        return nil;
    }

    _display = display;
    _maxWidth = maxWidth;
    _maxHeight = maxHeight;

    if (![self resizeToWidth:width height:height highDPI:highDPI]) {
        return nil;
    }

    return self;
}

- (BOOL)resizeToWidth:(NSUInteger)width
               height:(NSUInteger)height
              highDPI:(BOOL)highDPI {
    Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
    Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");

    if (!settingsClass || !modeClass || !self.display) {
        return NO;
    }

    // Widths/heights are pixel dimensions; CGVirtualDisplayMode takes point
    // dimensions, so hiDPI modes are halved. Offer ONLY the target mode:
    // when the current mode stays in the list, macOS keeps it instead of
    // switching, which silently defeats the resize.
    NSUInteger modeWidth = highDPI ? width / 2 : width;
    NSUInteger modeHeight = highDPI ? height / 2 : height;
    CGVirtualDisplayMode *mode = [[modeClass alloc] initWithWidth:modeWidth height:modeHeight refreshRate:60.0];
    CGVirtualDisplaySettings *settings = [[settingsClass alloc] init];
    settings.hiDPI = highDPI;
    settings.modes = @[mode];

    if (![self.display applySettings:settings]) {
        return NO;
    }

    _width = width;
    _height = height;
    return YES;
}

- (CGDirectDisplayID)displayID {
    return self.display.displayID;
}

@end
