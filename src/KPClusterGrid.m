//
//  KPClusterGrid.m
//  kingpin
//
//  Created by Stanislaw Pankevich on 18/04/14.
//
//

#import "KPClusterGrid.h"


void KPClusterGridInit(kp_cluster_grid_t **clusterGrid, NSUInteger gridSizeX, NSUInteger gridSizeY) {
    assert(clusterGrid);

    kp_cluster_grid_t *_clusterGrid;

    if (*clusterGrid) {
        _clusterGrid = *clusterGrid;
    } else {
        _clusterGrid = calloc(1, sizeof(kp_cluster_grid_t));
    }

    if (_clusterGrid->size.X < gridSizeX || _clusterGrid->size.Y < gridSizeY) {
        _clusterGrid->storage = realloc(_clusterGrid->storage, (gridSizeX * gridSizeY) * sizeof(kp_cluster_t));

        _clusterGrid->grid = realloc(_clusterGrid->grid, (gridSizeX + 2) * sizeof(kp_cluster_t **));

        if (_clusterGrid->grid == NULL || _clusterGrid->storage == NULL) {
            exit(1);
        }


        BOOL gridEmpty = (_clusterGrid->size.X == 0);
        size_t positionOfFirstNewCell = _clusterGrid->size.X + 2 * (gridEmpty == NO);
        size_t numberOfNewCells = (gridSizeX - _clusterGrid->size.X) + 2 * gridEmpty;


        memset(_clusterGrid->grid + positionOfFirstNewCell, 0, numberOfNewCells * sizeof(kp_cluster_t **));


        for (int i = 0; i < (gridSizeX + 2); i++) {
            _clusterGrid->grid[i] = realloc(_clusterGrid->grid[i], (gridSizeY + 2) * sizeof(kp_cluster_t *));

            if (_clusterGrid->grid[i] == NULL) {
                exit(1);
            }
        }

        _clusterGrid->size.X = gridSizeX;
        _clusterGrid->size.Y = gridSizeY;
    }

    for (int i = 0; i < (gridSizeX + 2); i++) {
        memset(_clusterGrid->grid[i], 0, (gridSizeY + 2) * sizeof(kp_cluster_t *));
    }

    /* Validation (Debug, remove later) */
    for (int i = 0; i < (gridSizeX + 2); i++) {
        for (int j = 0; j < (gridSizeY + 2); j++) {
            assert(_clusterGrid->grid[i][j] == NULL);
        }
    }

    *clusterGrid = _clusterGrid;
}


void KPClusterGridFree(kp_cluster_grid_t *clusterGrid) {
    for (int i = 0; i < (clusterGrid->size.X + 2); i++) {
        free(clusterGrid->grid[i]);
    }

    free(clusterGrid->grid);
    free(clusterGrid->storage);
}

void KPClusterGridDebug(kp_cluster_grid_t *clusterGrid) {
    for (int j = 0; j < (clusterGrid->size.Y + 2); j++) {
        for (int i = 0; i < (clusterGrid->size.X + 2); i++) {
            if (clusterGrid->grid[i][j]) {
                printf("[%2d ]  ", clusterGrid->grid[i][j]->annotationIndex);
            } else {
                printf(" NULL  ");
            }
        }
        printf("\n");
    }

    puts("");
}


