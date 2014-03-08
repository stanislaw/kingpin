//
// Copyright 2012 Bryan Bonczek
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "KPAnnotationTree.h"
#import "KPAnnotationTree_Private.h"

#import "KPTreeNode.h"

#import "KPAnnotation.h"


#if 0
#define BBTreeLog(...) NSLog(__VA_ARGS__)
#else
#define BBTreeLog(...) ((void) 0)
#endif


#define KP_LIKELY(x) __builtin_expect(!!(x), 1)

typedef struct {
    __unsafe_unretained id <MKAnnotation> annotation;
    MKMapPoint mapPoint;
} kp_internal_annotation_t;

typedef enum {
    KPAnnotationTreeAxisX = 1,
    KPAnnotationTreeAxisY = 2,
} KPAnnotationTreeAxis;

@implementation KPAnnotationTree

- (id)initWithAnnotations:(NSArray *)annotations {
    
    self = [super init];
    
    if(self){
        self.annotations = [NSSet setWithArray:annotations];
        [self buildTree:annotations];
    }
    
    return self;
}

#pragma mark - Search


- (NSArray *)annotationsInMapRect:(MKMapRect)rect totalMapPoint:(MKMapPoint *)totalMapPoint numberOfAnnotations:(NSUInteger *)numberOfAnnotations {

    NSMutableArray *result = [NSMutableArray array];

    [self doSearchInMapRect:rect
         mutableAnnotations:result
                    curNode:self.root
                   curLevel:0
              totalMapPoint:totalMapPoint numberOfAnnotations:numberOfAnnotations];

    return result;
}


- (void)doSearchInMapRect:(MKMapRect)mapRect
       mutableAnnotations:(NSMutableArray *)annotations
                  curNode:(KPTreeNode *)curNode
                 curLevel:(NSInteger)level
            totalMapPoint:(MKMapPoint *)totalMapPoint
      numberOfAnnotations:(NSUInteger *)numberOfAnnotations {

    if (curNode == nil) {
        return;
    }

    if (MKMapRectContainsRect(mapRect, curNode.mapRect)) {
        if (curNode.numberOfAnnotations > 1 || *numberOfAnnotations > 1) {
            (*numberOfAnnotations) += curNode.numberOfAnnotations;

            MKMapPoint mapPoint = (*totalMapPoint);
            mapPoint.x += curNode.totalMapPoint.x;
            mapPoint.y += curNode.totalMapPoint.y;
            (*totalMapPoint) = mapPoint;

            return;
        }
    }

    MKMapPoint mapPoint = curNode.mapPoint;

    if (MKMapRectContainsPoint(mapRect, mapPoint)){
        [annotations addObject:curNode.annotation];
        (*numberOfAnnotations)++;

        MKMapPoint mapPoint = (*totalMapPoint);
        mapPoint.x += curNode.mapPoint.x;
        mapPoint.y += curNode.mapPoint.y;
        (*totalMapPoint) = mapPoint;

    }

    KPAnnotationTreeAxis axis = (level & 1) == 0 ? KPAnnotationTreeAxisX : KPAnnotationTreeAxisY;

    double val, minVal, maxVal;

    if (axis == KPAnnotationTreeAxisX) {
        val    = mapPoint.x;
        minVal = mapRect.origin.x;
        maxVal = mapRect.origin.x + mapRect.size.width;
    } else {
        val    = mapPoint.y;
        minVal = mapRect.origin.y;
        maxVal = mapRect.origin.y + mapRect.size.height;
    }

    if (maxVal < val) {

        [self doSearchInMapRect:mapRect
             mutableAnnotations:annotations
                        curNode:curNode.left
                       curLevel:(level + 1)
                  totalMapPoint:totalMapPoint numberOfAnnotations:numberOfAnnotations];
    }
    else if (minVal > val) {

        [self doSearchInMapRect:mapRect
             mutableAnnotations:annotations
                        curNode:curNode.right
                       curLevel:(level + 1)
                  totalMapPoint:totalMapPoint numberOfAnnotations:numberOfAnnotations];
    }
    else {

        [self doSearchInMapRect:mapRect
             mutableAnnotations:annotations
                        curNode:curNode.left
                       curLevel:(level + 1)
                  totalMapPoint:totalMapPoint numberOfAnnotations:numberOfAnnotations];

        [self doSearchInMapRect:mapRect
             mutableAnnotations:annotations
                        curNode:curNode.right
                       curLevel:(level + 1)
                  totalMapPoint:totalMapPoint numberOfAnnotations:numberOfAnnotations];
    }
    
}

