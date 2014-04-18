//
//  kingpinTests.m
//  kingpinTests
//
//  Created by Stanislaw Pankevich on 08/03/14.
//
//

#import "TestHelpers.h"

#import "KPGridClusteringAlgorithm.h"
#import "KPGridClusteringAlgorithm_Private.h"

#import "KPAnnotation.h"
#import "KPAnnotationTree.h"

#import "KPGeometry.h"

#import "TestAnnotation.h"

@interface KPClusterGridTests : XCTestCase
@end

@implementation KPClusterGridTests

/*
- (void)testKPClusterGridMergeWithOldClusterGrid {

    NSUInteger gridSizeX = 4, gridSizeY = 4;

    kp_cluster_t   *clusterStorage = NULL;
    kp_cluster_grid_t *clusterGrid;
    KPClusterGridInit(&clusterGrid, gridSizeX, gridSizeY);

    clusterStorage = realloc(clusterStorage, (gridSizeX + 2) * (gridSizeY + 2) * sizeof(kp_cluster_t));

    clusterGrid    = realloc(clusterGrid, (gridSizeX + 2) * sizeof(kp_cluster_t **));

    if (clusterGrid == NULL || clusterStorage == NULL) {
        exit(1);
    }

    memset(clusterGrid, 0, (gridSizeX + 2) * sizeof(kp_cluster_t **));

    for (int i = 0; i < (gridSizeX + 2); i++) {
        clusterGrid->grid[i] = realloc(clusterGrid->grid[i], (gridSizeY + 2) * sizeof(kp_cluster_t *));

        if (clusterGrid->grid[i] == NULL) {
            exit(1);
        }
    }

    void (^resetClusterGrid)(void) = ^(void) {
        for (int i = 0; i < (gridSizeX + 2); i++) {
            memset(clusterGrid->grid[i], 0, (gridSizeY + 2) * sizeof(kp_cluster_t *));
        }

        for (int i = 0; i < (gridSizeX + 2); i++) {
            for (int j = 0; j < (gridSizeY + 2); j++) {
                assert(clusterGrid->grid[i][j] == NULL);
            }
        }
    };

    void (^fillClusterGrid)(void) = ^(void) {
        NSUInteger clusterIndex = 0;

        for (int j = 1; j < (gridSizeY + 1); j++) {
            for (int i = 1; i < (gridSizeX + 1); i++) {
                kp_cluster_t *cluster = clusterStorage + clusterIndex;
                cluster->annotationIndex = clusterIndex;
                cluster->clusterType = KPClusterGridCellSingle;
                cluster->annotation = nil;
                cluster->distributionQuadrant = 0;

                clusterGrid->grid[i][j] = cluster;
                
                clusterIndex++;
            }
        }
    };

    {
        resetClusterGrid();
        fillClusterGrid();
        printClusterGrid();

        KPClusterGridMergeWithOldClusterGrid(clusterGrid, 1, 1, ^(kp_cluster_t *cluster){
            NSLog(@"%lu", (unsigned long)cluster->annotationIndex);
        });

        printClusterGrid();

        XCTAssertTrue(clusterGrid->grid[3][1]->annotationIndex == 7);
        XCTAssertTrue(clusterGrid->grid[3][2]->annotationIndex == 11);
        XCTAssertTrue(clusterGrid->grid[3][3]->annotationIndex == 15);
        XCTAssertTrue(clusterGrid->grid[1][3]->annotationIndex == 13);
        XCTAssertTrue(clusterGrid[2][3]->annotationIndex == 14);

        printf("\n");
    }

    return;
    
    {
        resetClusterGrid();
        fillClusterGrid();
        printClusterGrid();

        KPClusterGridMergeWithOldClusterGrid(clusterGrid, gridSizeX, gridSizeY, -1, -1, ^(kp_cluster_t *cluster){
            NSLog(@"%lu", (unsigned long)cluster->annotationIndex);
        });

        printClusterGrid();

        XCTAssertTrue(clusterGrid[2][2]->annotationIndex == 0);
        XCTAssertTrue(clusterGrid[3][2]->annotationIndex == 1);
        XCTAssertTrue(clusterGrid[4][2]->annotationIndex == 2);
        XCTAssertTrue(clusterGrid[2][3]->annotationIndex == 4);
        XCTAssertTrue(clusterGrid[2][4]->annotationIndex == 8);

        printf("\n");
    }

    {
        resetClusterGrid();
        fillClusterGrid();

        KPClusterGridMergeWithOldClusterGrid(clusterGrid, gridSizeX, gridSizeY, 1, -1, ^(kp_cluster_t *cluster){
            NSLog(@"%lu", (unsigned long)cluster->annotationIndex);
        });

        XCTAssertTrue(clusterGrid[0][0] == NULL);
        XCTAssertTrue(clusterGrid[1][1] == NULL);

        XCTAssertTrue(clusterGrid[1][2]->annotationIndex == 1);
        XCTAssertTrue(clusterGrid[2][2]->annotationIndex == 2);
        XCTAssertTrue(clusterGrid[3][2]->annotationIndex == 3);
        XCTAssertTrue(clusterGrid[3][3]->annotationIndex == 7);
        XCTAssertTrue(clusterGrid[3][4]->annotationIndex == 11);

        printClusterGrid();
    }


    for (int i = 0; i < (gridSizeX + 2); i++) {
        free(clusterGrid[i]);
    }


    free(clusterGrid);
    free(clusterStorage);
}
*/


