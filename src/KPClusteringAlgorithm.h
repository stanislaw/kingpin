//
//  KPClusteringAlgorithm.h
//  kingpin
//
//  Created by Stanislaw Pankevich on 12/04/14.
//
//

#import <Foundation/Foundation.h>

@class KPAnnotationTree;
@class MKMapView;
@class KPTreeControllerRework;

@protocol KPClusteringAlgorithm <NSObject>

@property (strong, nonatomic) KPAnnotationTree *annotationTree;
@property (strong, nonatomic) MKMapView *mapView;
@property (weak, nonatomic) KPTreeControllerRework *controller;

- (void)_updateVisibileMapAnnotationsOnMapView:(BOOL)animated;

@end
