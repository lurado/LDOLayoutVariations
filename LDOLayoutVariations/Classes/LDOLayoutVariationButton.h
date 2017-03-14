//
//  LDOLayoutVariationButton.h
//  LDOLayoutVariations
//
//  Created by Sebastian Ludwig on 13.03.2017.
//  Copyright (c) 2017 Julian Raschke und Sebastian Ludwig GbR. All rights reserved.
//

@import UIKit;
#import "LDOVariationView.h"

@interface LDOLayoutVariationButton : UIButton <LDOVariationView>

@property (nonatomic, weak) IBOutlet UIButton *targetView;

@end
