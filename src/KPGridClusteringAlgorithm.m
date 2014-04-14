//
//  KPGridClusteringAlgorithm.m
//  kingpin
//
//  Created by Stanislaw Pankevich on 12/04/14.
//
//

#import "KPGridClusteringAlgorithm.h"

#import "KPGridClusteringAlgorithm_Private.h"

#import <MapKit/MapKit.h>

#import "KPTreeControllerRework.h"
#import "KPAnnotationTree.h"
#import "KPAnnotation.h"


#import "NSArray+KP.h"



@implementation KPGridClusteringAlgorithm

- (id)init {
    self = [super init];

    if (self == nil) return nil;

    self.gridSize = (kp_cluster_grid_size_t){0, 0};
    self.lastClusteredGridRect = (MKMapRect){0, 0};

    return self;
}

- (void)dealloc {
    [self _freeClusterStorage];
}

#pragma mark
#pragma mark Temporary cluster storage

- (void)_initializeClusterGridWithSizeX:(NSUInteger)gridSizeX sizeY:(NSUInteger)gridSizeY {
    if (self.gridSize.X < gridSizeX || self.gridSize.Y < gridSizeY) {
        self.clusterStorage = realloc(self.clusterStorage, (gridSizeX * gridSizeY) * sizeof(kp_cluster_t));

        self.clusterGrid = realloc(self.clusterGrid, (gridSizeX + 2) * sizeof(kp_cluster_t **));

        if (self.clusterGrid == NULL || self.clusterStorage == NULL) {
            exit(1);
        }

        
        BOOL gridEmpty = (self.gridSize.X == 0);
        size_t positionOfFirstNewCell = self.gridSize.X + 2 * (gridEmpty == NO);
        size_t numberOfNewCells = (gridSizeX - self.gridSize.X) + 2 * gridEmpty;


        memset(self.clusterGrid + positionOfFirstNewCell, 0, numberOfNewCells * sizeof(kp_cluster_t **));


        for (int i = 0; i < (gridSizeX + 2); i++) {
            self.clusterGrid[i] = realloc(self.clusterGrid[i], (gridSizeY + 2) * sizeof(kp_cluster_t *));

            if (self.clusterGrid[i] == NULL) {
                exit(1);
            }
        }

        self.gridSize = (kp_cluster_grid_size_t){ gridSizeX, gridSizeY };
    }

    for (int i = 0; i < (gridSizeX + 2); i++) {
        memset(self.clusterGrid[i], 0, (gridSizeY + 2) * sizeof(kp_cluster_t *));
    }

    /* Validation (Debug, remove later) */
    for (int i = 0; i < (gridSizeX + 2); i++) {
        for (int j = 0; j < (gridSizeY + 2); j++) {
            assert(self.clusterGrid[i][j] == NULL);
        }
    }
}

- (void)_freeClusterStorage {
    for (int i = 0; i < self.gridSize.X; i++) {
        free(self.clusterGrid[i]);
    }

    free(self.clusterGrid);
    free(self.clusterStorage);
}

