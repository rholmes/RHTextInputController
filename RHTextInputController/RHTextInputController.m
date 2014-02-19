//
//  RHTextInputController.m
//  RHTextInputController
//
//  Created by Ryan Holmes on 11/18/12.
//  Copyright (c) 2012 Ryan Holmes and Olivier Larivain. All rights reserved.
//

#import "RHTextInputController.h"

static const CGFloat ANIMATION_DURATION = 0.27f;

#pragma mark - UIView+FirstResponder
@interface UIView (FirstResponder)

- (UIView *)findFirstResponder;
- (BOOL)findAndResignFirstResponder;

@end

@implementation UIView (FirstResponder)

- (UIView *)findFirstResponder
{
    if (self.isFirstResponder) {
        return self;
    }
    
    for (UIView *subView in self.subviews) {
        UIView *candidate = [subView findFirstResponder];
        if (candidate != nil)
            return candidate;
    }
    
    return nil;
}

- (BOOL)findAndResignFirstResponder
{
	UIView *responder = [self findFirstResponder];
	[responder resignFirstResponder];
    
    return responder != nil;
}


@end

#define DEFAULT_MARGIN 5.0f

@interface RHTextInputController() {
    UITapGestureRecognizer *_tapGestureRecognizer;
}


@end

@implementation RHTextInputController

#pragma mark - lifecycle
- (void)awakeFromNib
{
    self.enabled = YES;
	self.margin = DEFAULT_MARGIN;
    
	if(self.nextPreviousSegmentedControl != nil) {
		NSAssert(self.nextPreviousSegmentedControl.numberOfSegments == 2, @"Next/Previous Segmented control must have exactly 2 segments");
	}
	self.nextPreviousSegmentedControl.momentary = YES;
}

- (id) initWithScrollView:(UIScrollView *)scrollView
			  inputFields:(NSArray *)inputFields
	   inputAccessoryView:(UIView *)inputAccessoryView
			 nextPrevious:(UISegmentedControl *)nextPrevious
{
	self = [super init];
	if(self) {
		self.margin = DEFAULT_MARGIN;
		self.scrollView = scrollView;
		self.textInputFields = inputFields;
		self.defaultInputAccessoryView = inputAccessoryView;
		self.nextPreviousSegmentedControl = nextPrevious;
		self.enabled = YES;
	}
	return self;
}

- (void)dealloc
{
    self.enabled = NO;
}

- (void)setNextPreviousSegmentedControl:(UISegmentedControl *)nextPreviousSegmentedControl
{
	_nextPreviousSegmentedControl = nextPreviousSegmentedControl;
	_nextPreviousSegmentedControl.momentary = YES;
}

- (void)setEnabled:(BOOL)enabled
{
	// no change, abort
	if(_enabled == enabled) {
		return;
	}
    
	// update the ivar
    _enabled = enabled;
    
	// enable or disable the controller
    if (enabled) {
        if([self.scrollView isKindOfClass: UITableView.class] &&
		   self.nextPreviousSegmentedControl != nil && self.delegate == nil) {
			NSLog(@"[Text Input Controller] Warning: scroll view is a table and the delegate is not set, did you forget it? Next/Previous will be buggy.");
		}
        
        // set the default input accessory view for all connected fields
        for (UIView *field in self.textInputFields) {
            [self useDefaultInputAccessoryView:YES
									  forField:field];
        }
        
        // capture taps anywhere on the view's background
        _tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                        action:@selector(backgroundTapped:)];
        [_tapGestureRecognizer setCancelsTouchesInView:NO];
        [self.scrollView addGestureRecognizer:_tapGestureRecognizer];
        
        // register for keyboard events
        [self registerForKeyboardNotifications];
		return;
    }
    
	// otherwise, do the oppose: unregister, unwire the gesture recognizer
    // and input toolbar
	[self unregisterForKeyboardNotifications];
    [self.scrollView removeGestureRecognizer:_tapGestureRecognizer];
	for (UIView *field in self.textInputFields) {
		[self useDefaultInputAccessoryView:NO
								  forField:field];
	}
}

#pragma mark - Making the current field visible
- (void)makeFirstResponderVisible
{
	UIView *firstResponder = [self.scrollView findFirstResponder];
    
    if (firstResponder)
    {
        CGRect firstResponderRect = [self.scrollView convertRect:firstResponder.frame
                                                        fromView:firstResponder.superview];
        [self.scrollView scrollRectToVisible:firstResponderRect animated:YES];
    }
}

#pragma mark - Dismissing the view
- (IBAction)done:(id)sender
{
	[self.scrollView findAndResignFirstResponder];
}

#pragma mark - cycling through fields
- (IBAction)nextPreviousTapped:(id)sender
{
	if(self.nextPreviousSegmentedControl.selectedSegmentIndex == 0) {
		[self previous:sender];
	} else {
		[self next:sender];
	}
}

