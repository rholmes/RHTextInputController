//
//  RHTextInputController.h
//  RHTextInputController
//
//  Created by Ryan Holmes on 11/18/12.
//  Copyright (c) 2012 Ryan Holmes and Olivier Larivain. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@protocol RHTextInputControllerDelegate <NSObject>

- (NSIndexPath *)indexPathForResponder: (UIView *) responder;

@end


@interface RHTextInputController : NSObject

- (id) initWithScrollView:(UIScrollView *)scrollView
			  inputFields:(NSArray *)inputFields
	   inputAccessoryView:(UIView *)inputAccessoryView
			 nextPrevious:(UISegmentedControl *)nextPrevious;

@property (weak) IBOutlet id<RHTextInputControllerDelegate> delegate;

// the controlled scroll view
@property (nonatomic, strong) IBOutlet UIScrollView *scrollView;

// list of text fied/views that can be cycled through with next/previous button
@property (nonatomic, strong) IBOutlet IBOutletCollection(UIView) NSArray *textInputFields;

// the input accessory view. Will be injected into the text input fields if they don't have one already.
@property (nonatomic, strong) IBOutlet UIView *defaultInputAccessoryView;

// holds the next/previous field buttons
@property (nonatomic, strong) IBOutlet UISegmentedControl *nextPreviousSegmentedControl;

// turns the controller on/off.
@property (nonatomic, assign) BOOL enabled;

// minimum margin between the bottom of the first responder and the top of the input accessory view.
@property (nonatomic, assign) CGFloat margin;

// forces the current first responder to be visible. This controller can detect when the user taps on
// on a text field/view while the keyboard is already up. Call this method liberally in -textField:didBeginEditing:
// to make sure the guy will be visible.
- (void)makeFirstResponderVisible;

- (IBAction)next:(id)sender;
- (IBAction)previous:(id)sender;

@end
