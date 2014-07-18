//
//  RZCoreDataStack.m
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


#import "RZCoreDataStack.h"
#import "NSManagedObject+RZVinylRecord.h"
#import "NSManagedObjectContext+RZVinylSave.h"
#import "RZVinylDefines.h"
#import <libkern/OSAtomic.h>

static RZCoreDataStack *s_defaultStack = nil;
static NSString* const kRZCoreDataStackParentStackKey = @"RZCoreDataStackParentStack";

@interface RZCoreDataStack ()

@property (nonatomic, strong, readwrite) NSManagedObjectModel            *managedObjectModel;
@property (nonatomic, strong, readwrite) NSManagedObjectContext          *mainManagedObjectContext;
@property (nonatomic, strong, readwrite) NSPersistentStoreCoordinator    *persistentStoreCoordinator;

@property (nonatomic, strong) NSManagedObjectContext *topLevelBackgroundContext;

@property (nonatomic, copy) NSString *modelName;
@property (nonatomic, copy) NSString *modelConfiguration;
@property (nonatomic, copy) NSString *storeType;
@property (nonatomic, copy) NSURL    *storeURL;
@property (nonatomic, strong) dispatch_queue_t backgroundContextQueue;
@property (nonatomic, assign) RZCoreDataStackOptions options;

@property (nonatomic, readonly, strong) NSDictionary *entityClassNamesToStalenessPredicates;

@end

@implementation RZCoreDataStack

@synthesize entityClassNamesToStalenessPredicates = _entityClassNamesToStalenessPredicates;

+ (RZCoreDataStack *)defaultStack
{
    if ( s_defaultStack == nil ) {
        RZVLogInfo(@"The default stack has been accessed without being configured. Creating a new default stack with the default options.");
        s_defaultStack = [[RZCoreDataStack alloc] initWithModelName:nil
                                                      configuration:nil
                                                          storeType:nil
                                                           storeURL:nil
                                                            options:kNilOptions];
    }
    return s_defaultStack;
}

+ (void)setDefaultStack:(RZCoreDataStack *)stack
{
    if ( s_defaultStack == nil ) {
        s_defaultStack = stack;
    }
    else {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:@"The default stack has already been set and cannot be changed."
                                     userInfo:nil];
    }
}

- (id)init
{
    return [self initWithModelName:nil
                     configuration:nil
                         storeType:nil
                          storeURL:nil
                           options:kNilOptions];
}

- (instancetype)initWithModelName:(NSString *)modelName
                    configuration:(NSString *)modelConfiguration
                        storeType:(NSString *)storeType
                         storeURL:(NSURL *)storeURL
                          options:(RZCoreDataStackOptions)options
{
    return [self initWithModelName:modelName
                     configuration:modelConfiguration
                         storeType:storeType
                          storeURL:storeURL
        persistentStoreCoordinator:nil
                           options:options];
}

- (instancetype)initWithModelName:(NSString *)modelName
                    configuration:(NSString *)modelConfiguration
                        storeType:(NSString *)storeType
                         storeURL:(NSURL *)storeURL
       persistentStoreCoordinator:(NSPersistentStoreCoordinator *)psc
                          options:(RZCoreDataStackOptions)options
{
    self = [super init];
    if ( self ) {
        _modelName                  = modelName;
        _modelConfiguration         = modelConfiguration;
        _storeType                  = storeType ?: NSSQLiteStoreType;
        _storeURL                   = storeURL;
        _persistentStoreCoordinator = psc;
        _options                    = options;
        
        _backgroundContextQueue     = dispatch_queue_create("com.rzvinyl.backgroundContextQueue", DISPATCH_QUEUE_SERIAL);
        
        if ( ![self buildStack] ) {
            return nil;
        }
        
        [self registerForNotifications];
    }
    return self;
}

- (instancetype)initWithModel:(NSManagedObjectModel *)model
                    storeType:(NSString *)storeType
                     storeURL:(NSURL *)storeURL
   persistentStoreCoordinator:(NSPersistentStoreCoordinator *)psc
                      options:(RZCoreDataStackOptions)options
{
    if ( !RZVParameterAssert(model) ) {
        return nil;
    }
    
    self = [super init];
    if ( self ) {
        _managedObjectModel         = model;
        _storeType                  = storeType ?: NSInMemoryStoreType;
        _storeURL                   = storeURL;
        _persistentStoreCoordinator = psc;
        _options                    = options;
        
        _backgroundContextQueue     = dispatch_queue_create("com.rzvinyl.backgroundContextQueue", DISPATCH_QUEUE_SERIAL);
        
        if ( ![self buildStack] ) {
            return nil;
        }
        
        [self registerForNotifications];
    }
    
    return self;
}

