//
//  FRZDatabaseMappable.h
//  Forza Football
//
//  Created by Joel Ekström on 2018-02-01.
//  Copyright © 2018 FootballAddicts. All rights reserved.
//

#import <Foundation/Foundation.h>
@import UIKit;

NS_ASSUME_NONNULL_BEGIN

/**
 This protocol can be used to listen to database updates from an FRZDatabaseViewMapper.
 The functions match UICollectionView, so it's already compatible. A UITableView-extension
 is provided below.

 This is meant to make the FRZDatabaseViewMapper agnostic to if it's updating a table view
 or collection view, but can be used to implement any similar view.
 */
@protocol FRZDatabaseMappable <NSObject>

@property (nonatomic, readonly) NSInteger numberOfSections;

- (void)reloadData;

- (void)insertSections:(NSIndexSet *)sections;
- (void)deleteSections:(NSIndexSet *)sections;

- (void)insertItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths;
- (void)deleteItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths;
- (void)reloadItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths;
- (void)moveItemAtIndexPath:(NSIndexPath *)indexPath toIndexPath:(NSIndexPath *)newIndexPath;

- (void)frz_performBatchUpdates:(void (NS_NOESCAPE ^ _Nullable)(void))updates completion:(void (^ _Nullable)(BOOL finished))completion;

@end

@interface UITableView (FRZDatabaseMappable) <FRZDatabaseMappable>

@end

@interface UICollectionView (FRZDatabaseMappable) <FRZDatabaseMappable>

@end

NS_ASSUME_NONNULL_END
