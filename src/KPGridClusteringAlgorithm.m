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


void MKMapViewDrawMapRect(MKMapView *mapView, MKMapRect mapRect) {
    MKMapPoint points[5];
    points[0] = mapRect.origin;
    points[1] = MKMapPointMake(mapRect.origin.x + mapRect.size.width, mapRect.origin.y);
    points[2] = MKMapPointMake(mapRect.origin.x + mapRect.size.width, mapRect.origin.y + mapRect.size.height);
    points[3] = MKMapPointMake(mapRect.origin.x, mapRect.origin.y + mapRect.size.height);
    points[4] = mapRect.origin;

    [mapView addOverlay:[MKPolyline polylineWithPoints:points count:5]];
}


@implementation KPGridClusteringAlgorithm

- (id)init {
    self = [super init];

    if (self == nil) return nil;

    self.lastClusteredGridRect = (MKMapRect){0, 0};

    return self;
}

- (void)dealloc {
    KPClusterGridFree(self.clusterGrid);
}

#pragma mark
#pragma mark Grid clustering algorithm

- (void)performClusteringOfAnnotationsInMapRect:(MKMapRect)mapRect cellSize:(MKMapSize)cellSize annotationTree:(KPAnnotationTree *)annotationTree panning:(BOOL)panning newClusters:(NSArray * __autoreleasing *)newClusters oldClusters:(NSArray * __autoreleasing *)oldClusters {
    assert(oldClusters);

    NSMutableArray *_newClusters;
    NSMutableArray *_oldClusters;

    if (panning) {
        _oldClusters = [NSMutableArray array];
    }

    assert(((uint32_t)mapRect.size.width  % (uint32_t)cellSize.width)  == 0);
    assert(((uint32_t)mapRect.size.height % (uint32_t)cellSize.height) == 0);

    int gridSizeX = mapRect.size.width / cellSize.width;
    int gridSizeY = mapRect.size.height / cellSize.height;

    assert(((uint32_t)mapRect.size.width % (uint32_t)cellSize.width) == 0);

    // We initialize with a rough estimate for size, as to minimize allocations.
    _newClusters = [[NSMutableArray alloc] initWithCapacity:(gridSizeX * gridSizeY)];

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

    NSLog(@"%ld %ld", sizeof(kp_cluster_t), sizeof(kp_cluster_t *));

    if ((self.clusterGrid == NULL) || panning == NO || (MKMapRectIntersectsRect(mapRect, self.lastClusteredGridRect) == NO)) {
        KPClusterGridInit(&_clusterGrid, gridSizeX, gridSizeY);
    } else {
        assert(self.clusterGrid->size.X == gridSizeX);
        assert(self.clusterGrid->size.Y == gridSizeY);

        assert(((uint32_t)fabs(mapRect.origin.x - self.lastClusteredGridRect.origin.x) % (uint32_t)cellSize.width) == 0);
        assert(((uint32_t)fabs(mapRect.origin.y - self.lastClusteredGridRect.origin.y) % (uint32_t)cellSize.height) == 0);


        NSInteger offsetX = (NSInteger)round((mapRect.origin.x - self.lastClusteredGridRect.origin.x) / cellSize.width);
        NSInteger offsetY = (NSInteger)round((mapRect.origin.y - self.lastClusteredGridRect.origin.y) / cellSize.height);

        if (offsetX == 0 && offsetY == 0) {
            NSLog(@"Offset is zero. Nothing to do...");

            return;
        } else {
            NSLog(@"Offsets: (%ld, %ld)", (long)offsetX, (long)offsetY);
        }

        KPClusterGridDebug(self.clusterGrid);

        KPClusterGridMergeWithOldClusterGrid(&_clusterGrid, offsetX, offsetY, ^(kp_cluster_t *cluster) {
            NSLog(@"Debugging cluster:");
            KPClusterDebug(cluster);
            
            [_oldClusters addObject:cluster->annotation];
        });

        KPClusterGridDebug(self.clusterGrid);
    }


    NSUInteger clusterIndex = 0;

    NSLog(@"Grid: (X, Y) => (%d, %d)", gridSizeX, gridSizeY);

    NSUInteger annotationCounter = 0;
    NSUInteger counter = 0;
    for(int col = 1; col < (gridSizeY + 1); col++){
        for(int row = 1; row < (gridSizeX + 1); row++) {
            counter++;

            int x = mapRect.origin.x + (row - 1) * cellSize.width;
            int y = mapRect.origin.y + (col - 1) * cellSize.height;

            MKMapRect cellRect = MKMapRectMake(x, y, cellSize.width, cellSize.height);

            MKMapViewDrawMapRect(self.debuggingMapView, cellRect);

            if (panning && MKMapRectContainsRect(self.lastClusteredGridRect, cellRect)) {
                kp_cluster_t *cluster = self.clusterGrid->grid[col][row];

                if (cluster) {
                    if (cluster->doNotRecluster) {
                        continue;
                    } else {
                        KPClusterStorageClusterRemove(self.clusterGrid->storage, cluster);
                    }
                } else {
                    self.clusterGrid->grid[col][row] = NULL;

                    continue;
                }
            }

            NSArray *newAnnotations = [annotationTree annotationsInMapRect:cellRect];

            // cluster annotations in this grid piece, if there are annotations to be clustered
            if (newAnnotations.count > 0) {
                KPAnnotation *annotation = [[KPAnnotation alloc] initWithAnnotations:newAnnotations];
                [_newClusters addObject:annotation];

                kp_cluster_t *cluster = KPClusterStorageClusterAdd(self.clusterGrid->storage);

                cluster->mapRect = cellRect;
                cluster->annotationIndex = clusterIndex;
                cluster->clusterType = KPClusterGridCellSingle;
                cluster->annotation = annotation;
                
                cluster->distributionQuadrant = KPClusterDistributionQuadrantForPointInsideMapRect(cellRect, MKMapPointForCoordinate(annotation.coordinate));

                self.clusterGrid->grid[col][row] = cluster;

                clusterIndex++;
                annotationCounter += newAnnotations.count;
            } else {
                self.clusterGrid->grid[col][row] = NULL;
            }
        }
    }

    NSLog(@"AnnotationCounter %lu", (unsigned long)annotationCounter);
    
    /* Validation (Debug, remove later) */
    assert(counter == (gridSizeX * gridSizeY));

    /* Validation (Debug, remove later) */
    for(int col = 0; col < (gridSizeY + 2); col++) {
        for(int row = 0; row < (gridSizeX + 2); row++) {
            kp_cluster_t *cluster = self.clusterGrid->grid[col][row];

            if (cluster) {
                //KPClusterDebug(cluster);
                
                assert(cluster->annotationIndex >= 0);
                assert(cluster->annotationIndex < gridSizeX * gridSizeY);
            }
        }
    }


    _newClusters = (NSMutableArray *)[self _mergeOverlappingClusters:_newClusters inClusterGrid:self.clusterGrid gridSizeX:gridSizeX gridSizeY:gridSizeY];


    self.lastClusteredGridRect = mapRect;

    *newClusters = [_newClusters copy];
    *oldClusters = [_oldClusters copy];

    NSLog(@"Grid after clustering");
    KPClusterGridDebug(self.clusterGrid);
}