void KPClusterGridMergeWithOldClusterGrid(kp_cluster_grid_t **clusterGrid, NSInteger offsetX, NSInteger offsetY, void(^marginalClusterCellBlock)(kp_cluster_t *clusterCell)) {
    kp_cluster_grid_t *_clusterGrid = *clusterGrid;

    assert(abs(offsetX) < (int)_clusterGrid->size.X);
    assert(abs(offsetY) < (int)_clusterGrid->size.Y);

    NSUInteger gridSizeX = _clusterGrid->size.X;
    NSUInteger gridSizeY = _clusterGrid->size.Y;

    NSLog(@"Gridsize:(%lu, %lu), offset:(%ld, %ld)", (unsigned long)gridSizeX, (unsigned long)gridSizeY, (long)offsetX, (long)offsetY);

    if (offsetX == 0 && offsetY == 0) return;

    int numberOfMarginalXCellsToCopyAlongAxisY = (int)(gridSizeY - abs(offsetY));
    int numberOfMarginalYCellsToCopyAlongAxisX = (int)(gridSizeX - abs(offsetX));

    kp_cluster_t **marginalXCells = NULL;
    kp_cluster_t **marginalYCells = NULL;

    int marginX;
    int startYPosition;
    int finalYPosition;

    NSUInteger marginalXCellsIndex = 0;
    if (offsetX != 0) {
        marginalXCells = calloc(numberOfMarginalXCellsToCopyAlongAxisY, sizeof(kp_cluster_t *));

        marginX = (offsetX > 0) ? (int)gridSizeX : 1;

        startYPosition = (offsetY >= 0) ? (1 + offsetY)  : 1;
        finalYPosition = (offsetY >= 0) ? (int)gridSizeY : ((int)gridSizeY + offsetY);

        KPClusterDistributionQuadrant acceptableDistributionQuadrant;
        kp_cluster_t *cluster = NULL;

        /* first */
        cluster = _clusterGrid->grid[marginX][startYPosition];

        if (cluster != NULL) {
            if (offsetY >= 0) {
                acceptableDistributionQuadrant = (offsetX > 0) ? KPClusterDistributionQuadrantFour : KPClusterDistributionQuadrantThree;
            } else {
                acceptableDistributionQuadrant = (offsetX > 0) ? KPClusterDistributionQuadrantOne : KPClusterDistributionQuadrantTwo;

                if (numberOfMarginalYCellsToCopyAlongAxisX > 1) {
                    acceptableDistributionQuadrant |= (offsetX > 0) ? KPClusterDistributionQuadrantTwo : KPClusterDistributionQuadrantOne;
                }

                if (numberOfMarginalXCellsToCopyAlongAxisY > 1) {
                    acceptableDistributionQuadrant |= (offsetX > 0) ? KPClusterDistributionQuadrantFour : KPClusterDistributionQuadrantThree;
                }
            }

            if ((cluster->clusterType == KPClusterGridCellSingle) || ((cluster->clusterType == KPClusterGridCellMerger) && (acceptableDistributionQuadrant & cluster->distributionQuadrant) != 0)) {
                marginalXCells[marginalXCellsIndex] = cluster;
                marginalClusterCellBlock(cluster);
                marginalXCellsIndex++;
            }
        } else {
            marginalXCellsIndex++;
        }

        /* non-edge */
        if (numberOfMarginalXCellsToCopyAlongAxisY > 2) {
            for (int j = (startYPosition + 1); j <= (finalYPosition - 1); j++) {
                cluster = _clusterGrid->grid[marginX][j];

                if (cluster) {
                    acceptableDistributionQuadrant = (offsetX > 0) ? (KPClusterDistributionQuadrantFour | KPClusterDistributionQuadrantOne) : KPClusterDistributionQuadrantTwo | KPClusterDistributionQuadrantThree;


                    if ((cluster->clusterType == KPClusterGridCellSingle) ||
                        ((cluster->clusterType == KPClusterGridCellMerger) && ((acceptableDistributionQuadrant & cluster->distributionQuadrant) != 0))) {
                        marginalXCells[marginalXCellsIndex] = cluster;
                        marginalClusterCellBlock(cluster);
                    }
                }

                marginalXCellsIndex++;
            }
        }

        /* last */
        if (numberOfMarginalXCellsToCopyAlongAxisY > 1) {
            cluster = _clusterGrid->grid[marginX][finalYPosition];

            if (cluster != NULL) {
                if (offsetY <= 0) {
                    acceptableDistributionQuadrant = (offsetX > 0) ? KPClusterDistributionQuadrantOne : KPClusterDistributionQuadrantTwo;
                } else {
                    acceptableDistributionQuadrant = (offsetX > 0) ?
                    (KPClusterDistributionQuadrantOne | KPClusterDistributionQuadrantFour) :
                    (KPClusterDistributionQuadrantTwo | KPClusterDistributionQuadrantThree);

                    if (numberOfMarginalYCellsToCopyAlongAxisX > 1) {
                        acceptableDistributionQuadrant |= (offsetX > 0) ?
                        KPClusterDistributionQuadrantThree :
                        KPClusterDistributionQuadrantFour;
                    }
                }

                if ((cluster->clusterType == KPClusterGridCellSingle) || ((cluster->clusterType == KPClusterGridCellMerger) && (acceptableDistributionQuadrant & cluster->distributionQuadrant) != 0)) {
                    marginalXCells[marginalXCellsIndex] = cluster;
                    marginalClusterCellBlock(cluster);
                }
            }

            marginalXCellsIndex++;
        }
    }

    int marginY;
    int startXPosition;
    int finalXPosition;

    NSUInteger marginalYCellsIndex = 0;
    if (offsetY != 0) {
        marginalYCells = malloc(numberOfMarginalYCellsToCopyAlongAxisX * sizeof(kp_cluster_t *));

        marginY = (offsetY > 0) ? (int)gridSizeY : 1;

        startXPosition = (offsetX >= 0) ? (1 + offsetX)       : 2;
        finalXPosition = (offsetX >= 0) ? ((int)gridSizeX - 1) : ((int)gridSizeX + offsetX);

        for (int i = startXPosition; i <= finalXPosition; i++) {
            kp_cluster_t *cluster = _clusterGrid->grid[i][marginY];

            marginalYCells[marginalYCellsIndex] = cluster;

            if (cluster && (cluster->clusterType != KPClusterGridCellSingle)) {
                marginalYCells[marginalYCellsIndex] = NULL;
            }

            marginalYCellsIndex++;

            if (cluster && (cluster->clusterType == KPClusterGridCellSingle)) {
                marginalClusterCellBlock(cluster);
            }
        }
    }


    for (int i = 0; i < (gridSizeX + 2); i++) {
        memset(_clusterGrid->grid[i], 0, (gridSizeY + 2) * sizeof(kp_cluster_t *));
    }

    if (offsetX != 0) {
        marginX -= offsetX;

        startYPosition -= offsetY;
        finalYPosition -= offsetY;

        for (int j = startYPosition; j <= finalYPosition; j++) {
            _clusterGrid->grid[marginX][j] = marginalXCells[j - startYPosition];
        }

        free(marginalXCells);
    }

    if (offsetY != 0) {
        marginY -= offsetY;

        startXPosition -= offsetX;
        finalXPosition -= offsetX;

        for (int i = startXPosition; i <= finalXPosition; i++) {
            _clusterGrid->grid[i][marginY] = marginalYCells[i - startXPosition];
        }

        free(marginalYCells);
    }

    *clusterGrid = _clusterGrid;
}


