#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface DSTVirtualDisplay : NSObject

@property(nonatomic, readonly) CGDirectDisplayID displayID;
@property(nonatomic, readonly) NSUInteger width;
@property(nonatomic, readonly) NSUInteger height;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (nullable instancetype)initWithName:(NSString *)name
                                width:(NSUInteger)width
                               height:(NSUInteger)height
                             maxWidth:(NSUInteger)maxWidth
                            maxHeight:(NSUInteger)maxHeight
                       pixelsPerInch:(NSUInteger)pixelsPerInch
                              highDPI:(BOOL)highDPI NS_DESIGNATED_INITIALIZER;

- (BOOL)resizeToWidth:(NSUInteger)width
               height:(NSUInteger)height
              highDPI:(BOOL)highDPI;

@end

NS_ASSUME_NONNULL_END