- (void)dealloc
{
    [self unregisterForNotifications];
}

#pragma mark - Public

- (void)performBlockUsingBackgroundContext:(RZCoreDataStackTransactionBlock)block completion:(void (^)(NSError *err))completion
{
    if ( !RZVParameterAssert(block) ) {
        return;
    }
    
    dispatch_async(self.backgroundContextQueue, ^{
        NSManagedObjectContext *context = [self backgroundManagedObjectContext];
        [context performBlockAndWait:^{
            block(context);
            NSError *err = nil;
            [context rzv_saveToStoreAndWait:&err];
            if ( completion ) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(err);
                });
            }
        }];
    });
}

- (NSManagedObjectContext *)backgroundManagedObjectContext
{
    NSManagedObjectContext *bgContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [[bgContext userInfo] setObject:self forKey:kRZCoreDataStackParentStackKey];
    bgContext.parentContext = self.topLevelBackgroundContext;
    return bgContext;
}

- (NSManagedObjectContext *)temporaryManagedObjectContext
{
    NSManagedObjectContext *tempContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    [[tempContext userInfo] setObject:self forKey:kRZCoreDataStackParentStackKey];
    tempContext.parentContext = self.mainManagedObjectContext;
    return tempContext;
}

- (void)purgeStaleObjectsWithCompletion:(void (^)(NSError *))completion
{
    [self performBlockUsingBackgroundContext:^(NSManagedObjectContext *context) {
        
        [self.entityClassNamesToStalenessPredicates enumerateKeysAndObjectsUsingBlock:^(NSString *className, NSPredicate *predicate, BOOL *stop) {
            
            Class moClass = NSClassFromString(className);
            if ( moClass != Nil ) {
                [moClass rzv_deleteAllWhere:predicate inContext:context];
            }
            
        }];
        
    } completion:^(NSError *err) {
        
        if (completion) {
            completion(err);
        }
        
    }];
}

#pragma mark - Lazy Default Properties

- (NSString *)modelName
{
    if ( _modelName == nil ) {
        NSMutableString *productName = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"] mutableCopy];
        [productName replaceOccurrencesOfString:@" " withString:@"_" options:0 range:NSMakeRange(0, productName.length)];
        [productName replaceOccurrencesOfString:@"-" withString:@"_" options:0 range:NSMakeRange(0, productName.length)];
        _modelName = [NSString stringWithString:productName];
    }
    return _modelName;
}

- (NSURL *)storeURL
{
    if (_storeURL == nil) {
        if ( [self.storeType isEqualToString:NSSQLiteStoreType] ) {
            NSString *storeFileName = [self.modelName stringByAppendingPathExtension:@"sqlite"];
            NSURL    *libraryDir = [[[NSFileManager defaultManager] URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask] lastObject];
            _storeURL = [libraryDir URLByAppendingPathComponent:storeFileName];
        }
    }
    return _storeURL;
}

- (NSDictionary *)entityClassNamesToStalenessPredicates
{
    __block NSDictionary *result = nil;
    
    //!!!: Must be a thread-safe lazy load
    rzv_performBlockAtomically(^{
        if ( _entityClassNamesToStalenessPredicates == nil ) {
            // Enumerate the model and discover stale predicates for each entity class
            NSMutableDictionary *classNamesToStalePredicates = [NSMutableDictionary dictionary];
            [[self.managedObjectModel entities] enumerateObjectsUsingBlock:^(NSEntityDescription *entity, NSUInteger idx, BOOL *stop) {
                Class moClass = NSClassFromString(entity.managedObjectClassName);
                if ( moClass != Nil ) {
                    NSPredicate *predicate = [moClass rzv_stalenessPredicate];
                    if ( predicate != nil ) {
                        [classNamesToStalePredicates setObject:predicate forKey:entity.managedObjectClassName];
                    }
                }
            }];
            _entityClassNamesToStalenessPredicates = [NSDictionary dictionaryWithDictionary:classNamesToStalePredicates];
        }
        result = _entityClassNamesToStalenessPredicates;
    });
    
    return result;
}

#pragma mark - Private

