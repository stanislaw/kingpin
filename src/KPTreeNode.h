//
// Copyright 2012 Bryan Bonczek
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>


@interface KPTreeNode : NSObject

@property (nonatomic) id<MKAnnotation> annotation;
@property (nonatomic) KPTreeNode *left;
@property (nonatomic) KPTreeNode *right;
@property (nonatomic) MKMapPoint mapPoint;

@property (nonatomic) MKMapRect mapRect;
@property (nonatomic) MKMapPoint totalMapPoint;
@property (nonatomic) NSUInteger numberOfAnnotations;

@end