#pragma mark
#pragma mark Grid clustering algorithm

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

    NSLog(@"MapRect: %f %f %f %f", mapRect.size.width, mapRect.size.height, mapRect.origin.x, mapRect.origin.y);
    
    NSLog(@"Grid: (X, Y) => (%d, %d)", gridSizeX, gridSizeY);

    if ((self.clusterStorage == NULL && self.clusterGrid == NULL) || panning == NO) {
        [self _initializeClusterGridWithSizeX:gridSizeX sizeY:gridSizeY];
    } else {
        assert(self.gridSize.X == gridSizeX);
        assert(self.gridSize.Y == gridSizeY);

        NSLog(@"diffx and cellsize: %f %f", self.lastClusteredGridRect.origin.x - mapRect.origin.x, cellSize.width);
        assert(((uint32_t)fabs(self.lastClusteredGridRect.origin.x - mapRect.origin.x) % (uint32_t)cellSize.width) == 0);
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

            MKMapRect cellRect = MKMapRectMake(x, y, cellSize.width, cellSize.height);

            if (panning && MKMapRectContainsRect(self.lastClusteredGridRect, cellRect)) {
                self.clusterGrid[i][j] = NULL;

                continue;
            }

            NSArray *newAnnotations = [annotationTree annotationsInMapRect:cellRect];

            // cluster annotations in this grid piece, if there are annotations to be clustered
            if (newAnnotations.count > 0) {
                KPAnnotation *annotation = [[KPAnnotation alloc] initWithAnnotations:newAnnotations];
                [newClusters addObject:annotation];

                kp_cluster_t *cluster = self.clusterStorage + clusterIndex;
                cluster->mapRect = cellRect;
                cluster->annotationIndex = clusterIndex;
                cluster->merged = NO;

                cluster->distributionQuadrant = KPClusterDistributionQuadrantForPointInsideMapRect(cellRect, MKMapPointForCoordinate(annotation.coordinate));

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


    self.lastClusteredGridRect = mapRect;


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

@end




void KPClusterGridMergeWithOldClusterGrid(kp_cluster_t ***clusterGrid, NSUInteger gridSizeX, NSUInteger gridSizeY, NSInteger offsetX, NSInteger offsetY, void(^marginalClusterCellBlock)(kp_cluster_t *clusterCell)) {
    assert(offsetX < (int)gridSizeX);
    assert(offsetY < (int)gridSizeY);

    int numberOfMarginalXCellsToCopy = (int)fabs(gridSizeX - offsetX);
    int numberOfMarginalYCellsToCopy = (int)fabs(gridSizeY - offsetY);

    kp_cluster_t **marginalXCells = NULL;
    kp_cluster_t **marginalYCells = NULL;

    int marginX;
    int startYPosition;
    int finalYPosition;

    NSUInteger marginalXCellsIndex = 0;
    if (offsetX != 0) {
        marginalXCells = malloc(numberOfMarginalXCellsToCopy * sizeof(kp_cluster_t *));

        marginX = (offsetX > 0) ? (int)gridSizeX : 1;

        startYPosition = (offsetY >= 0) ? (1 + offsetY) : 1;
        finalYPosition = (offsetY >= 0) ? (int)gridSizeY : ((int)gridSizeY + offsetY);

        for (int j = startYPosition; j <= finalYPosition; j++) {
            if (clusterGrid[marginX][j]) {
                kp_cluster_t *cluster = clusterGrid[marginX][j];
                marginalXCells[marginalXCellsIndex] = cluster;

                marginalClusterCellBlock(cluster);

                marginalXCellsIndex++;
            }
        }
    }

    int marginY;
    int startXPosition;
    int finalXPosition;

    NSUInteger marginalYCellsIndex = 0;
    if (offsetY != 0) {
        marginalYCells = malloc(numberOfMarginalYCellsToCopy * sizeof(kp_cluster_t *));

        marginY = (offsetY > 0) ? (int)gridSizeY : 1;

        startXPosition = (offsetX >= 0) ? (1 + offsetX)       : 2;
        finalXPosition = (offsetX >= 0) ? ((int)gridSizeX - 1) : ((int)gridSizeX + offsetX);

        for (int i = startXPosition; i <= finalXPosition; i++) {
            if (clusterGrid[i][marginY]) {
                kp_cluster_t *cluster = clusterGrid[i][marginY];

                marginalYCells[marginalYCellsIndex] = cluster;

                marginalClusterCellBlock(cluster);

                marginalYCellsIndex++;
            }
        }
    }

    for (int i = 0; i < (gridSizeX + 2); i++) {
        memset(clusterGrid[i], 0, (gridSizeY + 2) * sizeof(kp_cluster_t *));
    }

    if (offsetX != 0) {
        marginX -= offsetX;

        startYPosition -= offsetY;
        finalYPosition -= offsetY;

        for (int j = startYPosition; j <= finalYPosition; j++) {
            clusterGrid[marginX][j] = marginalXCells[j - startYPosition];
        }

        free(marginalXCells);
    }

    if (offsetY != 0) {
        marginY -= offsetY;

        startXPosition -= offsetX;
        finalXPosition -= offsetX;
        
        for (int i = startXPosition; i <= finalXPosition; i++) {
            clusterGrid[i][marginY] = marginalYCells[i - startXPosition];
        }
        
        free(marginalYCells);
    }
}
