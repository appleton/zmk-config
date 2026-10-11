// Integration test against Apple's installed parser; never publish fake devices
// into the OS inventory or alter actual Bluetooth connections.
#import "../SystemBatteries.m"
int main(void) { @autoreleasepool {
    NSMutableArray *sources=[NSMutableArray array];
    for (NSInteger index=0;index<12;index++) {
        [sources addObject:@{@"Power Source ID":@(9000+index),@"Type":@"Accessory Source",
            @"Transport Type":@"Bluetooth LE",@"Accessory Category":@"Game Controller",
            @"Name":[NSString stringWithFormat:@"Previously unseen controller %ld",(long)index],
            @"Vendor ID":@65500,@"Product ID":@(60000+index),
            @"Power Source State":@"Battery Power",@"Is Present":@YES,
            @"Current Capacity":@(40+index),@"Max Capacity":@100,@"Is Charging":@NO}];
    }
    NSArray *devices=NativeDevices((__bridge CFTypeRef)sources,(__bridge CFArrayRef)sources);
    NSCAssert(devices.count==12,@"The native parser must discover every previously unseen device");
    for (id device in devices) {
        NSCAssert([Get(device,@"connected") boolValue],@"Connected fixture must be visible");
        NSInteger percent=[Get(device,@"percentCharge") integerValue];
        NSCAssert(percent>=40 && percent<=51,@"Preserve actual battery percentages");
        SEL selector=NSSelectorFromString(@"batteryWidgetGlyphName:");
        Method method=class_getInstanceMethod([device class],selector);BOOL flag=NO;
        NSString *glyph=((id(*)(id,SEL,BOOL*))method_getImplementation(method))(device,selector,&flag);
        NSCAssert([glyph isEqual:@"gamecontroller.fill"],@"Apple must select icons without known product IDs");
    }
    NSArray *empty=@[];
    NSCAssert(NativeDevices((__bridge CFTypeRef)empty,(__bridge CFArrayRef)empty).count==0,@"Removed devices must disappear");
    puts("Native discovery tests passed: 12 unknown products, OS-selected icons, current levels, removal");
}}
