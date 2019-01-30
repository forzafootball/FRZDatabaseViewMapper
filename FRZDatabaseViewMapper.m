//
//  FRZDatabaseViewMapper.m
//  Forza Football
//
//  Created by Joel Ekström on 2018-02-01.
//  Copyright © 2018 FootballAddicts. All rights reserved.
//

#import "FRZDatabaseViewMapper.h"
#import <YapDatabase/YapDatabaseView.h>

/**
 A storage object for batch updates. Add updates to this items, and then
 when done, call updateView to perform them all at once.
 */
@interface FRZAggregatedViewChanges : NSObject

- (void)insertSection:(NSUInteger)section;
- (void)deleteSection:(NSUInteger)section;
- (void)insertIndexPathForItem:(NSUInteger)item inSection:(NSUInteger)section;
- (void)updateIndexPathForItem:(NSUInteger)item inSection:(NSUInteger)section;
- (void)deleteIndexPathForItem:(NSUInteger)item inSection:(NSUInteger)section;
- (void)moveIndexPathForItem:(NSUInteger)oldItem inSection:(NSUInteger)oldSection
          toIndexPathForItem:(NSUInteger)newItem inSection:(NSUInteger)newSection;

- (BOOL)hasAnyChanges;
- (void)updateView:(id<FRZDatabaseMappable>)view;

@end

@interface FRZDatabaseViewMapper()

@property (nonatomic, strong) YapDatabaseConnection *connection;

@end

@implementation FRZDatabaseViewMapper

- (instancetype)initWithConnection:(YapDatabaseConnection *)connection updateNotificationName:(NSNotificationName)updateNotificationName
{
    if (self = [super init]) {
        if (!connection.isInLongLivedReadTransaction) {
            [NSException raise:NSInternalInconsistencyException format:@"%@ requires a connection in a long lived read transaction", NSStringFromClass(self.class)];
        }

        self.connection = connection;
        self.shouldAnimateUpdates = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(databaseConnectionDidUpdate:) name:updateNotificationName object:connection];
    }
    return self;
}

#pragma mark - Public

- (void)setView:(id<FRZDatabaseMappable>)view
{
    _view = view;
    if (self.activeViewMappings.count > 0) {
        [_view reloadData];
    }
}

- (NSUInteger)numberOfSections
{
    return [[self.activeViewMappings valueForKeyPath:@"@sum.numberOfSections"] integerValue];
}

- (NSUInteger)numberOfItemsInSection:(NSUInteger)section
{
    YapDatabaseViewMappings *mappings = nil;
    NSUInteger actualSection = [self getGroup:nil mappings:&mappings forSection:section];
    return [mappings numberOfItemsInSection:actualSection];
}

- (NSString *)groupForSection:(NSUInteger)section
{
    NSString *group = nil;
    [self getGroup:&group mappings:nil forSection:section];
    return group;
}

- (YapDatabaseViewMappings *)mappingsForSection:(NSUInteger)section withInternalSection:(NSUInteger *)internalSection
{
    YapDatabaseViewMappings *mappings = nil;
    NSUInteger sectionWithinMappings = [self getGroup:nil mappings:&mappings forSection:section];
    if (internalSection) {
        *internalSection = sectionWithinMappings;
    }
    return mappings;
}

- (NSRange)sectionRangeForMappings:(YapDatabaseViewMappings *)mappings
{
    NSAssert([self.activeViewMappings containsObject:mappings], @"Attempted to get sections for non-managed mappings");
    NSInteger index = [self.activeViewMappings indexOfObject:mappings];
    NSArray<YapDatabaseViewMappings *> *mappingsBefore = [self.activeViewMappings subarrayWithRange:NSMakeRange(0, index)];
    return NSMakeRange([[mappingsBefore valueForKeyPath:@"@sum.numberOfSections"] integerValue], mappings.numberOfSections);
}

- (id)objectAtIndexPath:(NSIndexPath *)indexPath
{
    id object = nil;
    [self getObject:&object collection:nil key:nil metadata:nil atIndexPath:indexPath];
    return object;
}

- (void)getObject:(__autoreleasing id *)object collection:(NSString *__autoreleasing *)collection key:(NSString *__autoreleasing *)key metadata:(__autoreleasing id *)metadata atIndexPath:(NSIndexPath *)indexPath
{
    YapDatabaseViewMappings *mappings = nil;
    NSInteger actualSection = [self getGroup:nil mappings:&mappings forSection:indexPath.section];
    [self.connection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        YapDatabaseViewTransaction *viewTransaction = [transaction extension:mappings.view];
        if (object) {
            *object = [viewTransaction objectAtRow:indexPath.row inSection:actualSection withMappings:mappings];
        }

        if (key || collection) {
            [viewTransaction getKey:key collection:collection forRow:indexPath.row inSection:actualSection withMappings:mappings];
        }

        if (metadata) {
            *metadata = [viewTransaction metadataAtRow:indexPath.row inSection:actualSection withMappings:mappings];
        }
    }];
}

