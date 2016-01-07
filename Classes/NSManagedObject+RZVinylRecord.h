//
//  NSManagedObject+RZVinylRecord.h
//  RZVinyl
//
//  Created by Nick Donaldson on 6/4/14.
//
//  Copyright 2014 Raizlabs and other contributors
//  http://raizlabs.com/
//
//  Permission is hereby granted, free of charge, to any person obtaining
//  a copy of this software and associated documentation files (the
//                                                                "Software"), to deal in the Software without restriction, including
//  without limitation the rights to use, copy, modify, merge, publish,
//  distribute, sublicense, and/or sell copies of the Software, and to
//  permit persons to whom the Software is furnished to do so, subject to
//  the following conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
//  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
//  LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
//  OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
//  WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

@import CoreData;

@class RZCoreDataStack;

/**
 *  ActiveRecord-style extensions for NSManagedObject.
 *
 *  @note Because of the semantics of saving NSManagedObjectContext in a parent/child configuration, no "save" method 
 *        is provided for managed object instances themselves. You must call one of the methods in @p NSManagedObjectContext+RZVinylSave
 *        to persist objects to the store.
 *
 *  @warning This category requires the use of @p RZCoreDataStack to access the default managed object context,
 *           as well as valid overrides for the methods in @p NSManagedObject+NSVinylSubclass.h on managed object subclasses.
 *
 */
@interface NSManagedObject (RZVinylRecord)


/** @name Creating/Finding objects */


/**
 *  Create and return a new instance in the main context.
 *
 *  @return A new object instance.
 */
+ (instancetype)rzv_newObject;

/**
 *  Create and return a new instance in the provided context.
 *
 *  @param context The context in which to create the instance.
 *
 *  @return A new object instance.
 */
+ (instancetype)rzv_newObjectInContext:(NSManagedObjectContext *)context;

/**
 *  Return an instance of this managed object class from the main context with the provided value for its primary key.
 *
 *  @param primaryValue The value of the primary key (e.g. the remoteID)
 *  @param createNew    Pass YES to create a new object if one is not found.
 *
 *  @warning Calling this on a class that does not return a value for @p rzv_primaryKey will throw an exception.
 *
 *  @return An existing or new instance of this managed object class with the provided primary key
 *          value, or nil if @p createNew is NO and an existing object was not found.
 */
+ (instancetype)rzv_objectWithPrimaryKeyValue:(id)primaryValue createNew:(BOOL)createNew;

/**
 *  Return an instance of this managed object class from the provided context with the provided value for its primary key.
 *
 *
 *  @param primaryValue The value of the primary key (e.g. the remoteID)
 *  @param createNew    Pass YES to create a new object if one is not found.
 *  @param context      The context
 *
 *  @warning Calling this on a class that does not return a value for @p rzv_primaryKey will throw an exception.
 *
 *  @return An existing or new instance of this managed object class with the provided primary key
 *          value, or nil if @p createNew is NO and an existing object was not found.
 */
+ (instancetype)rzv_objectWithPrimaryKeyValue:(id)primaryValue createNew:(BOOL)createNew inContext:(NSManagedObjectContext *)context;

/**
 *  Find an object with the provided attribute/value pairs in the main context and optionally create a new one if no match is found.
 *
 *  @param attributes    Dictionary of key/value pairs for which to find a matching object. Must not be nil.
 *  @param createNew If YES and no match is found, a new object is created and initialized with the provided dictionary.
 *
 *  @return A matching or new object with the provided attributes, or nil if @p createNew is NO and no match is found.
 */
+ (instancetype)rzv_objectWithAttributes:(NSDictionary *)attributes createNew:(BOOL)createNew;

/**
 *  Find an object with the provided attribute/value pairs in the provided context and optionally create a new one if no match is found.
 *
 *  @param attributes    Dictionary of key/value pairs for which to find a matching object. Must not be nil.
 *  @param createNew If YES and no match is found, a new object is created and initialized with the provided dictionary.
 *  @param context   The context in which to find/create the object. Must not be nil.
 *
 *  @return A matching or new object with the provided attributes, or nil if @p createNew is NO and no match is found.
 */
+ (instancetype)rzv_objectWithAttributes:(NSDictionary *)attributes createNew:(BOOL)createNew inContext:(NSManagedObjectContext *)context;


/** @name Querying/Fetching Objects */


/**
 *  Return an array of all objects of the receiver's type in the main context.
 *
 *  @return All objects of this class's type.
 */
+ (NSArray *)rzv_all;

/**
 *  Return an array of all objects of the receiver's type in the provided context.
 *
 *  @param context Context in which to fetch
 *
 *  @return All objects of this class's type.
 */
+ (NSArray *)rzv_allInContext:(NSManagedObjectContext *)context;

/**
 *  Return an array of all objects of the receiver's type in the main context, optionally sorted.
 *
 *  @param sortDescriptors An array of sort descriptors to sort the results.
 *
 *  @return All objects of this class's type.
 */
+ (NSArray *)rzv_allSorted:(NSArray *)sortDescriptors;

/**
 *  Return an array of all objects of the receiver's type in the provided context, optionally sorted.
 *
 *  @param sortDescriptors An array of sort descriptors to sort the results.
 *  @param context         The context from which to fetch objects. Must not be nil.
 *
 *  @return All objects of this class's type.
 */
+ (NSArray *)rzv_allSorted:(NSArray *)sortDescriptors inContext:(NSManagedObjectContext *)context;