- (NSArray *)_mergeOverlappingClusters:(NSArray *)clusters inClusterGrid:(kp_cluster_grid_t *)clusterGrid gridSizeX:(int)gridSizeX gridSizeY:(int)gridSizeY {
    __block NSMutableArray *mutableClusters = [NSMutableArray arrayWithArray:clusters];
    __block NSMutableIndexSet *indexesOfClustersToBeRemovedAsMerged = [NSMutableIndexSet indexSet];

    kp_cluster_merge_result_t (^checkClustersAndMergeIfNeeded)(kp_cluster_t *cl1, kp_cluster_t *cl2) = ^(kp_cluster_t *cl1, kp_cluster_t *cl2) {
        /* Debug checks (remove later) */
        assert(cl1 && cl1->clusterType != KPClusterGridCellMerged);
        assert(cl2 && cl2->clusterType != KPClusterGridCellMerged);

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
                cl2->clusterType = KPClusterGridCellMerged;
                cl2->annotation = nil;

                mutableClusters[cl1->annotationIndex] = newAnnotation;

                cl1->annotation = newAnnotation;
                cl1->distributionQuadrant = KPClusterDistributionQuadrantForPointInsideMapRect(cl1->mapRect, newClusterMapPoint);
                cl1->clusterType = KPClusterGridCellMerger;

                return KPClusterMergeResultCurrent;
            } else {
                [indexesOfClustersToBeRemovedAsMerged addIndex:cl1->annotationIndex];
                cl1->clusterType = KPClusterGridCellMerged;
                cl1->annotation = nil;

                mutableClusters[cl2->annotationIndex] = newAnnotation;

                cl2->annotation = newAnnotation;
                cl2->distributionQuadrant = KPClusterDistributionQuadrantForPointInsideMapRect(cl2->mapRect, newClusterMapPoint);
                cl2->clusterType = KPClusterGridCellMerger;

                return KPClusterMergeResultOther;
            }
        }

        return KPClusterMergeResultNone;
    };


    struct {
        int row; // this order "row then col"
        int col; // is important
    } currentClusterCoordinate, adjacentClusterCoordinate;


    kp_cluster_t *currentCellCluster;
    kp_cluster_t *adjacentCellCluster;

    kp_cluster_merge_result_t mergeResult;


    for (int16_t col = 1; col < (gridSizeY + 2); col++) {
        for (int16_t row = 1; row < (gridSizeX + 2); row++) {
            loop_with_explicit_col_and_row:

            assert(col > 0);
            assert(row > 0);

            currentClusterCoordinate.col = col;
            currentClusterCoordinate.row = row;

            currentCellCluster = clusterGrid->grid[col][row];

            if (currentCellCluster == NULL ||
                currentCellCluster->doNotRecluster ||
                currentCellCluster->clusterType == KPClusterGridCellMerged) {
                continue;
            }

            int lookupIndexForCurrentCellQuadrant = log2f(currentCellCluster->distributionQuadrant); // we take log2f, because we need to transform KPClusterDistributionQuadrant which is one of the 1, 2, 4, 8 into array index: 0, 1, 2, 3, which we will use for lookups on the next step

            for (int adjacentClustersPositionIndex = 0; adjacentClustersPositionIndex < 3; adjacentClustersPositionIndex++) {
                int adjacentClusterPosition = KPClusterAdjacentClustersTable[lookupIndexForCurrentCellQuadrant][adjacentClustersPositionIndex];

                adjacentClusterCoordinate.col = currentClusterCoordinate.col + KPAdjacentClustersCoordinateDeltas[adjacentClusterPosition][0];
                adjacentClusterCoordinate.row = currentClusterCoordinate.row + KPAdjacentClustersCoordinateDeltas[adjacentClusterPosition][1];

                adjacentCellCluster = clusterGrid->grid[adjacentClusterCoordinate.col][adjacentClusterCoordinate.row];

                // In third condition we use bitwise & to check if adjacent cell has distribution of its cluster point which is _complementary_ to a one of the current cell. If it is so, than it worth to make a merge check.
                if (adjacentCellCluster != NULL &&
                    adjacentCellCluster->doNotRecluster == NO &&
                    adjacentCellCluster->clusterType != KPClusterGridCellMerged &&
                    (KPClusterConformityTable[adjacentClusterPosition] & adjacentCellCluster->distributionQuadrant) != 0) {
                    mergeResult = checkClustersAndMergeIfNeeded(currentCellCluster, adjacentCellCluster);

                    // The case when other cluster did adsorb current cluster into itself. This means that we must not continue looking for adjacent clusters because we don't have a current cell now.
                    if (mergeResult == KPClusterMergeResultOther) {
                        // If this other cluster lies upstream (behind current i,j cell), we revert back to its [i,j] coordinate and continue looping
                        if (*(int32_t *)(&currentClusterCoordinate) > *(int32_t *)(&adjacentClusterCoordinate)) {

                            col = adjacentClusterCoordinate.col;
                            row = adjacentClusterCoordinate.row;

                            goto loop_with_explicit_col_and_row;
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
