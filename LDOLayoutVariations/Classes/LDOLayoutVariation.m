//
//  LDOLayoutVariation.m
//  LDOLayoutVariations
//
//  Created by Sebastian Ludwig on 13.03.2017.
//  Copyright (c) 2017 Julian Raschke und Sebastian Ludwig GbR. All rights reserved.
//

#import "LDOLayoutVariation.h"
#import "LDOVariationView.h"

@implementation LDOLayoutVariation

+ (void)copyViewHierarchyFromRootView:(UIView<LDOVariationView> *)sourceRootView toRootView:(UIView<LDOVariationView> *)destinationRootView
{
    for (__kindof UIView *sourceSubview in sourceRootView.subviews) {
        if ([sourceSubview conformsToProtocol:@protocol(LDOVariationView)]) {
            UIView<LDOVariationView> *copy = [[sourceSubview class] new];
            
            copy.targetView = [sourceSubview targetView];
            
            [destinationRootView addSubview:copy];
            
            [self copyViewHierarchyFromRootView:sourceSubview toRootView:copy];
        }
    }
}

+ (instancetype)layoutVariationForCurrentStateBasedOnVariation:(LDOLayoutVariation *)variation
{
    UIView<LDOVariationView> *templateView = [[variation.templateView class] new];
    templateView.translatesAutoresizingMaskIntoConstraints = NO;
    templateView.frame = variation.destinationView.frame;
    templateView.targetView = variation.templateView.targetView;
    
    [self copyViewHierarchyFromRootView:variation.templateView toRootView:templateView];
    
    LDOLayoutVariation *currentState = [LDOLayoutVariation new];
    currentState.templateView = templateView;
    currentState.destinationView = variation.destinationView;
    
    NSMapTable<UIView *, UIView<LDOVariationView> *> *currentStateTargetToVariation = [NSMapTable weakToWeakObjectsMapTable];
    for (UIView<LDOVariationView> *variationView in [currentState collectVariationViews]) {
        // capture attribute state
        variationView.alpha = variationView.targetView.alpha;
        if ([variationView respondsToSelector:@selector(captureCurrentAttributes)]) {
            [variationView captureCurrentAttributes];
        }
        
        UIView *target = variationView.targetView;
#if DEBUG
        NSAssert([currentStateTargetToVariation objectForKey:target] == nil, @"Target view referenced more than once: %@", target);
#endif
        [currentStateTargetToVariation setObject:variationView forKey:target];
    }
    
    // add constraints of variation target views to current state variation views with the same target
    // this essentially caputres the current set of constraints
    NSSet<UIView *> *targetViews = [variation targetViewsFrom:[variation collectVariationViews]];
    NSArray<NSLayoutConstraint *> *targetConstraints = [variation relevantConstraintsFor:targetViews];
    NSMutableArray<NSLayoutConstraint *> *variationConstraints = [NSMutableArray new];
    for (NSLayoutConstraint *targetConstraint in targetConstraints) {
        UIView *firstItem = targetConstraint.firstItem ? [currentStateTargetToVariation objectForKey:targetConstraint.firstItem] : nil;
        UIView *secondItem = targetConstraint.secondItem ? [currentStateTargetToVariation objectForKey:targetConstraint.secondItem] : nil;
        
        NSLayoutConstraint *constraint = [NSLayoutConstraint constraintWithItem:firstItem
                                                                      attribute:targetConstraint.firstAttribute
                                                                      relatedBy:targetConstraint.relation
                                                                         toItem:secondItem
                                                                      attribute:targetConstraint.secondAttribute
                                                                     multiplier:targetConstraint.multiplier
                                                                       constant:targetConstraint.constant];
        [variationConstraints addObject:constraint];
    }
    
    [NSLayoutConstraint activateConstraints:variationConstraints];
    
    return currentState;
}

- (NSSet<UIView<LDOVariationView> *> *)collectVariationViews
{
    NSMutableSet<UIView<LDOVariationView> *> *variationViews = [NSMutableSet new];
    
    [self collectVariationViewsInto:variationViews startingWith:self.templateView];
    
    return [variationViews copy];
}

