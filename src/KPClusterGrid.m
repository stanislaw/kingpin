//
//  KPClusterGrid.m
//  kingpin
//
//  Created by Stanislaw Pankevich on 18/04/14.
//
//

#import "KPClusterGrid.h"


void KPClusterStorageRealloc(kp_cluster_storage_t **storage, uint16_t cols, uint16_t rows) {
    assert(storage);

    kp_cluster_storage_t *_storage;

    if (*storage == NULL) {
        _storage = calloc(1, sizeof(kp_cluster_storage_t));
    } else {
        _storage = *storage;
    }

    _storage->storage     = realloc(_storage->storage,     (cols * rows) * sizeof(kp_cluster_t));
    _storage->freeIndexes = realloc(_storage->freeIndexes, (cols * rows) * sizeof(uint16_t));

    _storage->capacity.cols = cols;
    _storage->capacity.rows = rows;

    *storage = _storage;
}


void KPClusterStoragePurge(kp_cluster_storage_t **storage) {
    assert(storage && *storage);

    memset((*storage)->storage,     0, (*storage)->used);
    memset((*storage)->freeIndexes, 0, (*storage)->freeIndexesCount);

    (*storage)->used = 0;
    (*storage)->freeIndexesCount = 0;
}


void KPClusterStorageFree(kp_cluster_storage_t **storage) {
    assert(storage && *storage);

    free((*storage)->storage);
    free((*storage)->freeIndexes);
    free((*storage));
}


void KPClusterStorageDebug(kp_cluster_storage_t *storage) {
    NSLog(@"Cluster storage: %u %u", storage->used, storage->freeIndexesCount);

    for (int i = 0; i < storage->used; i++) {
        if ((storage->storage + i)) {
            printf("%d %d |", storage->storage[i].storageIndex, storage->storage[i].annotationIndex);
        } else {
            printf("NULL ");
        }
    }
    puts("");
}


kp_cluster_t * KPClusterStorageClusterAdd(kp_cluster_storage_t *storage) {
    uint16_t clusterIndex;

    //NSLog(@"KPClusterStorageClusterAdd()");

    //KPClusterStorageDebug(storage);

    if (storage->freeIndexesCount == 0) {
        clusterIndex = storage->used++;
    } else {
        clusterIndex = storage->freeIndexes[--storage->freeIndexesCount];
    }

    kp_cluster_t *cluster = storage->storage + clusterIndex;

    memset(cluster, 0, sizeof(kp_cluster_t));

    cluster->storageIndex = clusterIndex;

    return cluster;
}


void KPClusterStorageClusterRemove(kp_cluster_storage_t *storage, kp_cluster_t *cluster) {
    if (cluster == NULL) {
        return;
    }

    storage->freeIndexes[storage->freeIndexesCount++] = cluster->storageIndex;

    memset(storage->storage + cluster->storageIndex, 0, sizeof(kp_cluster_t));
}


void KPClusterGridInit(kp_cluster_grid_t **clusterGrid, NSUInteger gridSizeX, NSUInteger gridSizeY) {
    assert(clusterGrid);

    NSLog(@"KPClusterGridInit(%lu, %lu)", (unsigned long)gridSizeX, (unsigned long)gridSizeY);

    kp_cluster_grid_t *_clusterGrid;

    if (*clusterGrid) {
        _clusterGrid = *clusterGrid;
    } else {
        _clusterGrid = calloc(1, sizeof(kp_cluster_grid_t));
    }

    if (_clusterGrid->size.X < gridSizeX || _clusterGrid->size.Y < gridSizeY) {
        KPClusterStorageRealloc(&_clusterGrid->storage, gridSizeY, gridSizeX);

        _clusterGrid->grid = realloc(_clusterGrid->grid, (gridSizeY + 2) * sizeof(kp_cluster_t **));

        if (_clusterGrid->grid == NULL || _clusterGrid->storage == NULL) {
            exit(1);
        }


        BOOL gridEmpty = (_clusterGrid->size.X == 0 && _clusterGrid->size.Y == 0);

        size_t indexOfFirstNewRow = gridEmpty ? 0               : (_clusterGrid->size.Y + 2);
        size_t numberOfNewRows    = gridEmpty ? (gridSizeY + 2) : (gridSizeY - _clusterGrid->size.Y);

        memset(_clusterGrid->grid + indexOfFirstNewRow, 0, numberOfNewRows * sizeof(kp_cluster_t **));

        for (int j = 0; j < (gridSizeY + 2); j++) {
            _clusterGrid->grid[j] = realloc(_clusterGrid->grid[j], (gridSizeX + 2) * sizeof(kp_cluster_t *));

            if (_clusterGrid->grid[j] == NULL) {
                exit(1);
            }
        }

        _clusterGrid->size.X = gridSizeX;
        _clusterGrid->size.Y = gridSizeY;
    }

    for (int j = 0; j < (gridSizeY + 2); j++) {
        memset(_clusterGrid->grid[j], 0, (gridSizeX + 2) * sizeof(kp_cluster_t *));
    }

    KPClusterStoragePurge(&_clusterGrid->storage);

    /* Validation (Debug, remove later) */
    for (int col = 0; col < (gridSizeY + 2); col++) {
        for (int row = 0; row < (gridSizeX + 2); row++) {
            assert(_clusterGrid->grid[col][row] == NULL);
        }
    }

    *clusterGrid = _clusterGrid;
}


