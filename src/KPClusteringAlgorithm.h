//
//  KPClusteringAlgorithm.h
//  kingpin
//
//  Created by Stanislaw Pankevich on 12/04/14.
//
//

#import <Foundation/Foundation.h>

#import <MapKit/MKGeometry.h>

@class KPAnnotationTree;
@class MKMapView;
@class KPTreeControllerRework;


@protocol KPClusteringAlgorithm <NSObject>

- (NSArray *)performClusteringOfAnnotationsInMapRect:(MKMapRect)mapRect cellSize:(MKMapSize)cellSize annotationTree:(KPAnnotationTree *)annotationTree;

@end