- (void)setActiveViewMappings:(NSArray<YapDatabaseViewMappings *> *)activeViewMappings
{
    [self setActiveViewMappings:activeViewMappings animated:NO];
}

- (void)setActiveViewMappings:(NSArray<YapDatabaseViewMappings *> *)activeViewMappings animated:(BOOL)animated
{
    _activeViewMappings = activeViewMappings;

    if (animated) {
        [self.view frz_performBatchUpdates:^{
            [self updateActiveViewMappings];
            if (self.view.numberOfSections > 0) {
                [self.view deleteSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.view.numberOfSections)]];
            }
            NSInteger numberOfSectionsAfter = [self numberOfSections];
            if (numberOfSectionsAfter > 0) {
                [self.view insertSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, numberOfSectionsAfter)]];
            }
        } completion:nil];
    } else {
        [self updateActiveViewMappings];
        [self.view reloadData];
    }
}

- (void)removeMappings:(YapDatabaseViewMappings *)mappings animated:(BOOL)animated
{
    NSRange sectionRange = [self sectionRangeForMappings:mappings];
    NSMutableArray *mutableMappings = [self.activeViewMappings mutableCopy];
    [mutableMappings removeObject:mappings];
    _activeViewMappings = [mutableMappings copy];
    if (animated) {
        [self.view deleteSections:[[NSIndexSet alloc] initWithIndexesInRange:sectionRange]];
    } else {
        [self.view reloadData];
    }
}

- (void)insertMappings:(YapDatabaseViewMappings *)mappings atIndex:(NSUInteger)index animated:(BOOL)animated
{
    [self.connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [mappings updateWithTransaction:transaction];
    }];

    NSMutableArray *mutableMappings = [self.activeViewMappings mutableCopy];
    [mutableMappings insertObject:mappings atIndex:index];
    _activeViewMappings = [mutableMappings copy];

    if (animated) {
        [self.view insertSections:[[NSIndexSet alloc] initWithIndexesInRange:[self sectionRangeForMappings:mappings]]];
    } else {
        [self.view reloadData];
    }
}

#pragma mark - Private

/**
 Get the group and/or mappings controlling an external section. Also returns the
 actual section within these mappings.
 */
- (NSUInteger)getGroup:(NSString **)group mappings:(YapDatabaseViewMappings **)managingMappings forSection:(NSUInteger)section
{
    NSInteger sectionOffset = 0;
    for (YapDatabaseViewMappings *mappings in self.activeViewMappings) {
        NSInteger numberOfSections = mappings.numberOfSections;
        if (section < numberOfSections + sectionOffset) {
            if (managingMappings) {
                *managingMappings = mappings;
            }

            NSInteger actualSection = section - sectionOffset;
            if (group) {
                *group = mappings.visibleGroups[actualSection];
            }
            return actualSection;
        }
        sectionOffset += numberOfSections;
    }
    [NSException raise:NSInternalInconsistencyException format:@"Attempted to get a group and/or view mappings for a section that is out of range: %i", (int)section];
    return NSNotFound;
}

#pragma mark - Database update handling

- (void)willBeginUpdates
{
    if ([self.delegate respondsToSelector:@selector(databaseViewMapperWillBeginUpdatingView:)]) {
        [self.delegate databaseViewMapperWillBeginUpdatingView:self];
    }
}

- (void)didEndUpdates
{
    if ([self.delegate respondsToSelector:@selector(databaseViewMapperDidEndUpdatingView:)]) {
        [self.delegate databaseViewMapperDidEndUpdatingView:self];
    }
}

- (void)databaseConnectionDidUpdate:(NSNotification *)notification
{
    NSParameterAssert(notification.userInfo[@"notifications"]);

    if (self.activeViewMappings.count == 0) {
        return;
    }

    NSArray *notifications = notification.userInfo[@"notifications"];

    if (![self hasAnyChangesForNotifications:notifications]) {
        [self updateActiveViewMappings];
        return;
    }

    [self willBeginUpdates];

    if (self.shouldAnimateUpdates == NO || ([self.view isKindOfClass:[UIView class]] && [(UIView *)self.view window] == nil)) {
        [self updateActiveViewMappings];
        [self.view reloadData];
        [self didEndUpdates];
        return;
    }
    
    [self.view frz_performBatchUpdates:^{
        FRZAggregatedViewChanges *changes = [self calculateAggregatedChangesForDatabaseNotifications:notifications];
        [changes updateView:self.view];
    } completion:^(BOOL finished) {
        [self didEndUpdates];
    }];
}