void KPClusterGridFree(kp_cluster_grid_t *clusterGrid) {
    for (int j = 0; j < (clusterGrid->size.Y + 2); j++) {
        free(clusterGrid->grid[j]);
    }

    free(clusterGrid->grid);

    KPClusterStorageFree(&clusterGrid->storage);
}

void KPClusterGridDebug(kp_cluster_grid_t *clusterGrid) {
    for (int col = 0; col < (clusterGrid->size.Y + 2); col++) {
        for (int row = 0; row < (clusterGrid->size.X + 2); row++) {
            kp_cluster_t *cluster = clusterGrid->grid[col][row];

            if (cluster) {
                printf("[%2lu (%d, %d)] ", (unsigned long)cluster->annotationIndex, cluster->clusterType, cluster->distributionQuadrant);
            } else {
                printf("    NULL    ");
            }
        }
        printf("\n");
    }

    puts("");
}


void KPClusterGridMergeWithOldClusterGrid(kp_cluster_grid_t **clusterGrid, NSInteger offsetX, NSInteger offsetY, void(^marginalClusterCellBlock)(kp_cluster_t *cluster)) {

    if (offsetX == 0 && offsetY == 0) return;

    kp_cluster_grid_t *_clusterGrid = *clusterGrid;

    assert(abs(offsetX) < (int)_clusterGrid->size.X);
    assert(abs(offsetY) < (int)_clusterGrid->size.Y);

    NSUInteger gridSizeX = _clusterGrid->size.X;
    NSUInteger gridSizeY = _clusterGrid->size.Y;


    NSLog(@"Gridsize:(%lu, %lu), offset:(%ld, %ld)", (unsigned long)gridSizeX, (unsigned long)gridSizeY, (long)offsetX, (long)offsetY);

    int numberOfMarginalXCellsToCopyAlongAxisY = (int)(gridSizeY - abs(offsetY));
    int numberOfMarginalYCellsToCopyAlongAxisX = (int)(gridSizeX - abs(offsetX));

    int indexOfEdgeRow;
    int indexOfFirstColumn;
    int indexOfLastColumn;

#warning WIP
    if (NO && offsetX != 0) {
        indexOfEdgeRow = (offsetX > 0) ? (int)gridSizeX : 1;

        indexOfFirstColumn = (offsetY >= 0) ? (1 + offsetY)  : 1;
        indexOfLastColumn  = (offsetY >= 0) ? (int)gridSizeY : ((int)gridSizeY + offsetY);

        KPClusterDistributionQuadrant acceptableDistributionQuadrant;
        kp_cluster_t *cluster = NULL;

        /* first */
        cluster = _clusterGrid->grid[indexOfFirstColumn][indexOfEdgeRow];

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

            if ((acceptableDistributionQuadrant & cluster->distributionQuadrant) != 0) {
                marginalClusterCellBlock(cluster);
            } else {
                cluster->clusterType = KPClusterGridCellDoNotRecluster;
            }
        } 

        /* non-edge */
        if (numberOfMarginalXCellsToCopyAlongAxisY > 2) {
            for (int j = (indexOfFirstColumn + 1); j <= (indexOfLastColumn - 1); j++) {
                cluster = _clusterGrid->grid[j][indexOfEdgeRow];

                if (cluster != NULL) {
                    acceptableDistributionQuadrant = (offsetX > 0) ? (KPClusterDistributionQuadrantFour | KPClusterDistributionQuadrantOne) : KPClusterDistributionQuadrantTwo | KPClusterDistributionQuadrantThree;


                    if ((acceptableDistributionQuadrant & cluster->distributionQuadrant) != 0) {
                        marginalClusterCellBlock(cluster);
                    } else {
                        cluster->clusterType = KPClusterGridCellDoNotRecluster;
                    }
                }
            }
        }

        /* last */
        if (numberOfMarginalXCellsToCopyAlongAxisY > 1) {
            cluster = _clusterGrid->grid[indexOfLastColumn][indexOfEdgeRow];

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

                if ((acceptableDistributionQuadrant & cluster->distributionQuadrant) != 0) {
                    marginalClusterCellBlock(cluster);
                } else {
                    cluster->clusterType = KPClusterGridCellDoNotRecluster;
                }
            }
        }
    }

    int marginY;
    int startXPosition;
    int finalXPosition;

    //NSUInteger marginalYCellsIndex = 0;
    if (offsetY != 0) {
        marginY = (offsetY > 0) ? (int)gridSizeY : 1;

        startXPosition = (offsetX >= 0) ? (1 + offsetX)       : 2;
        finalXPosition = (offsetX >= 0) ? ((int)gridSizeX - 1) : ((int)gridSizeX + offsetX);

//        for (int i = startXPosition; i <= finalXPosition; i++) {
//            kp_cluster_t *cluster = _clusterGrid->grid[i][marginY];
//
//            marginalYCellsIndex++;
//
//            if (cluster && (cluster->clusterType == KPClusterGridCellSingle)) {
////                marginalClusterCellBlock(cluster);
//            }
//        }
    }

    KPClusterGridCopy(&_clusterGrid, offsetX, offsetY, nil);

    *clusterGrid = _clusterGrid;
}