void KPClusterGridCopy(kp_cluster_grid_t **clusterGrid, NSInteger offsetX, NSInteger offsetY, void(^marginalClusterCellBlock)(kp_cluster_t *clusterCell)) {
    assert(clusterGrid && *clusterGrid);

    kp_cluster_grid_t *_clusterGrid = *clusterGrid;

    NSUInteger gridSizeX = _clusterGrid->size.X;
    NSUInteger gridSizeY = _clusterGrid->size.Y;

    if (offsetY > 0) {
        if (offsetX > 0) {
            for (int j = (1 + offsetY); j < (gridSizeY + 1); j++) {
                for (int i = (1 + offsetX); i < (gridSizeX + 1); i++) {
                    _clusterGrid->grid[i - offsetX][j - offsetY] = _clusterGrid->grid[i][j];
                }
                for (int i = (gridSizeX + 1 - offsetX); i < (gridSizeX + 1); i++) {
                    //NSLog(@"to NULL %d", _clusterGrid->grid[i][j]->annotationIndex);
                    _clusterGrid->grid[i][j - offsetY] = NULL;
                }
            }

            for (int j = (gridSizeY + 1 - offsetY); j < (gridSizeY + 1); j++) {
                for (int i = 1; i < (gridSizeX + 1); i++) {
                    _clusterGrid->grid[i][j] = NULL;
                }
            }
        }
    } else if (offsetY < 0) {

    } else {

    }
}

