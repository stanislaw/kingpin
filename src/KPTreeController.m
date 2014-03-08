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

#import <objc/runtime.h>

#import "KPTreeController.h"

#import "KPAnnotation.h"
#import "KPAnnotationTree.h"

#import "NSArray+KP.h"

#import <dispatch/dispatch.h>

FOUNDATION_EXPORT uint64_t dispatch_benchmark(size_t count, void (^block)(void));

#define Benchmark(n, block) \
    do { \
        float time = (float)dispatch_benchmark(n, block); \
        printf("The block have been run %d times. Average time is: %f milliseconds\n",  n, (time / 1000000)); \
    } while (0);


@interface KPTreeController()

@property (nonatomic) MKMapView *mapView;
@property (nonatomic) KPAnnotationTree *annotationTree;
@property (nonatomic) MKMapRect lastRefreshedMapRect;
@property (nonatomic) MKCoordinateRegion lastRefreshedMapRegion;
@property (nonatomic) CGRect mapFrame;
@property (nonatomic, readwrite) NSArray *gridPolylines;

@end

@implementation KPTreeController

- (id)initWithMapView:(MKMapView *)mapView {
    
    self = [super init];
    
    if(self){
        self.mapView = mapView;
        self.mapFrame = self.mapView.frame;
        self.gridSize = CGSizeMake(60.f, 60.f);
        self.annotationSize = CGSizeMake(60, 60);
        self.annotationCenterOffset = CGPointMake(30.f, 30.f);
        self.animationDuration = 0.5f;
        self.clusteringEnabled = YES;
    }
    
    return self;
    
}

- (void)setAnnotations:(NSArray *)annotations {
    [self.mapView removeAnnotations:[self.annotationTree.annotations allObjects]];


    /*
    Benchmark(5, ^{
        self.annotationTree = [[KPAnnotationTree alloc] initWithAnnotations:annotations];
    });
     */

    self.annotationTree = [[KPAnnotationTree alloc] initWithAnnotations:annotations];

    [self _updateVisibileMapAnnotationsOnMapView:NO];
}

