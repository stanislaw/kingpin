//
//  KPClusterGrid.h
//  kingpin
//
//  Created by Stanislaw Pankevich on 18/04/14.
//
//

#import <Foundation/Foundation.h>

#import <MapKit/MKGeometry.h>

@class KPAnnotation;

/*
 Cell of cluster grid
  --------
 |  2   1 |
 |        |
 |  3   4 |
  --------
 */
typedef enum : unsigned char {
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
    { 0,  1},    // 0 means that to access coordinate of cell #0 (to the right from current i, j) we must add the following: col + 0, row + 1
    {-1,  1},    // 1
    {-1,  0},    // 2
    {-1, -1},    // 3
    { 0, -1},    // 4
    { 1, -1},    // 5
    { 1,  0},    // 6
    { 1,  1}     // 7
};


typedef enum {
    KPClusterGridCellEmpty  = 0,
    KPClusterGridCellSingle = 1,
    KPClusterGridCellMerged = 2,
    KPClusterGridCellMerger = 3,
    KPClusterGridCellDoNotRecluster = 4,
} KPClusterGridCellType;


typedef struct {
    MKMapRect mapRect;

    uint16_t annotationIndex;
    uint16_t storageIndex;

    KPClusterGridCellType clusterType;

    KPClusterDistributionQuadrant distributionQuadrant; // One of 0, 1, 2, 4, 8
    __unsafe_unretained KPAnnotation *annotation;
} kp_cluster_t;


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


typedef struct {
    kp_cluster_t *storage;

    uint16_t used;

    uint16_t freeIndexesCount;
    uint16_t *freeIndexes;

    struct {
        uint16_t cols;
        uint16_t rows;
    } capacity;
} kp_cluster_storage_t;


typedef struct {
    kp_cluster_t ***grid;
    kp_cluster_storage_t *storage;

    struct {
        int X;
        int Y;
    } size;
} kp_cluster_grid_t;


typedef enum {
    KPClusterMergeResultNone = 0,
    KPClusterMergeResultCurrent = 1,
    KPClusterMergeResultOther = 2,
} kp_cluster_merge_result_t;


void KPClusterStorageRealloc(kp_cluster_storage_t **storage, uint16_t cols, uint16_t rows);
void KPClusterStorageFree(kp_cluster_storage_t **storage);
kp_cluster_t * KPClusterStorageClusterAdd(kp_cluster_storage_t *storage);
void KPClusterStorageClusterRemove(kp_cluster_storage_t *storage, kp_cluster_t *cluster);
void KPClusterStorageDebug(kp_cluster_storage_t *storage);


void KPClusterGridInit(kp_cluster_grid_t **clusterGrid, NSUInteger gridSizeX, NSUInteger gridSizeY);
void KPClusterGridFree(kp_cluster_grid_t *clusterGrid);
void KPClusterGridDebug(kp_cluster_grid_t *clusterGrid);

void KPClusterDebug(kp_cluster_t *cluster);

void KPClusterGridMergeWithOldClusterGrid(kp_cluster_grid_t **clusterGrid, NSInteger offsetX, NSInteger offsetY, void(^marginalClusterCellBlock)(kp_cluster_t *clusterCell));

void KPClusterGridCopy(kp_cluster_grid_t **clusterGrid, NSInteger offsetX, NSInteger offsetY, void(^marginalClusterCellBlock)(kp_cluster_t *clusterCell));

