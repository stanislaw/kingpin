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


#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>

#import <objc/runtime.h>

#import "KPTreeControllerRework.h"

#import "KPGridClusteringAlgorithm.h"

#import "KPAnnotation.h"
#import "KPAnnotationTree.h"


static KPTreeControllerReworkConfiguration KPTreeControllerReworkDefaultConfiguration = (KPTreeControllerReworkConfiguration) {
    .gridSize = (CGSize){60.f, 60.f},
    .annotationSize = (CGSize){60.f, 60.f},
    .annotationCenterOffset = (CGPoint){30.f, 30.f},
    .animationDuration = 0.5f,
    .clusteringEnabled = YES,
};


@interface KPTreeControllerRework()

@property (nonatomic) MKMapView *mapView;
@property (nonatomic) KPAnnotationTree *annotationTree;
@property (nonatomic) MKMapRect lastRefreshedMapRect;
@property (nonatomic) MKCoordinateRegion lastRefreshedMapRegion;
@property (nonatomic) CGRect mapFrame;
@property (nonatomic, readwrite) NSArray *gridPolylines;

@end

@implementation KPTreeControllerRework

- (id)initWithMapView:(MKMapView *)mapView {
    
    self = [self init];
    
    if (self == nil) {
        return nil;
    }

    self.mapView = mapView;
    self.mapFrame = self.mapView.frame;

    self.configuration = KPTreeControllerReworkDefaultConfiguration;
    self.clusteringAlgorithm = [[KPGridClusteringAlgorithm alloc] init];
    self.clusteringAlgorithm.mapView = self.mapView;
    self.clusteringAlgorithm.controller = self;

    return self;
    
}

- (void)setAnnotations:(NSArray *)annotations {
    [self.mapView removeAnnotations:[self.annotationTree.annotations allObjects]];

    self.annotationTree = [[KPAnnotationTree alloc] initWithAnnotations:annotations];
    self.clusteringAlgorithm.annotationTree = self.annotationTree;

    [self.clusteringAlgorithm _updateVisibileMapAnnotationsOnMapView:NO];
}

- (void)refresh:(BOOL)animated {
    
    if (MKMapRectIsNull(self.lastRefreshedMapRect) || [self _mapWasZoomed] || [self _mapWasPannedSignificantly]) {
        [self.clusteringAlgorithm _updateVisibileMapAnnotationsOnMapView:animated && [self _mapWasZoomed]];

        self.lastRefreshedMapRect = self.mapView.visibleMapRect;
        self.lastRefreshedMapRegion = self.mapView.region;
    }
}

// only refresh if:
// - the map has been zoomed
// - the map has been panned significantly

- (BOOL)_mapWasZoomed {
    return (fabs(self.lastRefreshedMapRect.size.width - self.mapView.visibleMapRect.size.width) > 0.1f);
}

- (BOOL)_mapWasPannedSignificantly {
    CGPoint lastPoint = [self.mapView convertCoordinate:self.lastRefreshedMapRegion.center
                                          toPointToView:self.mapView];
    
    CGPoint currentPoint = [self.mapView convertCoordinate:self.mapView.region.center
                                             toPointToView:self.mapView];

    return
    (fabs(lastPoint.x - currentPoint.x) > self.mapFrame.size.width) ||
    (fabs(lastPoint.y - currentPoint.y) > self.mapFrame.size.height);
}


#pragma mark - Private


- (void)_animateCluster:(KPAnnotation *)cluster
         fromAnnotation:(KPAnnotation *)fromAnnotation
           toAnnotation:(KPAnnotation *)toAnnotation
             completion:(void (^)(BOOL finished))completion
{
    
    CLLocationCoordinate2D fromCoord = fromAnnotation.coordinate;
    CLLocationCoordinate2D toCoord = toAnnotation.coordinate;
    
    cluster.coordinate = fromCoord;
    
    if ([self.delegate respondsToSelector:@selector(treeController:willAnimateAnnotation:fromAnnotation:toAnnotation:)]) {
        [self.delegate treeController:self willAnimateAnnotation:cluster fromAnnotation:fromAnnotation toAnnotation:toAnnotation];
    }
    
    void (^completionDelegate)() = ^ {
        if ([self.delegate respondsToSelector:@selector(treeController:didAnimateAnnotation:fromAnnotation:toAnnotation:)]) {
            [self.delegate treeController:self didAnimateAnnotation:cluster fromAnnotation:fromAnnotation toAnnotation:toAnnotation];
        }
    };
    
    void (^completionBlock)(BOOL finished) = ^(BOOL finished) {

        completionDelegate();
        
        if (completion) {
            completion(finished);
        }
    };
    
    [UIView animateWithDuration:self.configuration.animationDuration
                          delay:0.f
                        options:self.configuration.animationOptions
                     animations:^{
                         cluster.coordinate = toCoord;
                     }
                     completion:completionBlock];
    
}


@end
