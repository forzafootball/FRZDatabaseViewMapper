//
//  FRZDatabaseMappableView.m
//  Forza Football
//
//  Created by Joel Ekström on 2018-02-01.
//  Copyright © 2018 FootballAddicts. All rights reserved.
//

#import "FRZDatabaseMappable.h"

@implementation UITableView (FRZDatabaseMappable)

- (void)deleteSections:(NSIndexSet *)sections
{
    [self deleteSections:sections withRowAnimation:UITableViewRowAnimationFade];
}

- (void)insertSections:(NSIndexSet *)sections
{
    [self insertSections:sections withRowAnimation:UITableViewRowAnimationFade];
}

- (void)deleteItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths
{
    [self deleteRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationFade];
}

- (void)insertItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths
{
    [self insertRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationFade];
}

- (void)reloadItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths
{
    [self reloadRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationFade];
}

- (void)moveItemAtIndexPath:(NSIndexPath *)indexPath toIndexPath:(NSIndexPath *)newIndexPath;
{
    [self moveRowAtIndexPath:indexPath toIndexPath:newIndexPath];
}

- (void)frz_performBatchUpdates:(void (NS_NOESCAPE ^ _Nullable)(void))updates completion:(void (^ _Nullable)(BOOL finished))completion
{
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        if (completion) {
            completion(YES);
        }
    }];
    [self beginUpdates];
    updates();
    [self endUpdates];
    [CATransaction commit];
}

@end

@implementation UICollectionView (FRZDatabaseMappable)

- (void)frz_performBatchUpdates:(void (^)(void))updates completion:(void (^)(BOOL finished))completion
{
    [self performBatchUpdates:updates completion:completion];
}

@end