void KPClusterGridCopy(kp_cluster_grid_t **clusterGrid, NSInteger offsetX, NSInteger offsetY, void(^marginalClusterCellBlock)(kp_cluster_t *clusterCell)) {
    assert(clusterGrid && *clusterGrid);

    if (offsetX == 0 && offsetY == 0) {
        return;
    }

    NSLog(@"KPClusterGridCopy() for offset %d %d", offsetX, offsetY);
    
    kp_cluster_grid_t *_clusterGrid = *clusterGrid;
    kp_cluster_t *cluster;

    NSUInteger gridSizeX = _clusterGrid->size.X;
    NSUInteger gridSizeY = _clusterGrid->size.Y;

    if (offsetY > 0) {
        if (offsetX >= 0) {
            for (int col = 1; col < (1 + offsetY); col++) {
                for (int row = 1; row < (1 + gridSizeX); row++) {
                    KPClusterStorageClusterRemove(_clusterGrid->storage, _clusterGrid->grid[col][row]);
                }
            }

            for (int col = (1 + offsetY); col < (gridSizeY + 1); col++) {
                for (int row = 1; row < (1 + offsetX); row++) {
                    KPClusterStorageClusterRemove(_clusterGrid->storage, _clusterGrid->grid[col][row]);
                }

                for (int row = (1 + offsetX); row < (gridSizeX + 1); row++) {
                    _clusterGrid->grid[col - offsetY][row - offsetX] = _clusterGrid->grid[col][row];
                }

                for (int row = (gridSizeX + 1 - offsetX); row < (gridSizeX + 1); row++) {
                    _clusterGrid->grid[col - offsetY][row] = NULL;
                }
            }

            for (int col = (gridSizeY + 1 - offsetY); col < (gridSizeY + 1); col++) {
                for (int row = 1; row < (gridSizeX + 1); row++) {
                    _clusterGrid->grid[col][row] = NULL;
                }
            }
        }

        // -2, +2
        else {
            offsetX = abs(offsetX);

            for (int col = 1; col < (1 + offsetY); col++) {
                for (int row = 1; row < (1 + gridSizeX); row++) {
                    KPClusterStorageClusterRemove(_clusterGrid->storage, _clusterGrid->grid[col][row]);
                }
            }

            for (int col = (1 + offsetY); col < (gridSizeY + 1); col++) {
                for (int row = (gridSizeX + 1 - offsetX); row < (gridSizeX + 1); row++) {
                    KPClusterStorageClusterRemove(_clusterGrid->storage, _clusterGrid->grid[col][row]);
                }

                for (int row = 1; row < (1 + offsetX); row++) {
                    _clusterGrid->grid[col - offsetY][row + offsetX] = _clusterGrid->grid[col][row];
                }

                for (int row = 1; row < (1 + offsetX); row++) {
                    _clusterGrid->grid[col - offsetY][row] = NULL;
                }
            }

            for (int col = (gridSizeY + 1 - offsetY); col < (gridSizeY + 1); col++) {
                for (int row = 1; row < (gridSizeX + 1); row++) {
                    _clusterGrid->grid[col][row] = NULL;
                }
            }
        }

    } else if (offsetY < 0) {
        if (offsetX <= 0) {
            // -1, -1
            offsetX = abs(offsetX);
            offsetY = abs(offsetY);

            for (int col = (gridSizeY + 1 - offsetY); col < (gridSizeY + 1); col++) {
                for (int row = 1; row < (gridSizeX + 1); row++) {
                    KPClusterStorageClusterRemove(_clusterGrid->storage, _clusterGrid->grid[col][row]);
                }
            }

            for (int col = (gridSizeY - offsetY); col > 0; col--) {
                for (int row = (gridSizeX + 1 - offsetX); row < (gridSizeX + 1); row++) {
                    KPClusterStorageClusterRemove(_clusterGrid->storage, _clusterGrid->grid[col][row]);
                }

                for (int row = 1; row < (gridSizeX + 1 - offsetX); row++) {
                    _clusterGrid->grid[col + offsetY][row + offsetX] = _clusterGrid->grid[col][row];
                }

                for (int row = 1; row < (1 + offsetX); row++) {
                    _clusterGrid->grid[col + offsetY][row] = NULL;
                }
            }

            for (int col = 1; col < (1 + offsetY); col++) {
                for (int row = 1; row < (gridSizeX + 1); row++) {
                    _clusterGrid->grid[col][row] = NULL;
                }
            }

        // +2, -2
        } else {
            offsetY = abs(offsetY);

            for (int col = (gridSizeY + 1 - offsetY); col < (gridSizeY + 1); col++) {
                for (int row = 1; row < (gridSizeX + 1); row++) {
                    KPClusterStorageClusterRemove(_clusterGrid->storage, _clusterGrid->grid[col][row]);
                }
            }

            for (int col = 1; col < (1 + offsetY); col++) {
                for (int row = 1; row < (1 + offsetX); row++) {
                    KPClusterStorageClusterRemove(_clusterGrid->storage, _clusterGrid->grid[col][row]);
                }

                for (int row = (1 + offsetX); row < (gridSizeX + 1); row++) {
                    _clusterGrid->grid[col + offsetY][row - offsetX] = _clusterGrid->grid[col][row];
                }

                for (int row = (gridSizeX + 1 - offsetX); row < (gridSizeX + 1); row++) {
                    _clusterGrid->grid[col + offsetY][row] = NULL;
                }
            }

            for (int col = 1; col < (1 + abs(offsetY)); col++) {
                for (int row = 1; row < (gridSizeX + 1); row++) {
                    _clusterGrid->grid[col][row] = NULL;
                }
            }

        }
    } else {
        if (offsetX > 0) {
            for (int col = 1; col < (gridSizeY + 1); col++) {
                for (int row = 1; row < (1 + offsetX); row++) {
                    KPClusterStorageClusterRemove(_clusterGrid->storage, _clusterGrid->grid[col][row]);
                }

                memmove(_clusterGrid->grid[col] + 1, _clusterGrid->grid[col] + 1 + offsetX, (gridSizeX - offsetX) * sizeof(kp_cluster_t *));

                for (int row = (gridSizeX + 1 - offsetX); row < (gridSizeX + 1); row++) {
                    _clusterGrid->grid[col][row] = NULL;
                }
            }
        } else {
            offsetX = abs(offsetX);

            for (int col = 1; col < (gridSizeY + 1); col++) {
                for (int row = (gridSizeX + 1 - offsetX); row < (gridSizeX + 1); row++) {
                    KPClusterStorageClusterRemove(_clusterGrid->storage, _clusterGrid->grid[col][row]);
                }

                memmove(_clusterGrid->grid[col] + 1 + offsetX, _clusterGrid->grid[col] + 1, (gridSizeX - offsetX) * sizeof(kp_cluster_t *));

                for (int row = 1; row < (1 + offsetX); row++) {
                    _clusterGrid->grid[col][row] = NULL;
                }
            }
        }
    }
}


void KPClusterDebug(kp_cluster_t *cluster) {
    NSLog(@"Cluster (index, type, quadrant): (%d, %d, %d)", cluster->annotationIndex, cluster->clusterType, cluster->distributionQuadrant);
}