- (void)collectVariationViewsInto:(NSMutableSet<UIView<LDOVariationView> *> *)set startingWith:(UIView *)view
{
    if ([[view class] conformsToProtocol:@protocol(LDOVariationView)]) {
        UIView<LDOVariationView> *variationView = (UIView<LDOVariationView> *)view;
        if (variationView.targetView) {
            [set addObject:variationView];
        }
    }
    
    for (UIView *subview in view.subviews) {
        [self collectVariationViewsInto:set startingWith:subview];
    }
}

- (NSSet<UIView *> *)targetViewsFrom:(NSSet<UIView<LDOVariationView> *> *)variationViews
{
    NSMutableSet<UIView *> *targetViews = [NSMutableSet new];
    
    for (UIView<LDOVariationView> *variationView in variationViews) {
        UIView *targetView = variationView.targetView;
        
#ifdef DEBUG
        NSAssert(![targetViews containsObject:targetView], @"Target view referenced more than once: %@", targetView);
#endif

        [targetViews addObject:targetView];
    }
    
    return [targetViews copy];
}

- (NSArray<NSLayoutConstraint *> *)relevantConstraintsFor:(NSSet<UIView *> *)views
{
    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray new];
    
    for (UIView *view in views) {
        for (NSLayoutConstraint *constraint in view.constraints) {
            BOOL betweenViews = [views containsObject:constraint.firstItem] && [views containsObject:constraint.secondItem];
            BOOL sizeConstraint = [constraint isMemberOfClass:[NSLayoutConstraint class]] && (constraint.firstAttribute == NSLayoutAttributeHeight || constraint.firstAttribute == NSLayoutAttributeWidth);
            sizeConstraint = sizeConstraint && ![constraint.identifier containsString:@"-Encapsulated-Layout-"];
            if (betweenViews || sizeConstraint) {
                [constraints addObject:constraint];
            }
        }
    }
    
    return [constraints copy];
}

- (void)apply
{
    NSSet<UIView<LDOVariationView> *> *variationViews = [self collectVariationViews];
    
    [self applyConstraints:variationViews];
    [self applyAttributes:variationViews];
}

- (void)applyConstraints:(NSSet<UIView<LDOVariationView> *> *)variationViews
{
    NSSet<UIView *> *targetViews = [self targetViewsFrom:variationViews];
    
    // collect all constraints between target views (to be deactivated)
    NSArray<NSLayoutConstraint *> *currentConstraints = [self relevantConstraintsFor:targetViews];
    
    // re-create constraints between LDOVariationViews for target views
    NSArray<NSLayoutConstraint *> *templateConstraints = [self relevantConstraintsFor:variationViews];
    
    NSMutableArray<NSLayoutConstraint *> *newConstraints = [NSMutableArray new];
    for (NSLayoutConstraint *templateConstraint in templateConstraints) {
        UIView *firstItem = [templateConstraint.firstItem targetView];
        UIView *secondItem = [templateConstraint.secondItem targetView];
        
        NSLayoutConstraint *constraint = [NSLayoutConstraint constraintWithItem:firstItem
                                                                      attribute:templateConstraint.firstAttribute
                                                                      relatedBy:templateConstraint.relation
                                                                         toItem:secondItem
                                                                      attribute:templateConstraint.secondAttribute
                                                                     multiplier:templateConstraint.multiplier
                                                                       constant:templateConstraint.constant];
        [newConstraints addObject:constraint];
    }
    
    [NSLayoutConstraint deactivateConstraints:currentConstraints];
    [NSLayoutConstraint activateConstraints:newConstraints];
}

- (void)applyAttributes:(NSSet<UIView<LDOVariationView> *> *)variationViews
{
    for (UIView<LDOVariationView> *variationView in variationViews) {
        // common attributes are applied here so the code doesn't need to be repeated in all implementing views
        UIView *target = variationView.targetView;
        
        target.alpha = variationView.alpha;
        
        if ([variationView respondsToSelector:@selector(applyAttributes)]) {
            [variationView applyAttributes];
        }
    }
}

@end