/**
 A quick check to see if any of the views currently being managed have any changes since
 the latest update of the connection
 */
- (BOOL)hasAnyChangesForNotifications:(NSArray *)notifications
{
    for (YapDatabaseViewMappings *mappings in self.activeViewMappings) {
        YapDatabaseViewConnection *viewConnection = [self.connection extension:mappings.view];
        if ([viewConnection hasChangesForNotifications:notifications]) {
            return YES;
        }
    }
    return NO;
}

/**
 Updates active view mappings to the latest commit on connection, without
 calculating any changeset
 */
- (void)updateActiveViewMappings
{
    [self.connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        for (YapDatabaseViewMappings *mappings in self.activeViewMappings) {
            [mappings updateWithTransaction:transaction];
        }
    }];
}

/**
 Since section changes and row changes are per view mappings, this function creates an aggregate for all mappings and translates
 the sections into the actual sections seen by the table view.
 */
- (FRZAggregatedViewChanges *)calculateAggregatedChangesForDatabaseNotifications:(NSArray *)notifications
{
    FRZAggregatedViewChanges *changes = [FRZAggregatedViewChanges new];

    // Deletes and reloads work on the table view states _before_ any other updates have happened,
    // while inserts work on the state after the deletes have happened. Therefore, we must keep
    // both the previous and new offsets for each view mapping when we map the changes.
    __block NSInteger sectionOffsetBeforeDeletions = 0;
    __block NSInteger sectionOffsetAfterDeletions = 0;
    [self.activeViewMappings enumerateObjectsUsingBlock:^(YapDatabaseViewMappings *mappings, NSUInteger index, BOOL *stop) {
        NSArray *sectionChanges = nil;
        NSArray *rowChanges = nil;
        NSInteger previousSectionCount = mappings.numberOfSections;
        [[self.connection extension:mappings.view] getSectionChanges:&sectionChanges rowChanges:&rowChanges forNotifications:notifications withMappings:mappings];

        for (YapDatabaseViewSectionChange *change in sectionChanges) {
            if (change.type == YapDatabaseViewChangeDelete) {
                [changes deleteSection:change.index + sectionOffsetBeforeDeletions];
            } else {
                [changes insertSection:change.index + sectionOffsetAfterDeletions];
            }
        }

        for (YapDatabaseViewRowChange *change in rowChanges) {
            switch (change.type) {
                case YapDatabaseViewChangeDelete: {
                    NSUInteger mappedSection = change.indexPath.section + sectionOffsetBeforeDeletions;
                    [changes deleteIndexPathForItem:change.indexPath.item inSection:mappedSection];
                    break;
                }
                case YapDatabaseViewChangeInsert: {
                    NSUInteger mappedSection = change.newIndexPath.section + sectionOffsetAfterDeletions;
                    [changes insertIndexPathForItem:change.newIndexPath.item inSection:mappedSection];
                    break;
                }
                case YapDatabaseViewChangeUpdate: {
                    NSUInteger mappedSection = change.indexPath.section + sectionOffsetBeforeDeletions;
                    [changes updateIndexPathForItem:change.indexPath.item inSection:mappedSection];
                    break;
                }
                case YapDatabaseViewChangeMove: {
                    NSUInteger mappedFromSection = change.indexPath.section + sectionOffsetBeforeDeletions;
                    NSUInteger mappedToSection = change.newIndexPath.section + sectionOffsetAfterDeletions;
                    [changes moveIndexPathForItem:change.indexPath.item inSection:mappedFromSection
                               toIndexPathForItem:change.newIndexPath.item inSection:mappedToSection];
                    break;
                }
            }
        }

        sectionOffsetBeforeDeletions += previousSectionCount;
        sectionOffsetAfterDeletions += mappings.numberOfSections;
    }];

    return changes;
}

@end

@interface FRZAggregatedViewChanges()

@property (nonatomic, strong) NSMutableIndexSet *deletedSections;
@property (nonatomic, strong) NSMutableIndexSet *insertedSections;
@property (nonatomic, strong) NSMutableSet<NSIndexPath *> *deletedIndexPaths;
@property (nonatomic, strong) NSMutableSet<NSIndexPath *> *insertedIndexPaths;
@property (nonatomic, strong) NSMutableSet<NSIndexPath *> *updatedIndexPaths;
@property (nonatomic, strong) NSMutableDictionary<NSIndexPath *, NSIndexPath *> *movedIndexPaths;

@end

@implementation FRZAggregatedViewChanges

- (instancetype)init
{
    if (self = [super init]) {
        self.deletedSections = [NSMutableIndexSet new];
        self.insertedSections = [NSMutableIndexSet new];
        self.deletedIndexPaths = [NSMutableSet new];
        self.insertedIndexPaths = [NSMutableSet new];
        self.updatedIndexPaths = [NSMutableSet new];
        self.movedIndexPaths = [NSMutableDictionary new];
    }
    return self;
}

