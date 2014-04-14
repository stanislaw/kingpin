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


void KPClusterGridReset(kp_cluster_t ***clusterGrid) {

}

@implementation KPClusterGridTests

- (void)testKPClusterGridMergeWithOldClusterGrid {

    NSUInteger gridSizeX = 4, gridSizeY = 4;

    kp_cluster_t   *clusterStorage = NULL;
    kp_cluster_t ***clusterGrid    = NULL;

    clusterStorage = realloc(clusterStorage, (gridSizeX + 2) * (gridSizeY + 2) * sizeof(kp_cluster_t));

    clusterGrid    = realloc(clusterGrid, (gridSizeX + 2) * sizeof(kp_cluster_t **));

    if (clusterGrid == NULL || clusterStorage == NULL) {
        exit(1);
    }

    memset(clusterGrid, 0, (gridSizeX + 2) * sizeof(kp_cluster_t **));

    for (int i = 0; i < (gridSizeX + 2); i++) {
        clusterGrid[i] = realloc(clusterGrid[i], (gridSizeY + 2) * sizeof(kp_cluster_t *));

        if (clusterGrid[i] == NULL) {
            exit(1);
        }
    }

    void (^resetClusterGrid)(void) = ^(void) {
        for (int i = 0; i < (gridSizeX + 2); i++) {
            memset(clusterGrid[i], 0, (gridSizeY + 2) * sizeof(kp_cluster_t *));
        }

        /* Validation (Debug, remove later) */
        for (int i = 0; i < (gridSizeX + 2); i++) {
            for (int j = 0; j < (gridSizeY + 2); j++) {
                assert(clusterGrid[i][j] == NULL);
            }
        }
    };

    void (^fillClusterGrid)(void) = ^(void) {
        NSUInteger clusterIndex = 0;

        for (int j = 1; j < (gridSizeY + 1); j++) {
            for (int i = 1; i < (gridSizeX + 1); i++) {
                kp_cluster_t *cluster = clusterStorage + clusterIndex;
                cluster->annotationIndex = clusterIndex;

                clusterGrid[i][j] = cluster;
                
                clusterIndex++;
            }
        }
    };

    void (^printClusterGrid)(void) = ^(void) {
        for (int j = 0; j < (gridSizeY + 2); j++) {
            for (int i = 0; i < (gridSizeX + 2); i++) {
                if (clusterGrid[i][j]) {
                    printf("[%2d ]  ", clusterGrid[i][j]->annotationIndex);
                } else {
                    printf(" NULL  ");
                }
            }
            printf("\n");
        }
    };

    resetClusterGrid();
    fillClusterGrid();
    printClusterGrid();

    KPClusterGridMergeWithOldClusterGrid(clusterGrid, gridSizeX, gridSizeY, 1, 1, ^(kp_cluster_t *cluster){
        NSLog(@"%lu", (unsigned long)cluster->annotationIndex);
    });

    printClusterGrid();

    XCTAssertTrue(clusterGrid[3][1]->annotationIndex == 7);
    XCTAssertTrue(clusterGrid[3][2]->annotationIndex == 11);
    XCTAssertTrue(clusterGrid[3][3]->annotationIndex == 15);
    XCTAssertTrue(clusterGrid[1][3]->annotationIndex == 13);
    XCTAssertTrue(clusterGrid[2][3]->annotationIndex == 14);

    printf("\n");

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


    /*
     TEARDOWN
     */

    for (int i = 0; i < (gridSizeX + 2); i++) {
        free(clusterGrid[i]);
    }


    free(clusterGrid);
    free(clusterStorage);
}

@end