- (IBAction)next:(id)sender
{
	// get the first responder
	UIView *firstResponder = [self.scrollView findFirstResponder];
	if(firstResponder == nil) {
		return;
	}
    
	// find the index
	NSInteger index = [self.textInputFields indexOfObject:firstResponder];
    NSInteger nextIndex = index + 1;
    if (nextIndex >= [self.textInputFields count]) {
        return;
    }
    
	// grab the next field, make it first responder and scroll if needed
	UIView *nextField = [self.textInputFields objectAtIndex:nextIndex];
	[nextField becomeFirstResponder];
    
	[self makeFirstResponderVisible];
}

- (IBAction)previous:(id)sender
{
	// get the first responder
	UIView *firstResponder = [self.scrollView findFirstResponder];
	if(firstResponder == nil) {
		return;
	}
    
	// find the index
	NSInteger index = [self.textInputFields indexOfObject:firstResponder];
    NSInteger previousIndex = index - 1;
    if (previousIndex < 0 || previousIndex >= [self.textInputFields count]) {
        return;
    }
    
	// grab the previous field, make it first responder and scroll if needed
	UIView *nextField = [self.textInputFields objectAtIndex:previousIndex];
	[nextField becomeFirstResponder];
    
	[self makeFirstResponderVisible];
}

- (void)updateNextPreviousButtons
{
	UIView *firstResponder = [self.scrollView findFirstResponder];
	NSInteger index = [self.textInputFields indexOfObject:firstResponder];
    
	// first segment is enabled if the index is beyond 0
	[self.nextPreviousSegmentedControl setEnabled:index > 0
								forSegmentAtIndex:0];
	// next is enabled if we have one more element after the current one
	[self.nextPreviousSegmentedControl setEnabled:index < (self.textInputFields.count - 1)
								forSegmentAtIndex:1];
}

#pragma mark - Registering for keyboard events
- (void)registerForKeyboardNotifications
{
	// meh. Booor-iiiing!
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self
			   selector:@selector(keyboardWillShow:)
				   name:UIKeyboardWillShowNotification
				 object:nil];
    
    [center addObserver:self
			   selector:@selector(keyboardWillHide:)
				   name:UIKeyboardWillHideNotification
				 object:nil];
}

- (void)unregisterForKeyboardNotifications
{
	// Yawn.
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self
					  name:UIKeyboardWillShowNotification
					object:nil];
    
    [center removeObserver:self
					  name:UIKeyboardWillHideNotification
					object:nil];
}

#pragma mark - Responding to keyboard notifications
- (void) keyboardWillShow:(NSNotification *)notification
{
    NSDictionary* info = [notification userInfo];
    CGSize kbSize = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue].size;
    CGFloat kbHeight = 0.0f;
    
    UIInterfaceOrientation currentOrientation = [[UIApplication sharedApplication] statusBarOrientation];
    if ((currentOrientation == UIInterfaceOrientationLandscapeLeft) || (currentOrientation == UIInterfaceOrientationLandscapeRight))
    {
        kbHeight = kbSize.width;
    }
    else
    {
        kbHeight = kbSize.height;
    }
    
    
    UIEdgeInsets contentInsets = UIEdgeInsetsMake(0.0, 0.0, kbHeight, 0.0);
    self.scrollView.contentInset = contentInsets;
    self.scrollView.scrollIndicatorInsets = contentInsets;
    
	[self makeFirstResponderVisible];
}

- (void)keyboardWillHide:(NSNotification *)notification
{
	double duration = [[notification.userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{
        UIEdgeInsets contentInsets = UIEdgeInsetsZero;
        self.scrollView.contentInset = contentInsets;
        self.scrollView.scrollIndicatorInsets = contentInsets;
    }];
}

#pragma mark - Injecting the default accessory view

- (void)useDefaultInputAccessoryView:(BOOL)useDefault forField:(UIView *)field
{
	// does the field allow for overriding the accessory view?
	if(![field respondsToSelector:@selector(setInputAccessoryView:)]) {
		return;
	}
    
	// get a reference to the current accessory view
	UIView *existingInputAccessoryView = field.inputAccessoryView;
    
	// set or unset the field's input accessory view
	// do not touch the existing input accessory view, unless it's either not set or ours
	if (useDefault && existingInputAccessoryView == nil) {
		[field performSelector:@selector(setInputAccessoryView:) withObject:self.defaultInputAccessoryView];
	}
	if (!useDefault && existingInputAccessoryView == self.defaultInputAccessoryView) {
		[field performSelector:@selector(setInputAccessoryView:) withObject:nil];
	}
}

#pragma mark - Gesture recognizer

- (void)backgroundTapped:(UITapGestureRecognizer *)gestureRecognizer
{
    // check if this tap was inside one of the input fields
    for (UIView *view in self.textInputFields) {
        if (CGRectContainsPoint(view.bounds, [gestureRecognizer locationInView:view])) {
            return;
        }
    }
    // if it was not in any of the input fields, dismiss the keyboard
    [self.scrollView endEditing:YES];
}

@end