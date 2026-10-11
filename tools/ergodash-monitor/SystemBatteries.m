#import "SystemBatteries.h"
#import <AppKit/AppKit.h>
#import <IOKit/ps/IOPowerSources.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static id Get(id object, NSString *key) {
    @try { return [object valueForKey:key]; } @catch (NSException *exception) { return nil; }
}
static NSString *FallbackGlyph(NSDictionary *source) {
    if ([source[@"Type"] isEqual:@"InternalBattery"]) return @"laptopcomputer";
    return @"bluetooth";
}
static NSArray *NativeDevices(CFTypeRef blob, CFArrayRef sources) {
    static void *battery, *ui;
    if (!battery) battery=dlopen("/System/Library/PrivateFrameworks/BatteryCenter.framework/BatteryCenter",RTLD_LAZY|RTLD_LOCAL);
    if (!ui) ui=dlopen("/System/Library/PrivateFrameworks/BatteryCenterUI.framework/BatteryCenterUI",RTLD_LAZY|RTLD_LOCAL);
    Class cls=NSClassFromString(@"BCBatteryDeviceController");
    SEL shared=NSSelectorFromString(@"_sharedPowerSourceController");
    Method factory=class_getClassMethod(cls,shared);
    if (!factory || !ui) return nil;
    id controller=((id(*)(id,SEL))method_getImplementation(factory))(cls,shared);
    SEL ordered=NSSelectorFromString(@"_orderedDevicesFromPowerSourcesBlob:powerSourcesList:");
    Method parser=class_getInstanceMethod([controller class],ordered);
    if (!parser) return nil;
    return ((id(*)(id,SEL,CFTypeRef,CFArrayRef))method_getImplementation(parser))(controller,ordered,blob,sources);
}

NSData *ReadSystemBatteries(void) { @autoreleasepool {
    // Unlike the precise API used by Apple's privileged extension, this API
    // works without private entitlements. 0 means all power-source types.
    static void *iokit;
    if (!iokit) iokit=dlopen("/System/Library/Frameworks/IOKit.framework/IOKit",RTLD_LAZY|RTLD_LOCAL);
    CFTypeRef(*copy)(int)=iokit?dlsym(iokit,"IOPSCopyPowerSourcesByType"):NULL;
    CFTypeRef blob=copy?copy(0):IOPSCopyPowerSourcesInfo();
    if (!blob) return nil;
    CFArrayRef sources=IOPSCopyPowerSourcesList(blob);
    if (!sources) { CFRelease(blob); return nil; }
    NSMutableArray *readings=[NSMutableArray array];
    BOOL native=NO;
    @try {
        NSArray *devices=NativeDevices(blob,sources);
        native=devices!=nil;
        if (native) {
            for (id device in devices) {
                if (![Get(device,@"connected") boolValue]) continue;
                NSNumber *charge=Get(device,@"percentCharge");
                if (!charge || charge.integerValue<0 || charge.integerValue>100) continue;
                NSString *name=Get(device,@"name");
                NSString *identifier=Get(device,@"identifier");
                if (!name.length || !identifier.length) continue;
                BOOL unused=NO;
                SEL selector=NSSelectorFromString(@"batteryWidgetGlyphName:");
                Method method=class_getInstanceMethod([device class],selector);
                NSString *glyph=method?((id(*)(id,SEL,BOOL*))method_getImplementation(method))(device,selector,&unused):nil;
                BOOL internal=[Get(device,@"internal") boolValue];
                NSMutableDictionary *reading=[@{
                    @"id":identifier,@"name":name,@"percent":charge,
                    @"charging":Get(device,@"charging")?:@NO,
                    @"lowBattery":Get(device,@"lowBattery")?:@NO,
                    @"lowPowerMode":Get(device,@"lowPowerModeActive")?:@NO,
                    @"internalBattery":@(internal),
                    @"glyph":glyph?: (internal?@"laptopcomputer":@"bluetooth")
                } mutableCopy];
                // Most glyphs are system symbols. Keep native asset imagery
                // when the framework supplies a non-system glyph.
                if (glyph && ![NSImage imageWithSystemSymbolName:glyph accessibilityDescription:nil]) {
                    NSBundle *bundle=[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/BatteryCenterUI.framework"];
                    NSImage *image=[bundle imageForResource:glyph];
                    NSData *tiff=image.TIFFRepresentation;
                    NSBitmapImageRep *bitmap=tiff?[NSBitmapImageRep imageRepWithData:tiff]:nil;
                    NSData *png=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                    if (png.length>0 && png.length<262144) reading[@"glyphPNG"]=[png base64EncodedStringWithOptions:0];
                }
                [readings addObject:reading];
            }
        }
    } @catch (NSException *exception) { native=NO; [readings removeAllObjects]; }
    if (!native) {
        // API changes should degrade to actual OS data, not a frozen device list.
        NSUInteger index=0;
        for (id source in (__bridge NSArray*)sources) {
            NSDictionary *d=(__bridge NSDictionary*)IOPSGetPowerSourceDescription(blob,(__bridge CFTypeRef)source);
            NSNumber *current=d[@"Current Capacity"],*maximum=d[@"Max Capacity"];
            if (!current || !maximum || maximum.doubleValue<=0 || [d[@"Power Source State"] isEqual:@"Off Line"]) continue;
            NSInteger percent=lround(100*current.doubleValue/maximum.doubleValue);
            if (percent<0 || percent>100) continue;
            BOOL internal=[d[@"Type"] isEqual:@"InternalBattery"];
            NSString *name=internal?@"Mac":(d[@"Name"]?:@"Bluetooth device");
            NSString *identifier=[d[@"Power Source ID"] description]?:[NSString stringWithFormat:@"%@-%lu",name,(unsigned long)index++];
            [readings addObject:@{@"id":identifier,@"name":name,@"percent":@(percent),
                @"charging":d[@"Is Charging"]?:@NO,@"lowBattery":@(percent<=20),
                @"lowPowerMode":d[@"LPM Active"]?:@NO,@"internalBattery":@(internal),@"glyph":FallbackGlyph(d)}];
        }
    }
    CFRelease(sources); CFRelease(blob);
    return [NSJSONSerialization dataWithJSONObject:@{@"devices":readings,@"nativeIcons":@(native)} options:0 error:nil];
}}