#pragma mark - MKMapView


#pragma mark - Tree Building (Private)


- (void)buildTree:(NSArray *)annotations {
    NSUInteger count = annotations.count;

    __block
    kp_internal_annotation_t *annotationsX = malloc(count * sizeof(kp_internal_annotation_t));
    kp_internal_annotation_t *annotationsY = malloc(count * sizeof(kp_internal_annotation_t));

    [annotations enumerateObjectsUsingBlock:^(id <MKAnnotation> annotation, NSUInteger idx, BOOL *stop) {
        MKMapPoint mapPoint = MKMapPointForCoordinate(annotation.coordinate);

        kp_internal_annotation_t _annotation;
        _annotation.annotation = annotation;
        _annotation.mapPoint = mapPoint;

        annotationsX[idx] = _annotation;
    }];

    memcpy(annotationsY, annotationsX, count * sizeof(kp_internal_annotation_t));

    qsort_b(annotationsX, count, sizeof(kp_internal_annotation_t), ^int(const void *a1, const void *a2) {
        kp_internal_annotation_t *annotation1 = (kp_internal_annotation_t *)a1;
        kp_internal_annotation_t *annotation2 = (kp_internal_annotation_t *)a2;

        if (annotation1->mapPoint.x > annotation2->mapPoint.x) {
            return NSOrderedDescending;
        }

        if (annotation1->mapPoint.x < annotation2->mapPoint.x) {
            return NSOrderedAscending;
        }

        return NSOrderedSame;
    });

    qsort_b(annotationsY, count, sizeof(kp_internal_annotation_t), ^int(const void *a1, const void *a2) {
        kp_internal_annotation_t *annotation1 = (kp_internal_annotation_t *)a1;
        kp_internal_annotation_t *annotation2 = (kp_internal_annotation_t *)a2;

        if (annotation1->mapPoint.y > annotation2->mapPoint.y) {
            return NSOrderedDescending;
        }

        if (annotation1->mapPoint.y < annotation2->mapPoint.y) {
            return NSOrderedAscending;
        }

        return NSOrderedSame;
    });

    self.root = [self buildTree:annotationsX annotationsY:annotationsY count:count mapRect:MKMapRectWorld level:0];

    free(annotationsX);
    free(annotationsY);
}

