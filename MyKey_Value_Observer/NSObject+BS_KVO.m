//
//  NSObject+BS_KVO.m
//  MyKey_Value_Observer
//
//  Created by ZTL_Sui on 2018/3/23.
//  Copyright © 2018年 ZTL_Sui. All rights reserved.
//

#import "NSObject+BS_KVO.h"
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - BSObservationInfo
@interface BSObservationInfo : NSObject

@property (nonatomic, weak) NSObject *observer;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) BSObservingBlock block;

@end

@implementation BSObservationInfo

- (instancetype)initWithObserver:(NSObject *)observer Key:(NSString *)key block:(BSObservingBlock)block
{
    self = [super init];
    if (self) {
        _observer = observer;
        _key = key;
        _block = block;
    }
    return self;
}

@end

NSString *const BSClsPrefix = @"_BSKVOClassPrefix_";
NSString *const BSKVOAssociatedObServers = @"BSKVOAssociatedObServers";

static Class kvo_class(id self, SEL _cmd)
{
    return class_getSuperclass(object_getClass(self));
}

static NSString * setterForGetter(NSString *getter)
{
    if (getter.length <= 0) {
        return nil;
    }
    
    // upper case the first letter
    NSString *firstLetter = [[getter substringToIndex:1] uppercaseString];
    NSString *remainingLetters = [getter substringFromIndex:1];
    
    // add 'set' at the begining and ':' at the end
    NSString *setter = [NSString stringWithFormat:@"set%@%@:", firstLetter, remainingLetters];
    
    return setter;
}
static NSString * getterForSetter(NSString *setter)
{
    if (setter.length <=0 || ![setter hasPrefix:@"set"] || ![setter hasSuffix:@":"]) {
        return nil;
    }
    
    // remove 'set' at the begining and ':' at the end
    NSRange range = NSMakeRange(3, setter.length - 4);
    NSString *key = [setter substringWithRange:range];
    
    // lower case the first letter
    NSString *firstLetter = [[key substringToIndex:1] lowercaseString];
    key = [key stringByReplacingCharactersInRange:NSMakeRange(0, 1)
                                       withString:firstLetter];
    
    return key;
}
/// 动态添加的 setter 方法实现. 为被观察者赋值
static void kvo_setter(id self, SEL _cmd, id newValue)
{
    NSString *setterName = NSStringFromSelector(_cmd);
    NSString *getterName = getterForSetter(setterName);
    
    if (!getterName) {
        NSString *reason = [NSString stringWithFormat:@"Object %@ does not have setter %@", self, setterName];
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:reason
                                     userInfo:nil];
        return;
    }
    
    id oldValue = [self valueForKey:getterName];

    /// 获取父类对象
    struct objc_super superclazz = {
        .receiver = self,
        .super_class = class_getSuperclass(object_getClass(self))
    };
    
    // cast our pointer so the compiler won't complain
    void (*objc_msgSendSuperCasted)(void *, SEL, id) = (void *)objc_msgSendSuper;
    
    // call super's setter, which is original class's setter method
    objc_msgSendSuperCasted(&superclazz, _cmd, newValue);
    
    // look up observers and call the blocks
    NSMutableArray *observers = objc_getAssociatedObject(self, (__bridge const void *)(BSKVOAssociatedObServers));
    for (BSObservationInfo *each in observers) {
        if ([each.key isEqualToString:getterName]) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                each.block(self, getterName, oldValue, newValue);
            });
        }
    }
}

@implementation NSObject (BS_KVO)
/// 生成中间类(派生类）
- (Class)makeKvoClassWithOriginalClassName:(NSString *)clsName
{
    /// 生成派生类的类名字符串
    NSString *kvoClsName = [BSClsPrefix stringByAppendingString:clsName];
    /// 返回一个类对象
    Class kvoCls = NSClassFromString(kvoClsName);
    
    if (kvoCls) return kvoCls;
    /****************************************************************/
    /// 获取原来的类对象
    Class originalClass = object_getClass(self);
    /// 动态生成一个 kvo 类
    Class kvoClass = objc_allocateClassPair(originalClass, [kvoClsName UTF8String], 0);
    /// 获取 class 实例方法
    Method clasMethod = class_getInstanceMethod(originalClass, @selector(class));
    /// 获取 class 方法的参数、返回值
    const char *type = method_getTypeEncoding(clasMethod);
    /// 动态为 kvo 类 添加 class 方法的 kvo_class实现
    class_addMethod(kvoClass, @selector(class), (IMP)kvo_class, type);
    /// 注册动态添加的类
    objc_registerClassPair(kvoClass);
    
    return kvoClass;
}
- (BOOL)hasSelector:(SEL)selector
{
    Class class = object_getClass(self);
    unsigned int methodCount = 0;
    /// 获取类的 方法列表
    Method *methodList = class_copyMethodList(class, &methodCount);
    for (unsigned int i = 0; i<methodCount; i++) {
        SEL thisSelector = method_getName(methodList[i]);
        /// 是否含有 目标方法
        if (thisSelector == selector) {
            return YES;
        }
    }
    /// 释放
    free(methodList);
    return NO;
}

- (void)bs_addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath withBlock:(BSObservingBlock)block
{
    /// 获取被观察者的 setter 方法名
    SEL setterSelector = NSSelectorFromString(setterForGetter(keyPath));
    /// 获取 setter 方法
    Method SetterMethod = class_getInstanceMethod([self class], setterSelector);
    
    if (!SetterMethod) {
        NSString *reason = [NSString stringWithFormat:@"Object %@ does not have a setter for key %@", self, keyPath];
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:reason
                                     userInfo:nil];
        
        return;
    }
    /// 获取自身的类对象
    Class cls = object_getClass(self);
    /// 获取自身类名
    NSString *clsName = NSStringFromClass(cls);
    
    /// 生成 派生类
    if (![clsName hasPrefix:BSClsPrefix]) {
        cls = [self makeKvoClassWithOriginalClassName:clsName];
        /// 动态交换一个类
        object_setClass(self, cls);
    }
    /// 如果不存在setter 方法
    if (![self hasSelector:setterSelector]) {
        /// 获取setter 方法的返回值、参数
        const char *types = method_getTypeEncoding(SetterMethod);
        /// 动态为 cls 类 添加setter 方法的 实现
        class_addMethod(cls, setterSelector, (IMP)kvo_setter, types);
    }
    /// 初始化
    BSObservationInfo *info = [[BSObservationInfo alloc] initWithObserver:observer Key:keyPath block:block];
    /// 根据 BSKVOAssociatedObServers 获取数据
    NSMutableArray *observers = objc_getAssociatedObject(self, (__bridge const void *)(BSKVOAssociatedObServers));
    if (!observers) {
        observers = [NSMutableArray array];
        /// 动态关联绑定(添加属性)
        objc_setAssociatedObject(self, (__bridge const void *)(BSKVOAssociatedObServers), observers, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [observers addObject:info];
}

- (void)bs_removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath
{
    NSMutableArray* observers = objc_getAssociatedObject(self, (__bridge const void *)(BSKVOAssociatedObServers));
    
    BSObservationInfo *infoToRemove;
    for (BSObservationInfo* info in observers) {
        if (info.observer == observer && [info.key isEqual:keyPath]) {
            infoToRemove = info;
            break;
        }
    }
    
    [observers removeObject:infoToRemove];
}

@end