/**
 *  Return the results of a fetch on the main context using a predicate or format string.
 *
 *  @param predicate    An @p NSPredicate to filter the query. Passing nil will return all objects.
 *
 *  @return The results of the fetch.
 */
+ (NSArray *)rzv_where:(NSPredicate *)predicate;

/**
 *  Return the results of a fetch on the provided context using a predicate or format string.
 *
 *  @param predicate        An @p NSPredicate to filter the query. Passing nil will return all objects.
 *  @param context          The managed object context on which to perform the fetch. Must not be nil.
 *
 *  @return The results of the fetch.
 */
+ (NSArray *)rzv_where:(NSPredicate *)predicate inContext:(NSManagedObjectContext *)context;

/**
 *  Return the results of a fetch on the main context using a predicate or format string
 *  with optional sorting.
 *
 *  @param predicate        An @p NSPredicate to filter the query. Passing nil will return all objects.
 *  @param sortDescriptors  An optional array of sort descriptors.
 *
 *  @return The results of the fetch.
 */
+ (NSArray *)rzv_where:(NSPredicate *)predicate sort:(NSArray *)sortDescriptors;

/**
 *  Return the results of a fetch on the provided context using a predicate or format string
 *  with optional sorting.
 *
 *  @param predicate        An @p NSPredicate to filter the query. Passing nil will return all objects.
 *  @param sortDescriptors  An optional array of sort descriptors.
 *  @param context          The managed object context on which to perform the fetch. Must not be nil.
 *
 *  @return The results of the fetch.
 */
+ (NSArray *)rzv_where:(NSPredicate *)predicate
                  sort:(NSArray *)sortDescriptors
             inContext:(NSManagedObjectContext *)context;


/** @name Counting Objects */


/**
 *  Return the count of objects of the receiver's type in the main context.
 *
 *  @return The number of objects of this class's type.
 */
+ (NSUInteger)rzv_count;

/**
 *  Return the count of objects of the receiver's type in the provided context.
 *
 *  @param context The context in which to look for the objects. Must not be nil.
 *
 *  @return The number of objects of this class's type.
 */
+ (NSUInteger)rzv_countInContext:(NSManagedObjectContext *)context;

/**
 *  Return the count of objects of the receiver's type matching the query in the main context.
 *
 *  @param predicate An @p NSPredicate to filter the count. Passing nil will return the count of all objects.
 *
 *  @return The number of objects matching the query.
 */
+ (NSUInteger)rzv_countWhere:(NSPredicate *)predicate;

/**
 *  Return the count of objects of the receiver's type matching the query in the provided context.
 *
 *  @param predicate    An @p NSPredicate to filter the count. Passing nil will return the count of all objects.
 *  @param context      The context in which to look for the objects. Must not be nil.
 *
 *  @return The number of objects matching the query.
 */
+ (NSUInteger)rzv_countWhere:(NSPredicate *)predicate inContext:(NSManagedObjectContext *)context;


/**  @name Deleting Objects */


/**
 *  Delete this object from its managed object context. If this object is not inserted, no action is taken.
 *
 *  @note You must save the @p RZCoreDataStack to persist the deletion to the store.
 */
- (void)rzv_delete;

/**
 *  Delete all objects of the receiver's type from the main context.
 *
 *  @note You must save the @p RZCoreDataStack to persist the deletion to the store.
 */
+ (void)rzv_deleteAll;

/**
 *  Delete all objects of the receiver's type from the provided context.
 *
 *  @param context The context from which to delete the objects.
 *
 *  @note You must save the @p RZCoreDataStack to persist the deletion to the store.
 */
+ (void)rzv_deleteAllInContext:(NSManagedObjectContext *)context;

/**
 *  Delete all objects of the receiver's type matching the query from the main context.
 *
 *  @param predicate An @p NSPredicate to filter which objects to delete. Passing nil will delete all objects.
 *
 *  @note You must save the @p RZCoreDataStack to persist the deletion to the store.
 */
+ (void)rzv_deleteAllWhere:(NSPredicate *)predicate;

/**
 *  Delete all objects of the receiver's type matching the query from the provided context.
 *
 *  @param predicate An @p NSPredicate to filter which objects to delete. Passing nil will delete all objects.
 *  @param context   The context from which to delete the objects.
 *
 *  @note You must save the @p RZCoreDataStack to persist the deletion to the store.
 */
+ (void)rzv_deleteAllWhere:(NSPredicate *)predicate inContext:(NSManagedObjectContext *)context;


/** @name Subclassing */

/**
 *  Override in subclasses to provide a different data stack for use with this
 *  model object class. Defaults to @p +[RZDataStack defaultStack]
 *
 *  @return The data stack to use for this model object class.
 */
+ (RZCoreDataStack *)rzv_coreDataStack;

/**
 *  Override in subclasses to provide the key name of the property uniquely
 *  identifying this object
 *
 *  @warning If you do not override this method to return a valid key, attempting to use @c +rzv_objectWithPrimaryKeyValue:
 *           will throw a runtime exception.
 *
 *  @return The key name of the property uniquely identifying this object.
 */
+ (NSString *)rzv_primaryKey;

/**
 *  Override in subclasses to return a predicate to be used when purging stale objects from the persistent store.
 *  Returns nil (no objects considered stale) by default.
 *
 *  @return A predicate to use with @p RZCoreDataStack's @p -purgeStaleObjects
 */
+ (NSPredicate *)rzv_stalenessPredicate;


@end
