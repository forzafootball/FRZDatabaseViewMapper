//
//  FRZDatabaseViewMapper.m
//  Forza Football
//
//  Created by Joel Ekström on 2018-02-01.
//  Copyright © 2018 FootballAddicts. All rights reserved.
//

#import "FRZDatabaseViewMapper.h"
#import <YapDatabase/YapDatabaseView.h>

@interface FRZDatabaseViewMapper()

@property (nonatomic, strong) YapDatabaseConnection *connection;

@end

@implementation FRZDatabaseViewMapper

- (instancetype)initWithDatabase:(YapDatabase *)database
{
    if (self = [super init]) {
        self.connection = [database newConnection];
        [self.connection beginLongLivedReadTransaction];
        self.shouldAnimateUpdates = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(yapDatabaseModified:) name:YapDatabaseModifiedNotification object:database];
    }
    return self;
}

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

- (void)setShouldPauseUpdates:(BOOL)shouldPauseUpdates
{
    if (_shouldPauseUpdates == YES && shouldPauseUpdates == NO) {
        [self fastForwardActiveViewMappingsAndViewAnimated:NO];
    }
    _shouldPauseUpdates = shouldPauseUpdates;
}

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
    [self fastForwardActiveViewMappingsAndViewAnimated:animated];
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

/**
 This method is only called if the view mapper is managing its own, internal database connection.
 It begins a new long-lived read transaction and forwards the change notifications to the normal handler
 */
- (void)yapDatabaseModified:(NSNotification *)notification
{
    NSArray<NSNotification *> *changeNotifications = [self.connection beginLongLivedReadTransaction];
    [self updateWithNotifications:changeNotifications];
}

/**
 This method is called when an external YapDatabaseConnection is updated, with the registered
 NSNotificationName. Used when the client app manages the connection.
 */
- (void)databaseConnectionDidUpdate:(NSNotification *)notification
{
    NSParameterAssert(notification.userInfo[@"notifications"]);
    [self updateWithNotifications:notification.userInfo[@"notifications"]];
}

- (void)updateWithNotifications:(NSArray<NSNotification *> *)notifications
{
    if (self.activeViewMappings.count == 0 || self.shouldPauseUpdates) {
        return;
    }

    if (![self hasAnyChangesForNotifications:notifications]) {
        [self updateActiveViewMappings];
        return;
    }

    [self willBeginUpdates];

    if (self.shouldAnimateUpdates == NO || ([self.view isKindOfClass:[UIView class]] && [(UIView *)self.view window] == nil)) {
        [self fastForwardActiveViewMappingsAndViewAnimated:NO];
        [self didEndUpdates];
        return;
    }

    /**
     This is a crash fix for a bug in UITableView and UICollectionView. Reloads are not compatible
     with other types of updates inside the same block of batch updates, so we run them independently
     before.
     More info here: https://github.com/yapstudios/YapDatabase/issues/489
     */
    [self performUpdatesForNotifications:notifications];

    [self.view frz_performBatchUpdates:^{
        [self performInsertsDeletesAndMovesForNotifications:notifications];
    } completion:^(BOOL finished) {
        [self didEndUpdates];
    }];
}

/**
 A quick check to see if any of the views currently being managed have any changes since
 the latest update of the connection
 */
- (BOOL)hasAnyChangesForNotifications:(NSArray<NSNotification *> *)notifications
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
 Fast forwards all active view mappings to the latest database commit,
 and reflects the changes in the view, with an optional animation.
 The animation is a simpler transition, it doesn't actually do
 propert updates/inserts/deletes/moves.
 */
