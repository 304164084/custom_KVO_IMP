//
//  NSObject+BS_KVO.h
//  MyKey_Value_Observer
//
//  Created by ZTL_Sui on 2018/3/23.
//  Copyright © 2018年 ZTL_Sui. All rights reserved.
//



#import <Foundation/Foundation.h>

typedef void (^BSObservingBlock)(id observeObj,
                                 NSString *key,
                                 id oldValue,
                                 id newValue);

@interface NSObject (BS_KVO)

- (void)bs_addObserver:(NSObject *)observer
            forKeyPath:(NSString *)keyPath
             withBlock:(BSObservingBlock)block;

- (void)bs_removeObserver:(NSObject *)observer
               forKeyPath:(NSString *)keyPath;
@end
