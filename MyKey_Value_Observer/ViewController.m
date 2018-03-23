//
//  ViewController.m
//  MyKey_Value_Observer
//
//  Created by ZTL_Sui on 2018/3/23.
//  Copyright © 2018年 ZTL_Sui. All rights reserved.
//

#import "ViewController.h"
#import "NSObject+BS_KVO.h"

@interface Message : NSObject

/** message */
@property (nonatomic, copy) NSString *text;

@end

@implementation Message

@end

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UITextField *textField;

@property (weak, nonatomic) IBOutlet UIButton *changeButton;

/** Message */
@property (nonatomic, strong) Message *message;
@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self testMethod];
}

/// use custom kvo
- (void)testMethod
{
    self.message = [Message new];
    NSString *key = NSStringFromSelector(@selector(text));
    ///                                             @"text"
    __weak typeof(self)weakSelf = self;
    [self.message bs_addObserver:self forKeyPath:key withBlock:^(id observeObj, NSString *key, id oldValue, id newValue) {
        NSLog(@"\n%@\n%@\n%@\n"
              ,observeObj, key, newValue);
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.textField.text = (NSString *)newValue;
        });
    }];
}

- (IBAction)changeValueAction:(id)sender
{
    NSArray *values = @[@"sleep",@"eating",@"playing",@"working",@"drinking"];
    NSUInteger index = arc4random_uniform((uint32_t)values.count);
    self.message.text = values[index];
}



@end