- (void)refresh:(BOOL)animated {
    
    if(MKMapRectIsNull(self.lastRefreshedMapRect) || [self _mapWasZoomed] || [self _mapWasPannedSignificantly]){
        [self _updateVisibileMapAnnotationsOnMapView:animated && [self _mapWasZoomed]];
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

- (void)_updateVisibileMapAnnotationsOnMapView:(BOOL)animated
{
    
    NSSet *visibleAnnotations = [self.mapView annotationsInMapRect:[self.mapView visibleMapRect]];
    
    // we initialize with a rough estimate for size, as to minimize allocations
    NSMutableArray *newClusters = [[NSMutableArray alloc] initWithCapacity:visibleAnnotations.count * 2];
    
    // updates visible map rect plus a map view's worth of padding around it
    MKMapRect bigRect = MKMapRectInset(self.mapView.visibleMapRect,
                                       -self.mapView.visibleMapRect.size.width,
                                       -self.mapView.visibleMapRect.size.height);
    
    if (MKMapRectGetHeight(bigRect) > MKMapRectGetHeight(MKMapRectWorld) ||
        MKMapRectGetWidth(bigRect) > MKMapRectGetWidth(MKMapRectWorld)) {
        bigRect = MKMapRectWorld;
    }
    
    
    // calculate the grid size in terms of MKMapPoints
    double widthPercentage = self.gridSize.width / CGRectGetWidth(self.mapView.frame);
    double heightPercentage = self.gridSize.height / CGRectGetHeight(self.mapView.frame);
    
    double widthInterval = ceil(widthPercentage * self.mapView.visibleMapRect.size.width);
    double heightInterval = ceil(heightPercentage * self.mapView.visibleMapRect.size.height);

    bigRect.origin.x -= fmod(MKMapRectGetMinX(bigRect), widthInterval);
    bigRect.origin.y -= fmod(MKMapRectGetMinY(bigRect), heightInterval);

    NSMutableArray *polylines = nil;
    
    if (self.debuggingEnabled) {
        polylines = [NSMutableArray new];
    }
    
    for(int x = bigRect.origin.x; x < bigRect.origin.x + bigRect.size.width; x += widthInterval){
        
        for(int y = bigRect.origin.y; y < bigRect.origin.y + bigRect.size.height; y += heightInterval){
            
            MKMapRect gridRect = MKMapRectMake(x, y, widthInterval, heightInterval);

            MKMapPoint totalMapPoint = MKMapPointMake(0, 0);
            NSUInteger numberOfAnnotations = 0;

            NSArray *newAnnotations = [self.annotationTree annotationsInMapRect:gridRect totalMapPoint:&totalMapPoint numberOfAnnotations:&numberOfAnnotations];

            // cluster annotations in this grid piece, if there are annotations to be clustered
            if(numberOfAnnotations > 0){
                
                // if clustring is disabled, add each annotation individually
                
                NSMutableArray *clustersToAdd = [NSMutableArray new];
                
                if (self.clusteringEnabled) {
                    KPAnnotation *a;

                    if (numberOfAnnotations == 1) {
                        a = [[KPAnnotation alloc] initWithAnnotations:newAnnotations];
                    } else {
                        a = [[KPAnnotation alloc] initWithTotalMapPoint:totalMapPoint andNumberOfAnnotations:numberOfAnnotations];
                    }
                    
                    [clustersToAdd addObject:a];
                }
                else {
                    [clustersToAdd addObjectsFromArray:[newAnnotations kp_map:^KPAnnotation *(id<MKAnnotation> a) {
                        return [[KPAnnotation alloc] initWithAnnotations:@[a]];
                    }]];
                }
                
                for (KPAnnotation *a in clustersToAdd){

                    if([self.delegate respondsToSelector:@selector(treeController:configureAnnotationForDisplay:)]){
                        [self.delegate treeController:self configureAnnotationForDisplay:a];
                    }
                    
                    [newClusters addObject:a];
                }
            }
        }
    }
    
    if (self.clusteringEnabled) {
        //newClusters = (NSMutableArray *)[self _mergeOverlappingClusters:newClusters];
    }

    [self.mapView removeAnnotations:[self.mapView.annotations kp_filter:^BOOL(id annotation) {
        return [annotation isKindOfClass:[KPAnnotation class]];
    }]];

    [self.mapView addAnnotations:newClusters];
}

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
    
    [UIView animateWithDuration:self.animationDuration
                          delay:0.f
                        options:self.animationOptions
                     animations:^{
                         cluster.coordinate = toCoord;
                     }
                     completion:completionBlock];
    
}

// a modified single-linkage cluster algorithm to merge any annotations that visually overlap
// http://en.wikipedia.org/wiki/Single-linkage_clustering
// TODO: The runtime can properly be analyzed by figuring out the maximum number of possible overlaps.

- (NSArray *)_mergeOverlappingClusters:(NSArray *)clusters {
    
    NSMutableArray *mutableClusters = [NSMutableArray arrayWithArray:clusters];
    
    BOOL hasOverlaps;
    
    do {
        
        hasOverlaps = NO;
        
        for (int i = 0; i < mutableClusters.count; i++) {
            for (int j = 0; j < mutableClusters.count; j++) {
                
                KPAnnotation *c1 = mutableClusters[i];
                KPAnnotation *c2 = mutableClusters[j];
                
                if (c1 == c2) continue;
                
                // calculate CGRects for each annotation, memoizing the coord -> point coversion as we go
                // if the two views overlap, merge them
                
                if (!c1._annotationPointInMapView) {
                    c1._annotationPointInMapView = [NSValue valueWithCGPoint:[self.mapView convertCoordinate:c1.coordinate
                                                                                               toPointToView:self.mapView]];
                }
                
                if (!c2._annotationPointInMapView) {
                    c2._annotationPointInMapView = [NSValue valueWithCGPoint:[self.mapView convertCoordinate:c2.coordinate
                                                                                               toPointToView:self.mapView]];
                }
                
                CGPoint p1 = [c1._annotationPointInMapView CGPointValue];
                CGPoint p2 = [c2._annotationPointInMapView CGPointValue];
                
                CGRect r1 = CGRectMake(p1.x - self.annotationSize.width + self.annotationCenterOffset.x,
                                       p1.y - self.annotationSize.height + self.annotationCenterOffset.y,
                                       self.annotationSize.width,
                                       self.annotationSize.height);
                
                CGRect r2 = CGRectMake(p2.x - self.annotationSize.width + self.annotationCenterOffset.x,
                                       p2.y - self.annotationSize.height + self.annotationCenterOffset.y,
                                       self.annotationSize.width,
                                       self.annotationSize.height);
                
                if (CGRectIntersectsRect(r1, r2)) {
                    
                    NSMutableSet *combinedSet = [NSMutableSet setWithSet:c1.annotations];
                    [combinedSet unionSet:c2.annotations];

                    MKMapPoint commonTotalPoint = MKMapPointMake(c1.totalMapPoint.x + c2.totalMapPoint.x, c1.totalMapPoint.y + c2.totalMapPoint.y);
                    NSUInteger commonNumberOfAnnotations = c1.numberOfAnnotations + c2.numberOfAnnotations;

                    KPAnnotation *newAnnotation = [[KPAnnotation alloc] initWithTotalMapPoint:commonTotalPoint andNumberOfAnnotations:commonNumberOfAnnotations];
                    
                    [mutableClusters removeObject:c1];
                    [mutableClusters removeObject:c2];
                    [mutableClusters addObject:newAnnotation];
                    
                    hasOverlaps = YES;
                    
                    break;
                }
                
                if (hasOverlaps) {
                    break;
                }
            }
        }
        
    } while(hasOverlaps);
    
    return mutableClusters;
}


@end
