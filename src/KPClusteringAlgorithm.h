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

- (void)performClusteringOfAnnotationsInMapRect:(MKMapRect)mapRect cellSize:(MKMapSize)cellSize annotationTree:(KPAnnotationTree *)annotationTree panning:(BOOL)panning newClusters:(NSArray * __autoreleasing *)newClusters oldClusters:(NSArray * __autoreleasing *)oldClusters;

@end
