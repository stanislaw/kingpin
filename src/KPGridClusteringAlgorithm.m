//
//  KPGridClusteringAlgorithm.m
//  kingpin
//
//  Created by Stanislaw Pankevich on 12/04/14.
//
//

#import "KPGridClusteringAlgorithm.h"

#import <MapKit/MapKit.h>

#import "KPTreeControllerRework.h"
#import "KPAnnotationTree.h"
#import "KPAnnotation.h"


#import "NSArray+KP.h"


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


typedef struct {
    MKMapRect mapRect;
    NSUInteger annotationIndex;
    BOOL merged;
    KPClusterDistributionQuadrant distributionQuadrant; // One of 0, 1, 2, 4, 8
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

- (void)initializeClusterGridWithSizeX:(NSUInteger)gridSizeX sizeY:(NSUInteger)gridSizeY;

@end


@implementation KPGridClusteringAlgorithm

- (id)init {
    self = [super init];

    if (self == nil) return nil;

    self.gridSize = (kp_cluster_grid_size_t){0, 0};

    return self;
}

- (void)dealloc {
    [self _freeClusterStorage];
}

- (void)_freeClusterStorage {
    for (int i = 0; i < self.gridSize.X; i++) {
        free(self.clusterGrid[i]);
    }

    free(self.clusterGrid);
    free(self.clusterStorage);
}

- (NSArray *)performClusteringOfAnnotationsInMapRect:(MKMapRect)mapRect cellSize:(MKMapSize)cellSize annotationTree:(KPAnnotationTree *)annotationTree panning:(BOOL)panning {
    assert(((uint32_t)mapRect.size.width  % (uint32_t)cellSize.width)  == 0);
    assert(((uint32_t)mapRect.size.height % (uint32_t)cellSize.height) == 0);

    int gridSizeX = mapRect.size.width / cellSize.width;
    int gridSizeY = mapRect.size.height / cellSize.height;

    assert(((uint32_t)mapRect.size.width % (uint32_t)cellSize.width) == 0);

    // We initialize with a rough estimate for size, as to minimize allocations.
    __block NSMutableArray *newClusters = [[NSMutableArray alloc] initWithCapacity:(gridSizeX * gridSizeY)];

    /*
     We create grid of size (gridSizeX + 2) * (gridSizeY + 2) which looks like

     NULL NULL NULL .... NULL NULL NULL
     NULL    real cluster grid     NULL
     ...         of size           ...
     NULL  (gridSizeX, gridSizeY)  NULL
     NULL NULL NULL .... NULL NULL NULL

     We will use this NULL margin in -mergeOverlappingClusters method to avoid four- or even eight-fold branching when checking boundaries of i and j coordinates
     */

    NSLog(@"Grid: (X, Y) => (%d, %d)", gridSizeX, gridSizeY);

    if ((self.clusterStorage == NULL && self.clusterGrid == NULL) || panning == NO) {
        [self initializeClusterGridWithSizeX:gridSizeX sizeY:gridSizeY];
    } else {
        assert(self.gridSize.X == gridSizeX);
        assert(self.gridSize.Y == gridSizeY);
    }


    NSUInteger clusterIndex = 0;

    NSLog(@"Grid: (X, Y) => (%d, %d)", gridSizeX, gridSizeY);

    NSUInteger annotationCounter = 0;
    NSUInteger counter = 0;
    for(int i = 1; i < (gridSizeX + 1); i++) {
        for(int j = 1; j < (gridSizeY + 1); j++){
            counter++;

            int x = mapRect.origin.x + (i - 1) * cellSize.width;
            int y = mapRect.origin.y + (j - 1) * cellSize.height;

            MKMapRect gridRect = MKMapRectMake(x, y, cellSize.width, cellSize.height);

            NSArray *newAnnotations = [annotationTree annotationsInMapRect:gridRect];

            // cluster annotations in this grid piece, if there are annotations to be clustered
            if (newAnnotations.count > 0) {
                KPAnnotation *annotation = [[KPAnnotation alloc] initWithAnnotations:newAnnotations];
                [newClusters addObject:annotation];

                kp_cluster_t *cluster = self.clusterStorage + clusterIndex;
                cluster->mapRect = gridRect;
                cluster->annotationIndex = clusterIndex;
                cluster->merged = NO;

                cluster->distributionQuadrant = KPClusterDistributionQuadrantForPointInsideMapRect(gridRect, MKMapPointForCoordinate(annotation.coordinate));

                self.clusterGrid[i][j] = cluster;

                clusterIndex++;
                annotationCounter += newAnnotations.count;
            } else {
                self.clusterGrid[i][j] = NULL;
            }
        }
    }

    NSLog(@"AnnotationCounter %lu", (unsigned long)annotationCounter);
    
    /* Validation (Debug, remove later) */
    assert(counter == (gridSizeX * gridSizeY));

    /* Validation (Debug, remove later) */
    for(int i = 0; i < gridSizeX; i++){
        for(int j = 0; j < gridSizeY; j++){
            kp_cluster_t *cluster = self.clusterGrid[i][j];

            if (cluster) {
                assert(cluster->merged == NO);
                assert(cluster->annotationIndex >= 0);
                assert(cluster->annotationIndex < gridSizeX * gridSizeY);
            }
        }
    }


    newClusters = (NSMutableArray *)[self _mergeOverlappingClusters:newClusters inClusterGrid:self.clusterGrid gridSizeX:gridSizeX gridSizeY:gridSizeY];


    return newClusters;
}


- (NSArray *)_mergeOverlappingClusters:(NSArray *)clusters inClusterGrid:(kp_cluster_t ***)clusterGrid gridSizeX:(int)gridSizeX gridSizeY:(int)gridSizeY {
    __block NSMutableArray *mutableClusters = [NSMutableArray arrayWithArray:clusters];
    __block NSMutableIndexSet *indexesOfClustersToBeRemovedAsMerged = [NSMutableIndexSet indexSet];

    kp_cluster_merge_result_t (^checkClustersAndMergeIfNeeded)(kp_cluster_t *cl1, kp_cluster_t *cl2) = ^(kp_cluster_t *cl1, kp_cluster_t *cl2) {
        /* Debug checks (remove later) */
        assert(cl1 && cl1->merged == NO);
        assert(cl2 && cl2->merged == NO);

        assert(cl1->annotationIndex >= 0 && cl1->annotationIndex < gridSizeX * gridSizeY);
        assert(cl2->annotationIndex >= 0 && cl2->annotationIndex < gridSizeX * gridSizeY);


        KPAnnotation *cluster1 = [mutableClusters objectAtIndex:cl1->annotationIndex];
        KPAnnotation *cluster2 = [mutableClusters objectAtIndex:cl2->annotationIndex];

        BOOL clustersIntersect = [self.delegate clusterIntersects:cluster1 anotherCluster:cluster2];

        if (clustersIntersect) {
            NSMutableSet *combinedSet = [NSMutableSet setWithSet:cluster1.annotations];
            [combinedSet unionSet:cluster2.annotations];

            KPAnnotation *newAnnotation = [[KPAnnotation alloc] initWithAnnotationSet:combinedSet];

            MKMapPoint newClusterMapPoint = MKMapPointForCoordinate(newAnnotation.coordinate);

            if (MKMapRectContainsPoint(cl1->mapRect, newClusterMapPoint)) {
                [indexesOfClustersToBeRemovedAsMerged addIndex:cl2->annotationIndex];
                cl2->merged = YES;

                mutableClusters[cl1->annotationIndex] = newAnnotation;

                cl1->distributionQuadrant = KPClusterDistributionQuadrantForPointInsideMapRect(cl1->mapRect, newClusterMapPoint);

                return KPClusterMergeResultCurrent;
            } else {
                [indexesOfClustersToBeRemovedAsMerged addIndex:cl1->annotationIndex];
                cl1->merged = YES;

                mutableClusters[cl2->annotationIndex] = newAnnotation;

                cl2->distributionQuadrant = KPClusterDistributionQuadrantForPointInsideMapRect(cl2->mapRect, newClusterMapPoint);

                return KPClusterMergeResultOther;
            }
        }

        return KPClusterMergeResultNone;
    };


    int currentClusterCoordinate[2];
    int adjacentClusterCoordinate[2];

    kp_cluster_t *currentCellCluster;
    kp_cluster_t *adjacentCellCluster;

    kp_cluster_merge_result_t mergeResult;


    for (int16_t j = 1; j < (gridSizeY + 2); j++) {
        for (int16_t i = 1; i < (gridSizeX + 2); i++) {
        loop_with_explicit_i_and_j:

            assert(i >= 0);
            assert(j >= 0);

            currentClusterCoordinate[0] = i;
            currentClusterCoordinate[1] = j;

            currentCellCluster = clusterGrid[i][j];

            if (currentCellCluster == NULL || currentCellCluster->merged) {
                continue;
            }

            int lookupIndexForCurrentCellQuadrant = log2f(currentCellCluster->distributionQuadrant); // we take log2f, because we need to transform KPClusterDistributionQuadrant which is one of the 1, 2, 4, 8 into array index: 0, 1, 2, 3, which we will use for lookups on the next step

            for (int adjacentClustersPositionIndex = 0; adjacentClustersPositionIndex < 3; adjacentClustersPositionIndex++) {
                int adjacentClusterPosition = KPClusterAdjacentClustersTable[lookupIndexForCurrentCellQuadrant][adjacentClustersPositionIndex];

                adjacentClusterCoordinate[0] = currentClusterCoordinate[0] + KPAdjacentClustersCoordinateDeltas[adjacentClusterPosition][0];
                adjacentClusterCoordinate[1] = currentClusterCoordinate[1] + KPAdjacentClustersCoordinateDeltas[adjacentClusterPosition][1];

                adjacentCellCluster = clusterGrid[adjacentClusterCoordinate[0]][adjacentClusterCoordinate[1]];

                // In third condition we use bitwise & to check if adjacent cell has distribution of its cluster point which is _complementary_ to a one of the current cell. If it is so, than it worth to make a merge check.
                if (adjacentCellCluster != NULL && adjacentCellCluster->merged == NO && (KPClusterConformityTable[adjacentClusterPosition] & adjacentCellCluster->distributionQuadrant) != 0) {
                    mergeResult = checkClustersAndMergeIfNeeded(currentCellCluster, adjacentCellCluster);

                    // The case when other cluster did adsorb current cluster into itself. This means that we must not continue looking for adjacent clusters because we don't have a current cell now.
                    if (mergeResult == KPClusterMergeResultOther) {
                        // If this other cluster lies upstream (behind current i,j cell), we revert back to its [i,j] coordinate and continue looping
                        if (*(int32_t *)currentClusterCoordinate > *(int32_t *)adjacentClusterCoordinate) {

                            i = adjacentClusterCoordinate[0];
                            j = adjacentClusterCoordinate[1];

                            goto loop_with_explicit_i_and_j;
                        }
                        
                        break; // This breaks from checking adjacent clusters
                    }
                }
            }
        }
    }
    
    // We remove all the indexes of merged clusters that were accumulated by checkClustersAndMergeIfNeeded()
    [mutableClusters removeObjectsAtIndexes:indexesOfClustersToBeRemovedAsMerged];
    
    return mutableClusters;
}


- (void)initializeClusterGridWithSizeX:(NSUInteger)gridSizeX sizeY:(NSUInteger)gridSizeY {
    if (self.gridSize.X < gridSizeX || self.gridSize.Y < gridSizeY) {
        kp_cluster_t *largerClusterStorage = realloc(self.clusterStorage, (gridSizeX * gridSizeY) * sizeof(kp_cluster_t));

        if (largerClusterStorage != NULL) {
            self.clusterStorage = largerClusterStorage;
        } else {
            abort();
        }

        kp_cluster_t ***largerClusterGrid = realloc(self.clusterGrid, (gridSizeX + 2) * sizeof(kp_cluster_t **));

        if (largerClusterGrid != NULL) {
            self.clusterGrid = largerClusterGrid;
        } else {
            abort();
        }

        BOOL gridEmpty = (self.gridSize.X == 0);
        size_t positionOfFirstNewCell = self.gridSize.X + 2 * (gridEmpty == NO);
        size_t numberOfNewCells = (gridSizeX - self.gridSize.X) + 2 * gridEmpty;

        //NSLog(@"positionOfFirstNeCell, numberOfNewCells %ld %ld", positionOfFirstNewCell, numberOfNewCells);

        memset(self.clusterGrid + positionOfFirstNewCell, 0, numberOfNewCells * sizeof(kp_cluster_t **));

        for (int i = 0; i < (gridSizeX + 2); i++) {
            //NSLog(@"%d", self.clusterGrid[i] == NULL);

            self.clusterGrid[i] = realloc(self.clusterGrid[i], (gridSizeY + 2) * sizeof(kp_cluster_t *));

            if (self.clusterGrid[i] == NULL) {
                abort();
            }

            // First and last elements are marginal NULL
            self.clusterGrid[i][0] = NULL;
            self.clusterGrid[i][gridSizeY + 1] = NULL;
        }

        self.gridSize = (kp_cluster_grid_size_t){ gridSizeX, gridSizeY };
    }

    // memset() is the fastest way to NULLify marginal first and last rows of clusterGrid.
    memset(self.clusterGrid[0],             0, (gridSizeY + 2) * sizeof(kp_cluster_t *));
    memset(self.clusterGrid[gridSizeX + 1], 0, (gridSizeY + 2) * sizeof(kp_cluster_t *));

    /* Validation (Debug, remove later) */
    for (int i = 0; i < (gridSizeX + 2); i++) {
        assert(self.clusterGrid[i][0] == NULL);
        assert(self.clusterGrid[i][gridSizeY + 1] == NULL);
    }
    for (int i = 0; i < (gridSizeY + 2); i++) {
        assert(self.clusterGrid[0][i] == NULL);
        assert(self.clusterGrid[gridSizeX + 1][0] == NULL);
    }
}


@end