- (void)insertSection:(NSUInteger)section
{
    [self.insertedSections addIndex:section];
}

- (void)deleteSection:(NSUInteger)section
{
    [self.deletedSections addIndex:section];
}

- (void)insertIndexPathForItem:(NSUInteger)item inSection:(NSUInteger)section
{
    [self insertIndexPath:[NSIndexPath indexPathForItem:item inSection:section]];
}

- (void)deleteIndexPathForItem:(NSUInteger)item inSection:(NSUInteger)section
{
    [self deleteIndexPath:[NSIndexPath indexPathForItem:item inSection:section]];
}

- (void)updateIndexPathForItem:(NSUInteger)item inSection:(NSUInteger)section
{
    if (![self.deletedSections containsIndex:section]) {
        [self.updatedIndexPaths addObject:[NSIndexPath indexPathForItem:item inSection:section]];
    }
}

- (void)insertIndexPath:(NSIndexPath *)indexPath
{
    if (![self.insertedSections containsIndex:indexPath.section]) {
        [self.insertedIndexPaths addObject:indexPath];
    }
}

- (void)deleteIndexPath:(NSIndexPath *)indexPath
{
    if (![self.deletedSections containsIndex:indexPath.section]) {
        [self.deletedIndexPaths addObject:indexPath];
    }
}

- (void)moveIndexPathForItem:(NSUInteger)oldItem inSection:(NSUInteger)oldSection
          toIndexPathForItem:(NSUInteger)newItem inSection:(NSUInteger)newSection
{
    NSIndexPath *oldIndexPath = [NSIndexPath indexPathForItem:oldItem inSection:oldSection];
    NSIndexPath *newIndexPath = [NSIndexPath indexPathForItem:newItem inSection:newSection];
    [self.movedIndexPaths setObject:newIndexPath forKey:oldIndexPath];
}

- (BOOL)hasAnyChanges
{
    return self.deletedSections.count > 0 || self.insertedSections.count > 0 || self.deletedIndexPaths.count > 0 || self.insertedIndexPaths.count > 0 || self.updatedIndexPaths.count > 0 || self.movedIndexPaths.count > 0;
}

/**
 There is a bug (I believe in YapDatabase) which results in there sometimes being
 moves to the same index paths as inserts. This crashes UITableView/UICollectionView,
 so we remove any moves which collide with inserts/deletes
 */
- (void)curateMoves
{
    NSMutableArray *keysToDelete = [NSMutableArray new];
    [self.movedIndexPaths enumerateKeysAndObjectsUsingBlock:^(NSIndexPath *oldIndexPath, NSIndexPath *newIndexPath, BOOL *stop) {
        if ([self.insertedIndexPaths containsObject:newIndexPath] || [self.insertedSections containsIndex:newIndexPath.section]) {
            [keysToDelete addObject:oldIndexPath];
            [self deleteIndexPath:oldIndexPath];
        } else if ([self.deletedIndexPaths containsObject:oldIndexPath] || [self.deletedSections containsIndex:oldIndexPath.section]) {
            [keysToDelete addObject:oldIndexPath];
            [self insertIndexPath:newIndexPath];
        }
    }];
    [self.movedIndexPaths removeObjectsForKeys:keysToDelete];
}

- (void)updateView:(id<FRZDatabaseMappable>)view
{
    [self curateMoves];

    if (self.deletedSections.count > 0) [view deleteSections:self.deletedSections];
    if (self.insertedSections.count > 0) [view insertSections:self.insertedSections];
    if (self.deletedIndexPaths.count > 0) [view deleteItemsAtIndexPaths:self.deletedIndexPaths.allObjects];
    if (self.insertedIndexPaths.count > 0) [view insertItemsAtIndexPaths:self.insertedIndexPaths.allObjects];
    if (self.updatedIndexPaths.count > 0) [view reloadItemsAtIndexPaths:self.updatedIndexPaths.allObjects];

    [self.movedIndexPaths enumerateKeysAndObjectsUsingBlock:^(NSIndexPath *oldIndexPath, NSIndexPath *newIndexPath, BOOL *stop) {
        [view moveItemAtIndexPath:oldIndexPath toIndexPath:newIndexPath];
    }];
}

- (NSString *)description
{
    return [[super description] stringByAppendingFormat:@" (\n  Deleted sections: %@\n  Inserted sections: %@\n  Deleted items: %@\n  Inserted items: %@\n  Reloaded items: %@\n  Moved items: %@", self.deletedSections, self.insertedSections, self.deletedIndexPaths, self.insertedIndexPaths, self.updatedIndexPaths, self.movedIndexPaths];
}

@end