- (BOOL)hasOptionsSet:(RZCoreDataStackOptions)options
{
    return ( ( self.options & options ) == options );
}

- (BOOL)buildStack
{
    if ( !RZVAssert(self.modelName != nil, @"Must have a model name") ) {
        return NO;
    }
    
    //
    // Create model
    //
    if ( self.managedObjectModel == nil ) {
        self.managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:[[NSBundle mainBundle] URLForResource:self.modelName withExtension:@"momd"]];
        if ( self.managedObjectModel == nil ) {
            RZVLogError(@"Could not create managed object model for name %@", self.modelName);
            return NO;
        }
    }
    
    //
    // Create PSC
    //
    NSError *error = nil;
    if ( self.persistentStoreCoordinator == nil ) {
        self.persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.managedObjectModel];
    }
    
    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    
    if ( self.storeType == NSSQLiteStoreType ) {
        if ( !RZVAssert(self.storeURL != nil, @"Must have a store URL for SQLite stores") ) {
            return NO;
        }
        NSString *journalMode = [self hasOptionsSet:RZCoreDataStackOptionsDisableWriteAheadLog] ? @"DELETE" : @"WAL";
        options[NSSQLitePragmasOption] = @{@"journal_mode" : journalMode};
    }

    if ( ![self hasOptionsSet:RZCoreDataStackOptionDisableAutoLightweightMigration] && self.storeURL ){
        options[NSMigratePersistentStoresAutomaticallyOption] = @(YES);
        options[NSInferMappingModelAutomaticallyOption] = @(YES);
    }
    
    if( ![self.persistentStoreCoordinator addPersistentStoreWithType:self.storeType
                                                       configuration:self.modelConfiguration
                                                                 URL:self.storeURL
                                                             options:options error:&error] ) {
        
        RZVLogError(@"Error creating/reading persistent store: %@", error);
        
        if ( [self hasOptionsSet:RZCoreDataStackOptionDeleteDatabaseIfUnreadable] && self.storeURL ) {
            
            // Reset the error before we reuse it
            error = nil;
            
            if ( [[NSFileManager defaultManager] removeItemAtURL:self.storeURL error:&error] ) {
                
                [self.persistentStoreCoordinator addPersistentStoreWithType:self.storeType
                                                              configuration:self.modelConfiguration
                                                                        URL:self.storeURL
                                                                    options:options
                                                                      error:&error];
            }
        }
        
        if ( error != nil ) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:[NSString stringWithFormat:@"Unresolved error creating PSC for data stack: %@", error]
                                         userInfo:nil];
            return NO;
        }
    }
    
    //
    // Create Contexts
    //
    self.topLevelBackgroundContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    self.topLevelBackgroundContext.persistentStoreCoordinator = self.persistentStoreCoordinator;

    self.mainManagedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    self.mainManagedObjectContext.parentContext = self.topLevelBackgroundContext;
    
    return YES;
}

#pragma mark - Notifications

- (void)registerForNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleAppDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleContextDidSave:) name:NSManagedObjectContextDidSaveNotification object:nil];
}

- (void)unregisterForNotifications
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextDidSaveNotification object:nil];

}

- (void)handleAppDidEnterBackground:(NSNotification *)notification
{
    if ( [self hasOptionsSet:RZCoreDataStackOptionsEnableAutoStalePurge] ) {
        
        __block UIBackgroundTaskIdentifier backgroundPurgeTaskID = UIBackgroundTaskInvalid;
        
        [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
            [[UIApplication sharedApplication] endBackgroundTask:backgroundPurgeTaskID];
            backgroundPurgeTaskID = UIBackgroundTaskInvalid;
        }];
        
        [self purgeStaleObjectsWithCompletion:^(NSError *err) {
            [[UIApplication sharedApplication] endBackgroundTask:backgroundPurgeTaskID];
            backgroundPurgeTaskID = UIBackgroundTaskInvalid;
        }];
    }
}

- (void)handleContextDidSave:(NSNotification *)notification
{
    NSManagedObjectContext *context = [notification object];
    if ( [[context userInfo] objectForKey:kRZCoreDataStackParentStackKey] == self ) {
        [self.mainManagedObjectContext performBlock:^{
            [self.mainManagedObjectContext mergeChangesFromContextDidSaveNotification:notification];
        }];
    }
}

@end

//=====================
//  FOR TESTING ONLY
//=====================

void __rzv_resetDefaultStack()
{
    s_defaultStack = nil;
}

