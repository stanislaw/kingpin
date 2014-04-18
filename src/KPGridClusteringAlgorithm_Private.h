//
//  KPGridClusteringAlgorithm_Private.h
//  kingpin
//
//  Created by Stanislaw Pankevich on 14/04/14.
//
//

#import "KPGridClusteringAlgorithm.h"

#import "KPClusterGrid.h"

@interface KPGridClusteringAlgorithm ()

@property (assign, nonatomic) kp_cluster_grid_t *clusterGrid;
@property (assign, nonatomic) MKMapRect lastClusteredGridRect;

@end