- (KPTreeNode *)buildTree:(kp_internal_annotation_t *)annotationsX annotationsY:(kp_internal_annotation_t *)annotationsY count:(NSUInteger)count mapRect:(MKMapRect)mapRect level:(NSInteger)curLevel {
    if (count == 0) {
        return nil;
    }
    
    KPTreeNode *n = [[KPTreeNode alloc] init];

    n.mapRect = mapRect;
    n.numberOfAnnotations = count;

    // Prefer machine way of doing odd/even check
    KPAnnotationTreeAxis axis = (curLevel & 1) == 0 ? KPAnnotationTreeAxisX : KPAnnotationTreeAxisY;

    if (axis == KPAnnotationTreeAxisX) {
        NSUInteger medianIdx = count / 2;

        kp_internal_annotation_t medianAnnotation = annotationsX[medianIdx];
        n.annotation = medianAnnotation.annotation;
        n.mapPoint = medianAnnotation.mapPoint;

        double splittingX = n.mapPoint.x;

        kp_internal_annotation_t tmpAnnotation;
        while (medianIdx > 0 && (tmpAnnotation = annotationsX[medianIdx - 1]).mapPoint.x == n.mapPoint.x) {
            medianIdx--;

            n.annotation = tmpAnnotation.annotation;
            n.mapPoint = tmpAnnotation.mapPoint;
        }

        kp_internal_annotation_t *leftAnnotationsY  = malloc(medianIdx * sizeof(kp_internal_annotation_t));
        kp_internal_annotation_t *rightAnnotationsY = malloc((count - medianIdx - 1) * sizeof(kp_internal_annotation_t));

        NSUInteger leftAnnotationsYCount = 0;
        NSUInteger rightAnnotationsYCount = 0;

        for (NSUInteger i = 0; i < count; i++) {
            kp_internal_annotation_t annotation = annotationsY[i];

            MKMapPoint totalMapPoint = n.totalMapPoint;
            totalMapPoint.x += annotation.mapPoint.x;
            totalMapPoint.y += annotation.mapPoint.y;

            n.totalMapPoint = totalMapPoint;

            if (KP_LIKELY([annotation.annotation isEqual:n.annotation] == NO)) {
                if (annotation.mapPoint.x < splittingX) {
                    leftAnnotationsY[leftAnnotationsYCount++] = annotation;
                } else {
                    rightAnnotationsY[rightAnnotationsYCount++] = annotation;
                }
            }
        }

        // Ensure integrity
        NSAssert(leftAnnotationsYCount == medianIdx, nil);
        NSAssert(rightAnnotationsYCount == (count - medianIdx - 1), nil);

        kp_internal_annotation_t *leftAnnotationsX = annotationsX;
        kp_internal_annotation_t *rightAnnotationsX = annotationsX + (medianIdx + 1);

        MKMapRect leftMapRect, rightMapRect;

        double fraction = 0.000001;
        MKMapRectDivide(mapRect, &leftMapRect, &rightMapRect, splittingX - MKMapRectGetMinX(mapRect), CGRectMinXEdge);

        leftMapRect.size.width -= fraction;

        n.left = [self buildTree:leftAnnotationsX annotationsY:leftAnnotationsY count:medianIdx mapRect:leftMapRect level:(curLevel + 1)];
        n.right = [self buildTree:rightAnnotationsX annotationsY:rightAnnotationsY count:(count - medianIdx - 1) mapRect:rightMapRect level:(curLevel + 1)];

        free(leftAnnotationsY);
        free(rightAnnotationsY);
    } else {
        NSInteger medianIdx = count / 2;

        kp_internal_annotation_t medianAnnotation = annotationsY[medianIdx];
        n.annotation = medianAnnotation.annotation;
        n.mapPoint = medianAnnotation.mapPoint;

        double splittingY = n.mapPoint.y;

        kp_internal_annotation_t tmpAnnotation;
        while (medianIdx > 0 && (tmpAnnotation = annotationsY[medianIdx - 1]).mapPoint.y == n.mapPoint.y) {
            medianIdx--;

            n.annotation = tmpAnnotation.annotation;
            n.mapPoint = tmpAnnotation.mapPoint;
        }

        kp_internal_annotation_t *leftAnnotationsX  = malloc(medianIdx * sizeof(kp_internal_annotation_t));
        kp_internal_annotation_t *rightAnnotationsX = malloc((count - medianIdx - 1) * sizeof(kp_internal_annotation_t));

        NSUInteger leftAnnotationsXCount = 0;
        NSUInteger rightAnnotationsXCount = 0;

        for (NSUInteger i = 0; i < count; i++) {
            kp_internal_annotation_t annotation = annotationsX[i];

            MKMapPoint totalMapPoint = n.totalMapPoint;
            totalMapPoint.x += annotation.mapPoint.x;
            totalMapPoint.y += annotation.mapPoint.y;

            n.totalMapPoint = totalMapPoint;

            if (KP_LIKELY([annotation.annotation isEqual:n.annotation] == NO)) {
                if (annotation.mapPoint.y < splittingY) {
                    leftAnnotationsX[leftAnnotationsXCount++] = annotation;
                } else {
                    rightAnnotationsX[rightAnnotationsXCount++] = annotation;
                }
            }
        }

        // Ensure integrity
        NSAssert(leftAnnotationsXCount == medianIdx, nil);
        NSAssert(rightAnnotationsXCount == (count - medianIdx - 1), nil);

        kp_internal_annotation_t *leftAnnotationsY = annotationsY;
        kp_internal_annotation_t *rightAnnotationsY = annotationsY + (medianIdx + 1);

        MKMapRect leftMapRect, rightMapRect;

        double fraction = 0.000001;

        MKMapRectDivide(mapRect, &leftMapRect, &rightMapRect, splittingY - MKMapRectGetMinY(mapRect), CGRectMinYEdge);

        leftMapRect.size.height -= fraction;

        n.left = [self buildTree:leftAnnotationsX annotationsY:leftAnnotationsY count:medianIdx mapRect:leftMapRect level:(curLevel + 1)];
        n.right = [self buildTree:rightAnnotationsX annotationsY:rightAnnotationsY count:(count - medianIdx - 1) mapRect:rightMapRect level:(curLevel + 1)];

        free(leftAnnotationsX);
        free(rightAnnotationsX);
    }

    return n;
}

@end
