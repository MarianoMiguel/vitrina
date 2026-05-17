#import "VirtualDisplayShim.h"

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
@end

@implementation DSTVirtualDisplay

- (nullable instancetype)initWithName:(NSString *)name
                                width:(NSUInteger)width
                               height:(NSUInteger)height
                       pixelsPerInch:(NSUInteger)pixelsPerInch
                              highDPI:(BOOL)highDPI {
    self = [super init];
    if (!self) {
        return nil;
    }

    Class descriptorClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
    Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
    Class displayClass = NSClassFromString(@"CGVirtualDisplay");

    if (!descriptorClass || !settingsClass || !modeClass || !displayClass) {
        return nil;
    }

    CGVirtualDisplayDescriptor *descriptor = [[descriptorClass alloc] init];
    descriptor.queue = dispatch_get_main_queue();
    descriptor.name = name;
    descriptor.maxPixelsWide = (uint32_t)width;
    descriptor.maxPixelsHigh = (uint32_t)height;
    descriptor.vendorID = 0x445354;
    descriptor.productID = 1;
    descriptor.serialNum = 1;
    descriptor.sizeInMillimeters = CGSizeMake(25.4 * width / pixelsPerInch, 25.4 * height / pixelsPerInch);

    descriptor.whitePoint = CGPointMake(0.3125, 0.3291);
    descriptor.redPrimary = CGPointMake(0.6797, 0.3203);
    descriptor.greenPrimary = CGPointMake(0.2559, 0.6983);
    descriptor.bluePrimary = CGPointMake(0.1494, 0.0557);

    CGVirtualDisplay *display = [[displayClass alloc] initWithDescriptor:descriptor];
    if (!display) {
        return nil;
    }

    NSUInteger modeWidth = highDPI ? width / 2 : width;
    NSUInteger modeHeight = highDPI ? height / 2 : height;
    CGVirtualDisplayMode *mode = [[modeClass alloc] initWithWidth:modeWidth height:modeHeight refreshRate:60.0];
    CGVirtualDisplaySettings *settings = [[settingsClass alloc] init];
    settings.hiDPI = highDPI;
    settings.modes = @[mode];

    if (![display applySettings:settings]) {
        return nil;
    }

    _display = display;
    _width = width;
    _height = height;

    return self;
}

- (CGDirectDisplayID)displayID {
    return self.display.displayID;
}

@end