- (void)fastForwardActiveViewMappingsAndViewAnimated:(BOOL)animated
{
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

/**
 Since section changes and row changes are per view mappings, this function will map the changes from individual mappings
 into the actual sections seen by the table view.

 This function will update activeViewMappings to the current database commit, and run
 inserts/deletes/moves but skip updates.
 */
- (void)performInsertsDeletesAndMovesForNotifications:(NSArray *)notifications
{
    // Deletes and work on the table view states _before_ any other updates have happened,
    // while inserts work on the state after the deletes have happened. Therefore, we must keep
    // both the previous and new offsets for each view mapping when we map the changes.
    __block NSInteger sectionOffsetBeforeDeletions = 0;
    __block NSInteger sectionOffsetAfterDeletions = 0;
    [self.activeViewMappings enumerateObjectsUsingBlock:^(YapDatabaseViewMappings *mappings, NSUInteger index, BOOL *stop) {
        NSArray *sectionChanges = nil;
        NSArray *rowChanges = nil;
        NSInteger numberOfSectionsBeforeUpdates = mappings.numberOfSections;
        [[self.connection extension:mappings.view] getSectionChanges:&sectionChanges rowChanges:&rowChanges forNotifications:notifications withMappings:mappings];

        for (YapDatabaseViewSectionChange *change in sectionChanges) {
            if (change.type == YapDatabaseViewChangeDelete) {
                [self.view deleteSections:[NSIndexSet indexSetWithIndex:change.index + sectionOffsetBeforeDeletions]];
            } else {
                [self.view insertSections:[NSIndexSet indexSetWithIndex:change.index + sectionOffsetAfterDeletions]];
            }
        }

        for (YapDatabaseViewRowChange *change in rowChanges) {
            switch (change.type) {
                case YapDatabaseViewChangeDelete: {
                    NSUInteger mappedSection = change.indexPath.section + sectionOffsetBeforeDeletions;
                    [self.view deleteItemsAtIndexPaths:@[[NSIndexPath indexPathForItem:change.indexPath.item inSection:mappedSection]]];
                    break;
                }
                case YapDatabaseViewChangeInsert: {
                    NSUInteger mappedSection = change.newIndexPath.section + sectionOffsetAfterDeletions;
                    [self.view insertItemsAtIndexPaths:@[[NSIndexPath indexPathForItem:change.newIndexPath.item inSection:mappedSection]]];
                    break;
                }
                case YapDatabaseViewChangeUpdate: {
                    // Do nothing here - reloads were handled independently to fix crashes
                    break;
                }
                case YapDatabaseViewChangeMove: {
                    NSUInteger mappedFromSection = change.indexPath.section + sectionOffsetBeforeDeletions;
                    NSUInteger mappedToSection = change.newIndexPath.section + sectionOffsetAfterDeletions;
                    [self.view moveItemAtIndexPath:[NSIndexPath indexPathForItem:change.indexPath.item inSection:mappedFromSection]
                                       toIndexPath:[NSIndexPath indexPathForItem:change.newIndexPath.item inSection:mappedToSection]];
                    break;
                }
            }
        }

        sectionOffsetBeforeDeletions += numberOfSectionsBeforeUpdates;
        sectionOffsetAfterDeletions += mappings.numberOfSections;
    }];
}

/**
 This function will perform all YapDatabaseViewUpdates without updating the view mappings to the current
 commit.
 */
- (void)performUpdatesForNotifications:(NSArray<NSNotification *> *)notifications
{
    __block NSArray<NSIndexPath *> *updatedIndexPaths = nil;
    [self.connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        updatedIndexPaths = [self mappedIndexPathsToReloadForNotifications:notifications transaction:transaction];
    }];
    if (updatedIndexPaths.count > 0) [self.view reloadItemsAtIndexPaths:updatedIndexPaths];
}

/**
 Returns mapped indexPaths for all updated rows in the active viewMappings
 for a set of update notifications.
 */
- (NSArray<NSIndexPath *> *)mappedIndexPathsToReloadForNotifications:(NSArray<NSNotification *> *)notifications
                                                         transaction:(YapDatabaseReadTransaction *)transaction
{
    NSMutableArray<NSIndexPath *> *mappedIndexPaths = [NSMutableArray new];
    NSInteger sectionOffset = 0;
    for (YapDatabaseViewMappings *mappings in self.activeViewMappings) {
        for (NSIndexPath *indexPath in [self indexPathsToReloadForMappings:mappings notifications:notifications transaction:transaction]) {
            [mappedIndexPaths addObject:[NSIndexPath indexPathForItem:indexPath.item inSection:indexPath.section + sectionOffset]];
        }
        sectionOffset += mappings.numberOfSections;
    }
    return mappedIndexPaths;
}

/**
 Returns unmapped indexPaths for all the updated rows for a given set of viewMappings
 and update notifications.
 */
- (NSArray<NSIndexPath *> *)indexPathsToReloadForMappings:(YapDatabaseViewMappings *)mappings
                                            notifications:(NSArray<NSNotification *> *)notifications
                                              transaction:(YapDatabaseReadTransaction *)transaction
{
    NSMutableArray<NSIndexPath *> *indexPaths = [NSMutableArray new];
    YapDatabaseViewTransaction *viewTransaction = (YapDatabaseViewTransaction *)[transaction extension:mappings.view];
    for (NSNotification *notification in notifications) {
        NSArray *changes = notification.userInfo[YapDatabaseExtensionsKey][mappings.view][YapDatabaseViewChangesKey];
        NSIndexSet *updateIndexes = [changes indexesOfObjectsPassingTest:^BOOL(id change, NSUInteger idx, BOOL *stop) {
            return [change isKindOfClass:YapDatabaseViewRowChange.class] && [(YapDatabaseViewRowChange *)change type] == YapDatabaseViewChangeUpdate;
        }];

        [changes enumerateObjectsAtIndexes:updateIndexes options:0 usingBlock:^(YapDatabaseViewRowChange *update, NSUInteger idx, BOOL *stop) {
            NSIndexPath *indexPath = [viewTransaction indexPathForKey:update.collectionKey.key inCollection:update.collectionKey.collection withMappings:mappings];
            if (indexPath) [indexPaths addObject:indexPath];
        }];
    }
    return indexPaths;
}

@end
