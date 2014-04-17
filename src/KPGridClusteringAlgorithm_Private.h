//
//  KPGridClusteringAlgorithm_Private.h
//  kingpin
//
//  Created by Stanislaw Pankevich on 14/04/14.
//
//

#import "KPGridClusteringAlgorithm.h"

/*
 Cell of cluster grid
  --------
 |  2   1 |
 |        |
 |  3   4 |
  --------
 */
typedef enum {
    KPClusterDistributionQuadrantOne   = 1 << 0, // Cluster's point is distributed in North East direction from cell's center i.e. cluster.x > cellCenter.x && cluster.y < cellCenter.y (given MKMapPoints: 0, 0 is on north-west...)
    KPClusterDistributionQuadrantTwo   = 1 << 1,
    KPClusterDistributionQuadrantThree = 1 << 2,
    KPClusterDistributionQuadrantFour  = 1 << 3
} KPClusterDistributionQuadrant;

/*
 cluster 3      cluster 2     cluster 1
 cluster 4  (current cluster) cluster 0
 cluster 5      cluster 6     cluster 7

 2 1  2 1  2 1
 3 4  3 4  3 4

 2 1  curr 2 1
 3 4  cl.  3 4

 2 1  2 1  2 1
 3 4  3 4  3 4
 */
static const int KPClusterConformityTable[8] = {
    KPClusterDistributionQuadrantTwo   | KPClusterDistributionQuadrantThree,  // 0
    KPClusterDistributionQuadrantThree,                                       // 1
    KPClusterDistributionQuadrantThree | KPClusterDistributionQuadrantFour,   // 2
    KPClusterDistributionQuadrantFour,                                        // 3
    KPClusterDistributionQuadrantOne   | KPClusterDistributionQuadrantFour,   // 4
    KPClusterDistributionQuadrantOne,                                         // 5
    KPClusterDistributionQuadrantOne   | KPClusterDistributionQuadrantTwo,    // 6
    KPClusterDistributionQuadrantTwo,                                         // 7
};

/*
 Example: if we have cluster point distributed to first quadrant, then the only adjacent clusters we need to check are 0, 1 and 2, the rest of clusters may be skipped for this current cluster.

  -------- -------- --------
 |        |        |        |
 |  cl.3  |  cl.2  |  cl.1  |
 |        |        |        |
  -------- -------- --------
 |  2   1 |        |        |
 |  cl.4  | current|  cl.0  |  // the middle cell is the every current cluster in -mergeOverlappingClusters
 |  3   4 |        |        |
  -------- -------- --------
 |        |        |        |
 |  cl.5  |  cl.6  |  cl.7  |
 |        |        |        |
  -------- -------- --------
 */
static const int KPClusterAdjacentClustersTable[4][3] = {
    {0, 1, 2},
    {2, 3, 4},
    {4, 5, 6},
    {6, 7, 0},
};

static const int KPAdjacentClustersCoordinateDeltas[8][2] = {
    { 1,  0},    // 0 means that to access coordinate of cell #0 (to the right from current i, j) we must add the following: i + 1, j + 0
    { 1, -1},    // 1
    { 0, -1},    // 2
    {-1, -1},    // 3
    {-1,  0},    // 4
    {-1,  1},    // 5
    { 0,  1},    // 6
    { 1,  1}     // 7
};


typedef enum : unsigned char {
    KPClusterGridCellSingle = 1,
    KPClusterGridCellMerger = 2,
    KPClusterGridCellMerged = 3,
} KPClusterGridCellType;

typedef struct {
    MKMapRect mapRect;
    NSUInteger annotationIndex;
    KPClusterGridCellType clusterType;
    KPClusterDistributionQuadrant distributionQuadrant; // One of 0, 1, 2, 4, 8
    __unsafe_unretained KPAnnotation *annotation;
} kp_cluster_t;


void KPClusterGridMergeWithOldClusterGrid(kp_cluster_t ***clusterGrid, NSUInteger gridSizeX, NSUInteger gridSizeY, NSInteger offsetX, NSInteger offsetY, void(^marginalClusterCellBlock)(kp_cluster_t *clusterCell));
void KPClusterGridDebug(kp_cluster_t ***clusterGrid, NSUInteger gridSizeX, NSUInteger gridSizeY);


static inline KPClusterDistributionQuadrant KPClusterDistributionQuadrantForPointInsideMapRect(MKMapRect mapRect, MKMapPoint point) {
    MKMapPoint centerPoint = MKMapPointMake(MKMapRectGetMidX(mapRect), MKMapRectGetMidY(mapRect));

    if (point.x >= centerPoint.x) {
        if (point.y >= centerPoint.y) {
            return KPClusterDistributionQuadrantFour;
        } else {
            return KPClusterDistributionQuadrantOne;
        }
    } else {
        if (point.y >= centerPoint.y) {
            return KPClusterDistributionQuadrantThree;
        } else {
            return KPClusterDistributionQuadrantTwo;
        }
    }
}


typedef enum {
    KPClusterMergeResultNone = 0,
    KPClusterMergeResultCurrent = 1,
    KPClusterMergeResultOther = 2,
} kp_cluster_merge_result_t;


typedef struct kp_cluster_grid_size_t {
    int X;
    int Y;
} kp_cluster_grid_size_t;


@interface KPGridClusteringAlgorithm ()

@property (assign, nonatomic) kp_cluster_t *clusterStorage;
@property (assign, nonatomic) kp_cluster_t ***clusterGrid;
@property (assign, nonatomic) kp_cluster_grid_size_t gridSize;
@property (assign, nonatomic) MKMapRect lastClusteredGridRect;

- (void)_initializeClusterGridWithSizeX:(NSUInteger)gridSizeX sizeY:(NSUInteger)gridSizeY;
- (void)_freeClusterStorage;

@end

