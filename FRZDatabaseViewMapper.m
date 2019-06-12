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
@property (nonatomic, strong) NSMutableDictionary<NSIndexPath *, YapCollectionKey *> *cache;

@end

@implementation FRZDatabaseViewMapper

- (instancetype)initWithDatabase:(YapDatabase *)database
{
    if (self = [super init]) {
        _cache = [NSMutableDictionary new];
        _connection = [database newConnection];
        [_connection beginLongLivedReadTransaction];
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

        _cache = [NSMutableDictionary new];
        _connection = connection;
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
    [self.connection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        YapCollectionKey *collectionKey = self.cache[indexPath];
        if (collectionKey == nil) {
            YapDatabaseViewMappings *mappings = nil;
            NSString *collection = nil;
            NSString *key = nil;
            NSInteger actualSection = [self getGroup:nil mappings:&mappings forSection:indexPath.section];
            [[transaction extension:mappings.view] getKey:&key collection:&collection forRow:indexPath.row inSection:actualSection withMappings:mappings];
            collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
            self.cache[indexPath] = collectionKey;
        }

        if (key) *key = collectionKey.key;
        if (object) *object = [transaction objectForKey:collectionKey.key inCollection:collectionKey.collection];
        if (metadata) *metadata = [transaction metadataForKey:collectionKey.key inCollection:collectionKey.collection];
        if (collection) *collection = collectionKey.collection;
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

    if (self.animationStyle != FRZDatabaseViewMapperAnimationStyleFull) {
        [self fastForwardActiveViewMappingsAndViewAnimated:self.animationStyle == FRZDatabaseViewMapperAnimationStyleCrossDissolve];
        [self didEndUpdates];
        return;
    }

    /**
     This is a crash fix for a bug in UITableView and UICollectionView. Reloads are not compatible
     with other types of updates inside the same block of batch updates, so we run them independently
     before. We must make sure that objectAtIndexPath: etc returns objects from the cache during reload,
     since the view mappings will not contain the correct rowid's.
     More info here: https://github.com/yapstudios/YapDatabase/issues/489
     */
    NSSet<YapCollectionKey *> *collectionKeys = [self updatedCollectionKeysInNotifications:notifications];
    NSSet<NSIndexPath *> *updatedIndexPaths = [self.cache keysOfEntriesPassingTest:^BOOL(NSIndexPath *indexPath, YapCollectionKey *collectionKey, BOOL *stop) {
        return [collectionKeys containsObject:collectionKey];
    }];
    if (updatedIndexPaths.count > 0) [self.view reloadItemsAtIndexPaths:updatedIndexPaths.allObjects];

    // Clear the cache, since now we will be doing actual changes to the view, and items will receive new index paths
    [self.cache removeAllObjects];

    [self.view frz_performBatchUpdates:^{
        [self performInsertsDeletesAndMovesForNotifications:notifications];
    } completion:^(BOOL finished) {
        [self didEndUpdates];
    }];
}

- (FRZDatabaseViewMapperAnimationStyle)animationStyle
{
    // Optimization: Don't perform animated updates if the view is not in the window hierarchy
    if ([self.view isKindOfClass:UIView.class] && [(UIView *)self.view window] == nil) {
        return FRZDatabaseViewMapperAnimationStyleNone;
    }
    return _animationStyle;
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
    [self.cache removeAllObjects];
    [self updateActiveViewMappings];
    if (animated && [self.view isKindOfClass:UIView.class]) {
        [UIView transitionWithView:(UIView *)self.view
                          duration:0.22
                           options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                        animations:^{ [self.view reloadData]; }
                        completion:nil];
    } else {
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

- (NSSet<YapCollectionKey *> *)updatedCollectionKeysInNotifications:(NSArray<NSNotification *> *)notifications
{
    NSMutableSet<YapCollectionKey *> *collectionKeys = [NSMutableSet new];
    for (NSNotification *notification in notifications) {
        for (NSDictionary *extension in [notification.userInfo[YapDatabaseExtensionsKey] allValues]) {
            for (id change in extension[YapDatabaseViewChangesKey]) {
                if ([change isKindOfClass:YapDatabaseViewRowChange.class] && [(YapDatabaseViewRowChange *)change type] == YapDatabaseViewChangeUpdate) {
                    [collectionKeys addObject:[(YapDatabaseViewRowChange *)change collectionKey]];
                }
            }
        }
    }
    return collectionKeys;
}

@end
