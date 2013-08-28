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
	// initialized to CGRectZero since clang 4.something
	// so no need to explicitely initialize
	CGRect _lastKeyboardRect;
	CGRect _lastIntersection;
	double _lastKeyboardAnimationDuration;
	BOOL _didInsetScrollView;
	BOOL _keyboardVisible;
	BOOL _isTableView;
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

- (void)setScrollView:(UIScrollView *)scrollView
{
	_scrollView = scrollView;
	_isTableView = [scrollView isKindOfClass:UITableView.class];
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
        // register for keyboard events
        [self registerForKeyboardNotifications];
		return;
    }
    
	// otherwise, do the oppose: unregister, unwire the input toolbar
	[self unregisterForKeyboardNotifications];
	for (UIView *field in self.textInputFields) {
		[self useDefaultInputAccessoryView:NO
								  forField:field];
	}
}

#pragma mark - Making the current field visible
- (void)makeFirstResponderVisible
{
	[self makeFirstResponderVisible:NO];
}

- (void)makeFirstResponderVisible:(BOOL)forced
{
	UIView *firstResponder = [self.scrollView findFirstResponder];
	// no responder, no problem
	// same thing if we don't have a keyboard size yet.
	if(firstResponder == nil || CGRectEqualToRect(CGRectZero, _lastKeyboardRect ) ) {
		return;
	}
    
	// ok, so now, convert the last keyboard rect from its coordinate system to the scroll view's parent
	// this will make getting the intersection between the keyboard and the scroll view easier.
	// Note that the rect here actually contains the input accessory view. So we really just
	// have to convert this guy to the scroll view's parent.
	CGRect convertedKeyboardRect = [self.scrollView.window convertRect:_lastKeyboardRect
																toView:self.scrollView.superview];
    
	// we might have to inset the scroll view/scroller indicator since something is showing up.
	// The inset is actually exactly the intersection between the scroll view and the keyboard **in the scroll view's
	// parent coordinate.** We don't care at all if the keyboard doesn't overlap our scroll view.
	// It sounds stupid, but scroll views that don't extend to the bottom of the screen (think toolbar) or forms sheet
	// on iPad will make the intersection smaller than keyboard height and will throw off everything down the line.
	// No intersection, no inset.
	// No inset... No inset!
    
	// This could be made more accurate by checking if the content size is smaller than the frame, but I've been getting
	// mixed result with this approach - mostly because when that's the case, the content inset has to take the diff
	// between content size and frame size into account. It's good enough for now we'll say.
	_lastIntersection = CGRectIntersection(self.scrollView.frame, convertedKeyboardRect);
    
	// figure out where the active field is in scroll view coordinates
	CGRect convertedFieldFrame = [firstResponder.superview convertRect:firstResponder.frame
																toView:self.scrollView];
	// and don't forget to shift by the content offset to bring this back to actual screen overlap
	convertedFieldFrame = CGRectOffset(convertedFieldFrame, -self.scrollView.contentOffset.x, -self.scrollView.contentOffset.y);
	// if the active field and the keyboard intersect, we have to change the content offset
	BOOL updateContentOffset = CGRectIntersectsRect(convertedKeyboardRect, convertedFieldFrame) || (forced && [self.scrollView isKindOfClass: UITableView.class]);
    
	// make sure the next/previous buttons are properly enabled/disabled, if applicable
	[self updateNextPreviousButtons];
    
	// we don't need to touch anything, call it a day.
	if(_didInsetScrollView && !updateContentOffset) {
		return;
	}
    
	CGPoint contentOffset = self.scrollView.contentOffset;
	if(updateContentOffset) {
		// take the lowest point of the field + the margin, substract the visible part of the scroll view (i.e. scroll
		// view height minus the intersection height).
		// that's our new content offset! Yep, draw it on a piece of paper, if you don't believe me.
		CGFloat visiblScrollViewHeight = self.scrollView.frame.size.height - _lastIntersection.size.height;
		contentOffset.y = MAX(CGRectGetMaxY(convertedFieldFrame) + self.margin - visiblScrollViewHeight, 0);
	}
    
	// copy then flip the updated content inset flag
	BOOL updateContentInset = !_didInsetScrollView;
	_didInsetScrollView = YES;
    
	void (^animations)() = ^{
		if (updateContentInset) {
			// if we should be insetting, add to the existing inset. We wouldn't want ot mess existing offset
			// would we?
			UIEdgeInsets inset = self.scrollView.contentInset;
			inset.bottom += _lastIntersection.size.height;
			self.scrollView.contentInset = inset;
            
			// the inset is the same for the scroll indicators
			inset = self.scrollView.scrollIndicatorInsets;
			inset.bottom += _lastIntersection.size.height;
			self.scrollView.scrollIndicatorInsets = inset;
		}
        
		// apply content offset only if needed
		if (!updateContentOffset) {
			return ;
		}
        
		// scroll views are easy, just use the given content offset
		if(!_isTableView || self.delegate == nil) {
			[self.scrollView setContentOffset: contentOffset];
			return;
		}
		// for tables, if the delegate gave us an index path, then scroll to that
		NSIndexPath *indexPath = [self.delegate indexPathForResponder: firstResponder];
		if(indexPath == nil) {
			return;
		}
		[(UITableView *) self.scrollView scrollToRowAtIndexPath: indexPath
											   atScrollPosition: UITableViewScrollPositionNone
													   animated: NO];
	};
	[UIView animateWithDuration: _lastKeyboardAnimationDuration
					 animations: animations];
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
    
	[self makeFirstResponderVisible:YES];
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
    
	[self makeFirstResponderVisible: YES];
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
	CGRect newRect = [[notification.userInfo objectForKey: UIKeyboardFrameEndUserInfoKey] CGRectValue];
	CGRect convertedNewKeyboardRect = [self.scrollView.window convertRect:newRect
																   toView:self.scrollView.superview];
    
	CGRect convertedKeyboardRect = [self.scrollView.window convertRect:_lastKeyboardRect
																toView:self.scrollView.superview];
	if(convertedNewKeyboardRect.size.height != convertedKeyboardRect.size.height) {
		[self removeContentInset: 0.0f clearLastKeyboardRect: NO];
		_didInsetScrollView = NO;
	}
    
	// copy the target keyboard rect and the animation duration over
	_lastKeyboardRect = newRect;
	_lastKeyboardAnimationDuration = [[notification.userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    
	[self makeFirstResponderVisible];
	_keyboardVisible = YES;
}

- (void) keyboardWillHide: (NSNotification *) notification {
	double duration = [[notification.userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
	[self removeContentInset: duration clearLastKeyboardRect:YES];
}

- (void) removeContentInset:(double)duration clearLastKeyboardRect:(BOOL)clearLastKeyboardRect
{
    
	// unset the content inset and such
	void (^animations)() = ^{
		// un-apply the inset modification we made in -showCurrentField
		UIEdgeInsets inset = self.scrollView.contentInset;
		inset.bottom -= _lastIntersection.size.height;
        self.scrollView.contentInset = inset;
        
		inset = self.scrollView.scrollIndicatorInsets;
		inset.bottom -= _lastIntersection.size.height;
        self.scrollView.scrollIndicatorInsets = inset;
    };
    
	void(^completion)(BOOL) = ^(BOOL finished) {
		if(!clearLastKeyboardRect) {
			return ;
		}
		// clear the keyboard and copy the animation duration, we don't want stale data hanging around
		_lastKeyboardRect = CGRectZero;
		_lastIntersection = CGRectZero;
		_lastKeyboardAnimationDuration = 0.0f;
	};
    
    [UIView animateWithDuration:duration
					 animations:animations
					 completion:completion];
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


@end