- (void)testKPClusterGridCopy {
    NSUInteger gridSizeX = 4, gridSizeY = 4;

    kp_cluster_t   *clusterStorage = NULL;
    kp_cluster_grid_t *clusterGrid = NULL;
    KPClusterGridInit(&clusterGrid, gridSizeX, gridSizeY);

    clusterStorage = realloc(clusterStorage, (gridSizeX + 2) * (gridSizeY + 2) * sizeof(kp_cluster_t));

    void (^fillClusterGrid)(void) = ^(void) {
        NSUInteger clusterIndex = 0;

        for (int j = 1; j < (gridSizeY + 1); j++) {
            for (int i = 1; i < (gridSizeX + 1); i++) {
                kp_cluster_t *cluster = clusterStorage + clusterIndex;
                cluster->annotationIndex = clusterIndex + 1;
                cluster->clusterType = KPClusterGridCellSingle;
                cluster->annotation = nil;
                cluster->distributionQuadrant = 0;

                clusterGrid->grid[i][j] = cluster;

                clusterIndex++;
            }
        }
    };

    // +1, +1
    {
        fillClusterGrid();

        KPClusterGridDebug(clusterGrid);

        NSUInteger offsetX = 1;
        NSUInteger offsetY = 1;

        KPClusterGridCopy(&clusterGrid, offsetX, offsetY, nil);

        XCTAssertTrue(clusterGrid->grid[0][0] == NULL);

        XCTAssertTrue(clusterGrid->grid[1][1]->annotationIndex == 6);
        XCTAssertTrue(clusterGrid->grid[2][1]->annotationIndex == 7);
        XCTAssertTrue(clusterGrid->grid[1][2]->annotationIndex == 10);
        XCTAssertTrue(clusterGrid->grid[2][2]->annotationIndex == 11);

        KPClusterGridDebug(clusterGrid);
    }

    // +2, +2
    {
        fillClusterGrid();
        
        KPClusterGridDebug(clusterGrid);

        NSUInteger offsetX = 2;
        NSUInteger offsetY = 2;
        
        KPClusterGridCopy(&clusterGrid, offsetX, offsetY, nil);

        XCTAssertTrue(clusterGrid->grid[0][0] == NULL);

        XCTAssertTrue(clusterGrid->grid[1][1]->annotationIndex == 11);
        XCTAssertTrue(clusterGrid->grid[2][1]->annotationIndex == 12);
        XCTAssertTrue(clusterGrid->grid[1][2]->annotationIndex == 15);
        XCTAssertTrue(clusterGrid->grid[2][2]->annotationIndex == 16);

        KPClusterGridDebug(clusterGrid);
    }

    // +3, +3
    {
        fillClusterGrid();

        KPClusterGridDebug(clusterGrid);

        NSUInteger offsetX = 3;
        NSUInteger offsetY = 3;

        KPClusterGridCopy(&clusterGrid, offsetX, offsetY, nil);

        XCTAssertTrue(clusterGrid->grid[0][0] == NULL);

        XCTAssertTrue(clusterGrid->grid[1][1]->annotationIndex == 16);

        KPClusterGridDebug(clusterGrid);
    }

    // +2, +1
    {
        fillClusterGrid();

        KPClusterGridDebug(clusterGrid);

        NSUInteger offsetX = 2;
        NSUInteger offsetY = 1;

        KPClusterGridCopy(&clusterGrid, offsetX, offsetY, nil);

        XCTAssertTrue(clusterGrid->grid[0][0] == NULL);

        XCTAssertTrue(clusterGrid->grid[1][1]->annotationIndex == 7);

        KPClusterGridDebug(clusterGrid);
    }

}



@end



