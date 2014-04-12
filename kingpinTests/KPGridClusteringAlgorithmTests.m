//
//  kingpinTests.m
//  kingpinTests
//
//  Created by Stanislaw Pankevich on 08/03/14.
//
//

#import "TestHelpers.h"

#import "KPGridClusteringAlgorithm.h"

#import "KPAnnotationTree.h"

#import "KPGeometry.h"

#import "TestAnnotation.h"

@interface KPGridClusteringAlgorithmTests : XCTestCase
@end


@implementation KPGridClusteringAlgorithmTests

- (void)testGridClusteringAlgorithmIntegrity
{
    NSMutableArray *annotations = [NSMutableArray array];

    NSUInteger randomNumberOfAnnotations = 1 + arc4random_uniform(1000);

    for (int i = 0; i < randomNumberOfAnnotations; i++) {
        CLLocationDegrees latAdj = ((CLLocationDegrees)(arc4random_uniform(900)) / 10);
        CLLocationDegrees lngAdj = ((CLLocationDegrees)(arc4random_uniform(900)) / 10) * 2;

        TestAnnotation *a = [[TestAnnotation alloc] init];

        a.coordinate = CLLocationCoordinate2DMake(0 + latAdj,
                                                  0 + lngAdj);

        [annotations addObject:a];
    }

    KPAnnotationTree *annotationTree = [[KPAnnotationTree alloc] initWithAnnotations:annotations];

    MKMapRect randomRect = MKMapRectRandom();

    //NSArray *annotationsBySearch = [annotationTree annotationsInMapRect:randomRect];

    KPGridClusteringAlgorithm *clusteringAlgorithm = [[KPGridClusteringAlgorithm alloc] init];

    MKMapSize cellSize = MKMapSizeMake(round(randomRect.size.width / 10), round(randomRect.size.height / 10));

    NSLog(@"rect size: %f %f", randomRect.size.width, randomRect.size.height);

    NSLog(@"Cell size: %f %f", cellSize.width, cellSize.height);

    randomRect = MKMapRectNormalizeToCellSize(randomRect, cellSize);

    //NSArray *clusters = [clusteringAlgorithm performClusteringOfAnnotationsInMapRect:randomRect cellSize:cellSize annotationTree:annotationTree];

    
}

@end
