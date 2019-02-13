//
//  FRZDatabaseViewMapper.h
//  Forza Football
//
//  Created by Joel Ekström on 2018-02-01.
//  Copyright © 2018 FootballAddicts. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseViewMappings.h>
#import "FRZDatabaseMappable.h"

@class FRZDatabaseViewMapper;
@protocol FRZDatabaseViewMapperDelegate <NSObject>

@optional
- (void)databaseViewMapperWillBeginUpdatingView:(FRZDatabaseViewMapper *)mapper;
- (void)databaseViewMapperDidEndUpdatingView:(FRZDatabaseViewMapper *)mapper;

@end

/**
 This class manages keeping a UITableView (or collectionView) updated with animations,
 from a set of one or several view mappings. This is useful if you need to handle more than one
 YapDatabaseViewMappings in your table view (for example to have the same object show up in multiple sections).
 It's also useful to avoid the boilerplate of forwarding database updates to your view.
 */
@interface FRZDatabaseViewMapper : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

/**
 Initialize the viewMapper with a database. The view mapper will create and manage a long-lived
 read connection internally. If you use a permanent long-lived read connection for caching,
 and want the view mapper to read from that, use initWithConnection:updateNotificationName: instead.
 */
- (instancetype)initWithDatabase:(YapDatabase *)database NS_DESIGNATED_INITIALIZER;

/**
 Initialize the viewMapper with a connection and an update notification

 @param connection A connection in a longLivedReadTransaction, typically the UI connection
 @param updateNotificationName The name of the notification posted by NSNotificationCenter when `connection` is updated to a new longLivedReadTransaction.
 @discussion FRZDatabaseViewMapper will listen to NSNotifications with name `updateNotificationName`, where object == `connection`.
 The user info of this notification must contain the key "notifications" which is the array returned when running beginLongLivedReadTransaction on `connection`.
 */
- (instancetype)initWithConnection:(YapDatabaseConnection *)connection updateNotificationName:(NSNotificationName)updateNotificationName NS_DESIGNATED_INITIALIZER;

@property (nonatomic, weak) id<FRZDatabaseViewMapperDelegate> delegate;
@property (nonatomic, assign) BOOL shouldAnimateUpdates; // If NO, calls reloadData instead of animating updates. Defaults to YES

/**
 This property determines what view mappings are visible in the view. If changed, the view will
 reload its data and show the new mappings. The mappings will be updated automatically when the
 database UI connection updates. The order of the view mappings here determine the order
 of the sections in the view.
 */
@property (nonatomic, strong) NSArray<YapDatabaseViewMappings *> *activeViewMappings;
- (void)setActiveViewMappings:(NSArray<YapDatabaseViewMappings *> *)activeViewMappings animated:(BOOL)animated;

/**
 Use these functions to enable/disable specific mappings with an animation.
 Will update the activeViewMappings-array.
 */
- (void)removeMappings:(YapDatabaseViewMappings *)mappings animated:(BOOL)animated;
- (void)insertMappings:(YapDatabaseViewMappings *)mappings atIndex:(NSUInteger)index animated:(BOOL)animated;

/**
 Pausing updates is good when the mapped view disappears. The view mapper will stop listening for changes on the
 database connection which will save in on processing time. Unpausing will forward the current view mappings to the
 latest database commit and reload the view. A good practice is to set pauseUpdates = YES in viewWillDisappear:
 and pauseUpdates = NO in viewWillAppear:.
 */
@property (nonatomic, assign) BOOL shouldPauseUpdates;

/**
 When set, this view will be automatically kept updated with any
 changes to the database affecting activeViewMappings. UITableView
 and UICollectionView works by default, but any FRZDatabaseMappable-object
 can be used.
 */
@property (nonatomic, weak) id<FRZDatabaseMappable> view;

- (NSUInteger)numberOfSections;
- (NSUInteger)numberOfItemsInSection:(NSUInteger)section;
- (NSString *)groupForSection:(NSUInteger)section;
- (YapDatabaseViewMappings *)mappingsForSection:(NSUInteger)section withInternalSection:(NSUInteger *)internalSection;
- (NSRange)sectionRangeForMappings:(YapDatabaseViewMappings *)mappings;
- (id)objectAtIndexPath:(NSIndexPath *)indexPath;
- (void)getObject:(id *)object collection:(NSString **)collection key:(NSString **)key metadata:(id *)metadata atIndexPath:(NSIndexPath *)indexPath;

@end
