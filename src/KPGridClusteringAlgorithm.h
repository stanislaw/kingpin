//
//  KPGridClusteringAlgorithm.h
//  kingpin
//
//  Created by Stanislaw Pankevich on 12/04/14.
//
//

#import <Foundation/Foundation.h>

#import "KPClusteringAlgorithm.h"
#import "KPGridClusteringAlgorithmDelegate.h"

@class KPAnnotation, MKMapView;

@interface KPGridClusteringAlgorithm : NSObject <KPClusteringAlgorithm>
@property (weak, nonatomic) id <KPGridClusteringAlgorithmDelegate> delegate;
@property (weak, nonatomic) MKMapView *debuggingMapView;
@end



