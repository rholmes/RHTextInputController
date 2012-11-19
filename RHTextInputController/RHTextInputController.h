//
//  RHTextInputController.h
//  RHTextInputController
//
//  Created by Ryan Holmes on 11/18/12.
//  Copyright (c) 2012 Ryan Holmes. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface RHTextInputController : NSObject

- (id)initWithScrollView:(UIScrollView *)scrollView;

@property (strong, nonatomic) IBOutlet UIScrollView *scrollView;
@property (strong, nonatomic) IBOutletCollection(UIView) NSArray *textInputFields;
@property (strong, nonatomic) IBOutlet UISegmentedControl *fieldNavigationControl;
@property (strong, nonatomic) IBOutlet UIView *defaultInputAccessoryView;

@property (strong, nonatomic) UIView *activeField;
@property (assign, nonatomic) BOOL enabled;

- (IBAction)fieldNavigationTapped:(id)sender;
- (IBAction)inputDoneTapped:(id)sender;

@end
