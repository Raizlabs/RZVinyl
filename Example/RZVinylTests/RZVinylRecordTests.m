//
//  RZVinylRecordTests.m
//  RZVinylDemo
//
//  Created by Nick Donaldson on 6/5/14.
//  Copyright (c) 2014 Raizlabs. All rights reserved.
//

@import XCTest;
#import "RZVinyl.h"
#import "Artist.h"
#import "Song.h"
#import "RZWaiter.h"

@interface RZVinylRecordTests : XCTestCase

@property (nonatomic, strong) RZCoreDataStack *stack;

@end

@implementation RZVinylRecordTests

- (void)setUp
{
    [super setUp];
    NSURL *modelURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"TestModel" withExtension:@"momd"];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    self.stack = [[RZCoreDataStack alloc] initWithModel:model
                                              storeType:NSInMemoryStoreType
                                               storeURL:nil
                             persistentStoreCoordinator:nil
                                                options:kNilOptions];
    
    [RZCoreDataStack setDefaultStack:self.stack];
    [self seedDatabase];
}

- (void)tearDown
{
    [super tearDown];
    self.stack = nil;
}

#pragma mark - Utils

- (void)seedDatabase
{
    // Manual import for this test
    NSURL *testJSONURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"record_tests" withExtension:@"json"];
    NSArray *testArtists = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:testJSONURL] options:kNilOptions error:NULL];
    [testArtists enumerateObjectsUsingBlock:^(NSDictionary *artistDict, NSUInteger idx, BOOL *stop) {
        Artist *artist = [NSEntityDescription insertNewObjectForEntityForName:@"Artist" inManagedObjectContext:self.stack.mainManagedObjectContext];
        artist.remoteID = artistDict[@"id"];
        artist.name = artistDict[@"name"];
        artist.genre = artistDict[@"genre"];
        
        NSMutableSet *songs = [NSMutableSet set];
        NSArray *songArray = artistDict[@"songs"];
        [songArray enumerateObjectsUsingBlock:^(NSDictionary *songDict, NSUInteger songIdx, BOOL *stop) {
            Song *song = [NSEntityDescription insertNewObjectForEntityForName:@"Song" inManagedObjectContext:self.stack.mainManagedObjectContext];
            song.remoteID = songDict[@"id"];
            song.title = songDict[@"title"];
            song.length = songDict[@"length"];
            [songs addObject:song];
        }];
        
        artist.songs = songs;
    }];
    
    [self.stack save:YES];
}

#pragma mark - Tests

- (void)test_SimpleCreation
{
    Artist *newArtist = nil;
    XCTAssertNoThrow(newArtist = [Artist rzv_newObject], @"Creation threw exception");
    XCTAssertNotNil(newArtist, @"Failed to create new object");
    XCTAssertTrue([newArtist isKindOfClass:[Artist class]], @"New object is not of correct class");
}

- (void)test_ChildContext
{
    NSManagedObjectContext *childContext = [self.stack temporaryChildManagedObjectContext];
    [childContext performBlockAndWait:^{
        Artist *newArtist = nil;
        XCTAssertNoThrow(newArtist = [Artist rzv_newObjectInContext:childContext], @"Creation with explicit context should not throw exception");
        XCTAssertNotNil(newArtist, @"Failed to create new object");
        XCTAssertTrue([newArtist isKindOfClass:[Artist class]], @"New object is not of correct class");
        XCTAssertEqualObjects(newArtist.managedObjectContext, childContext, @"Wrong Context");
        
        newArtist.remoteID = @100;
        newArtist.name = @"Sergio";
        newArtist.genre = @"Sax";
        
        NSError *err = nil;
        [childContext save:&err];
        XCTAssertNil(err, @"Saving child context failed: %@", err);
    }];
    
    Artist *matchingArtist = [Artist rzv_objectWithPrimaryKeyValue:@100 createNew:NO];
    XCTAssertNotNil(matchingArtist, @"Could not fetch from main context");
    XCTAssertEqualObjects(matchingArtist.name, @"Sergio", @"Fetched artist has wrong name");
}

- (void)test_BackgroundBlock
{
    __block BOOL finished = NO;
    
    [self.stack performBlockUsingBackgroundContext:^(NSManagedObjectContext *moc) {
        
        XCTAssertNotEqualObjects(moc, self.stack.mainManagedObjectContext, @"Current moc should not equal main moc");

        Artist *newArtist = nil;
        XCTAssertNoThrow(newArtist = [Artist rzv_newObjectInContext:moc], @"Creation threw exception");
        XCTAssertNotNil(newArtist, @"Failed to create new object");
        XCTAssertTrue([newArtist isKindOfClass:[Artist class]], @"New object is not of correct class");
        XCTAssertEqualObjects(newArtist.managedObjectContext, moc, @"Wrong Context");
        
        newArtist.remoteID = @100;
        newArtist.name = @"Sergio";
        newArtist.genre = @"Sax";
        
    } completion:^(NSError *err) {
        XCTAssertNil(err, @"An error occurred during the background save: %@", err);
        
        [[self.stack mainManagedObjectContext] reset];
        
        Artist *matchingArtist = [Artist rzv_objectWithPrimaryKeyValue:@100 createNew:NO];
        XCTAssertNil(matchingArtist, @"Matching object should not exist after reset without save");
        
        finished = YES;
    }];
    
    [RZWaiter waitWithTimeout:3 pollInterval:0.1 checkCondition:^BOOL{
        return finished;
    } onTimeout:^{
        XCTFail(@"Operation timed out");
    }];
    
    finished = NO;
    
    [self.stack performBlockUsingBackgroundContext:^(NSManagedObjectContext *moc) {
        Artist *newArtist = nil;
        XCTAssertNoThrow(newArtist = [Artist rzv_newObjectInContext:moc], @"Creation threw exception");
        XCTAssertNotNil(newArtist, @"Failed to create new object");
        XCTAssertTrue([newArtist isKindOfClass:[Artist class]], @"New object is not of correct class");
        XCTAssertEqualObjects(newArtist.managedObjectContext, moc, @"Wrong Context");
        
        newArtist.remoteID = @100;
        newArtist.name = @"Sergio";
        newArtist.genre = @"Sax";
        
    } completion:^(NSError *err) {
        XCTAssertNil(err, @"An error occurred during the background save: %@", err);
        
        [self.stack save:YES];
        [[self.stack mainManagedObjectContext] reset];
        
        Artist *matchingArtist = [Artist rzv_objectWithPrimaryKeyValue:@100 createNew:NO];
        XCTAssertNotNil(matchingArtist, @"Matching object should exist after reset after save");
        XCTAssertEqualObjects(matchingArtist.name, @"Sergio", @"Fetched artist has wrong name");
        
        finished = YES;
    }];
    
    [RZWaiter waitWithTimeout:3 pollInterval:0.1 checkCondition:^BOOL{
        return finished;
    } onTimeout:^{
        XCTFail(@"Operation timed out");
    }];
}

- (void)test_FetchOrCreateByPrimary
{
    Artist *dusky = [Artist rzv_objectWithPrimaryKeyValue:@1000 createNew:NO];
    XCTAssertNotNil(dusky, @"Should be a matching object");
    XCTAssertEqualObjects(dusky.name, @"Dusky", @"Wrong object");
    
    Artist *pezzner = [Artist rzv_objectWithPrimaryKeyValue:@9999 createNew:YES];
    XCTAssertNotNil(pezzner, @"Should be new object");
    XCTAssertTrue([self.stack.mainManagedObjectContext hasChanges], @"Moc should have changes after new object add");
    XCTAssertEqualObjects(pezzner.remoteID, @9999, @"New object should have correct primary key value");
    XCTAssertNil(pezzner.name, @"New object should have nil attributes");
    
    [self.stack.mainManagedObjectContext reset];
    
    __block BOOL finished = NO;
    
    [self.stack performBlockUsingBackgroundContext:^(NSManagedObjectContext *moc) {
        
        Artist *dusky = [Artist rzv_objectWithPrimaryKeyValue:@1000 createNew:NO inContext:moc];
        XCTAssertNotNil(dusky, @"Should be a matching object");
        XCTAssertEqualObjects(dusky.name, @"Dusky", @"Wrong object");
        XCTAssertEqualObjects(moc, dusky.managedObjectContext, @"Wrong context");
        
        Artist *pezzner = [Artist rzv_objectWithPrimaryKeyValue:@9999 createNew:YES inContext:moc];
        XCTAssertNotNil(pezzner, @"Should be new object");
        XCTAssertTrue([moc hasChanges], @"Moc should have changes after new object add");
        XCTAssertEqualObjects(pezzner.remoteID, @9999, @"New object should have correct primary key value");
        XCTAssertNil(pezzner.name, @"New object should have nil attributes");
        XCTAssertEqualObjects(moc, pezzner.managedObjectContext, @"Wrong context");

        
    } completion:^(NSError *err) {
        XCTAssertNil(err, @"An error occurred during the background save: %@", err);
        finished = YES;
    }];
    
    [RZWaiter waitWithTimeout:3 pollInterval:0.1 checkCondition:^BOOL{
        return finished;
    } onTimeout:^{
        XCTFail(@"Operation timed out");
    }];
}

- (void)test_FetchOrCreateByAttributes
{
    Artist *dusky = [Artist rzv_objectWithAttributes:@{ @"name" : @"Dusky" } createNew:NO];
    XCTAssertNotNil(dusky, @"Should be a matching object");
    XCTAssertEqualObjects(dusky.name, @"Dusky", @"Wrong object");
    XCTAssertFalse([dusky.managedObjectContext hasChanges], @"Moc should not have changes");

    Artist *pezzner = [Artist rzv_objectWithAttributes:@{ @"name" : @"Pezzner" } createNew:YES];
    XCTAssertNotNil(pezzner, @"Should be a new object");
    XCTAssertEqualObjects(pezzner.name, @"Pezzner", @"Failed to prepopulate new object");
    XCTAssertTrue([pezzner.managedObjectContext hasChanges], @"Moc should have changes from new object");
}

- (void)test_FetchAll
{
    // Get all artists
    NSArray *artists = [Artist rzv_all];
    XCTAssertNotNil(artists, @"Should not return nil");
    XCTAssertEqual(artists.count, 3, @"Should be three artists");
    
    // Get all songs
    NSArray *songs = [Song rzv_all];
    XCTAssertNotNil(songs, @"Should not return nil");
    XCTAssertEqual(songs.count, 3, @"Should be three songs");
    
    // Get all artists sorted by name
    artists = [Artist rzv_allSorted:@[RZVKeySort(@"name", YES)]];
    XCTAssertNotNil(artists, @"Should not return nil");
    
    NSArray *expectedNames = @[@"BCee", @"Dusky", @"Tool"];
    XCTAssertEqualObjects([artists valueForKey:@"name"], expectedNames, @"Not in expected order");
    
    // Background fetch all
    __block BOOL finished = NO;
    [self.stack performBlockUsingBackgroundContext:^(NSManagedObjectContext *moc) {
        
        NSArray *artists = [Artist rzv_allInContext:moc];
        XCTAssertNotNil(artists, @"Should not return nil");
        XCTAssertEqual(artists.count, 3, @"Should be three artists");
        XCTAssertEqualObjects([[artists lastObject] managedObjectContext], moc, @"Wrong context");
        
    } completion:^(NSError *err) {
        XCTAssertNil(err, @"An error occurred during the background save: %@", err);
        finished = YES;
    }];
    
    [RZWaiter waitWithTimeout:3 pollInterval:0.1 checkCondition:^BOOL{
        return finished;
    } onTimeout:^{
        XCTFail(@"Operation timed out");
    }];
}

- (void)test_QueryString
{
    // Get all artists who have songs
    NSArray *artists = [Artist rzv_where:@"songs.@count > 0"];
    XCTAssertEqual(artists.count, 2, @"Should be two artists with songs");
    
    // Get all artists who have songs sorted by name
    NSArray *expectedNames = @[@"Dusky", @"Tool"];

    artists = [Artist rzv_where:@"songs.@count > 0" sort:@[RZVKeySort(@"name", YES)]];
    XCTAssertEqual(artists.count, 2, @"Should be two artists with songs");
    XCTAssertEqualObjects(expectedNames, [artists valueForKey:@"name"], @"Not in correct order");
    
    // Try on child context
    NSManagedObjectContext *scratchContext = [self.stack temporaryChildManagedObjectContext];
    artists = [Artist rzv_where:@"songs.@count > 0" inContext:scratchContext];
    XCTAssertEqual(artists.count, 2, @"Should be two artists with songs");
    XCTAssertEqual([[artists lastObject] managedObjectContext], scratchContext, @"Wrong Context");
    
    artists = [Artist rzv_where:@"songs.@count > 0" sort:@[RZVKeySort(@"name", YES)] inContext:scratchContext];
    XCTAssertEqual(artists.count, 2, @"Should be two artists with songs");
    XCTAssertEqualObjects(expectedNames, [artists valueForKey:@"name"], @"Not in correct order");
    XCTAssertEqual([[artists lastObject] managedObjectContext], scratchContext, @"Wrong Context");
}

- (void)test_QueryPredicate
{
    // Get all artists who have songs
    NSArray *artists = [Artist rzv_where:[NSPredicate predicateWithFormat:@"songs.@count > 0"]];
    XCTAssertEqual(artists.count, 2, @"Should be two artists with songs");
    
    // Get all artists who have songs sorted by name
    NSArray *expectedNames = @[@"Dusky", @"Tool"];
    
    artists = [Artist rzv_where:[NSPredicate predicateWithFormat:@"songs.@count > 0"] sort:@[RZVKeySort(@"name", YES)]];
    XCTAssertEqual(artists.count, 2, @"Should be two artists with songs");
    XCTAssertEqualObjects(expectedNames, [artists valueForKey:@"name"], @"Not in correct order");
    
    // Try on child context
    NSManagedObjectContext *scratchContext = [self.stack temporaryChildManagedObjectContext];
    artists = [Artist rzv_where:[NSPredicate predicateWithFormat:@"songs.@count > 0"] inContext:scratchContext];
    XCTAssertEqual(artists.count, 2, @"Should be two artists with songs");
    XCTAssertEqual([[artists lastObject] managedObjectContext], scratchContext, @"Wrong Context");
    
    artists = [Artist rzv_where:[NSPredicate predicateWithFormat:@"songs.@count > 0"] sort:@[RZVKeySort(@"name", YES)] inContext:scratchContext];
    XCTAssertEqual(artists.count, 2, @"Should be two artists with songs");
    XCTAssertEqualObjects(expectedNames, [artists valueForKey:@"name"], @"Not in correct order");
    XCTAssertEqual([[artists lastObject] managedObjectContext], scratchContext, @"Wrong Context");
}

- (void)test_Count
{
    NSUInteger artistCount = [Artist rzv_count];
    XCTAssertEqual(artistCount, 3, @"Should be three artists");
    
    NSUInteger artistsWithSongsCount = [Artist rzv_countWhere:@"songs.@count != 0"];
    XCTAssertEqual(artistsWithSongsCount, 2, @"Should be two artists with songs");
}

- (void)test_Delete
{
    Artist *dusky = [Artist rzv_objectWithPrimaryKeyValue:@1000 createNew:NO];
    XCTAssertNotNil(dusky, @"Should be a matching object");
    
    [dusky rzv_delete];
    XCTAssertTrue(dusky.isDeleted, @"Should be deleted");
    dusky = [Artist rzv_objectWithPrimaryKeyValue:@1000 createNew:NO];
    XCTAssertNil(dusky, @"Fetching again should not return deleted object");
    
    [self.stack.mainManagedObjectContext reset];
    
    dusky = [Artist rzv_objectWithPrimaryKeyValue:@1000 createNew:NO];
    XCTAssertNotNil(dusky, @"Fetching after reset without save should return object.");

    [dusky rzv_delete];
    XCTAssertTrue(dusky.isDeleted, @"Should be deleted");
    dusky = [Artist rzv_objectWithPrimaryKeyValue:@1000 createNew:NO];
    XCTAssertNil(dusky, @"Fetching again should not return deleted object");
    
    [self.stack save:YES];
    [self.stack.mainManagedObjectContext reset];
    
    dusky = [Artist rzv_objectWithPrimaryKeyValue:@1000 createNew:NO];
    XCTAssertNil(dusky, @"Fetching after reset with save should not return object.");
}

- (void)test_BackgroundDelete
{
    __block BOOL finished = NO;
    
    [self.stack performBlockUsingBackgroundContext:^(NSManagedObjectContext *moc) {
        
        Artist *dusky = [Artist rzv_objectWithPrimaryKeyValue:@1000 createNew:NO inContext:moc];
        XCTAssertNotNil(dusky, @"Should be a matching object");
        
        [dusky rzv_delete];
        XCTAssertTrue(dusky.isDeleted, @"Should be deleted");
        dusky = [Artist rzv_objectWithPrimaryKeyValue:@1000 createNew:NO inContext:moc];
        XCTAssertNil(dusky, @"Fetching again should not return deleted object");
        
        [[self.stack mainManagedObjectContext] performBlockAndWait:^{
            Artist *mainDusky = [Artist rzv_objectWithPrimaryKeyValue:@1000 createNew:NO];
            XCTAssertNotNil(mainDusky, @"Should be a matching object on the main context prior to save");
        }];
        
    } completion:^(NSError *err) {
        XCTAssertNil(err, @"An error occurred during the background save: %@", err);
        
        Artist *mainDusky = [Artist rzv_objectWithPrimaryKeyValue:@1000 createNew:NO];
        XCTAssertNil(mainDusky, @"Should not be a matching object on the main context after save");
        
        finished = YES;
    }];
    
    [RZWaiter waitWithTimeout:3 pollInterval:0.1 checkCondition:^BOOL{
        return finished;
    } onTimeout:^{
        XCTFail(@"Operation timed out");
    }];
}

- (void)test_ChildDelete
{
    NSManagedObjectContext *scratchContext = [self.stack temporaryChildManagedObjectContext];
    [scratchContext performBlockAndWait:^{
        
        Artist *dusky = [Artist rzv_objectWithPrimaryKeyValue:@1000 createNew:NO inContext:scratchContext];
        XCTAssertNotNil(dusky, @"Should be a matching object");
        XCTAssertEqualObjects(dusky.managedObjectContext, scratchContext, @"Object is in wrong context");
        
        [dusky rzv_delete];
        XCTAssertTrue(dusky.isDeleted, @"Should be deleted");
        dusky = [Artist rzv_objectWithPrimaryKeyValue:@1000 createNew:NO inContext:scratchContext];
        XCTAssertNil(dusky, @"Fetching again should not return deleted object");
        
        [[self.stack mainManagedObjectContext] performBlockAndWait:^{
            Artist *mainDusky = [Artist rzv_objectWithPrimaryKeyValue:@1000 createNew:NO];
            XCTAssertNotNil(mainDusky, @"Should be a matching object on the main context prior to child save");
        }];
    }];
    
    NSError *saveErr = nil;
    [scratchContext save:&saveErr];
    XCTAssertNil(saveErr, @"Save caused an error: %@", saveErr);
    
    Artist *mainDusky = [Artist rzv_objectWithPrimaryKeyValue:@1000 createNew:NO];
    XCTAssertNil(mainDusky, @"Should not be a matching object on the main context after child save");
}

- (void)test_DeleteAll
{
    NSArray *artists = [Artist rzv_all];
    XCTAssertEqual(artists.count, 3, @"Should be three artists to start");
    
    [Artist rzv_deleteAll];
    artists = [Artist rzv_all];
    XCTAssertEqual(artists.count, 0, @"Should be no artists after delete all");
    
    [self.stack.mainManagedObjectContext reset];
    
    artists = [Artist rzv_all];
    XCTAssertEqual(artists.count, 3, @"Should be three artists to start");
    
    [Artist rzv_deleteAllWhere:@"songs.@count == 0"];
    artists = [Artist rzv_all];
    XCTAssertEqual(artists.count, 2, @"Should be 2 artists after delete all with predicate");
    
    [self.stack.mainManagedObjectContext reset];

    // Repeat in background
    __block BOOL finished = NO;
    [self.stack performBlockUsingBackgroundContext:^(NSManagedObjectContext *moc) {
        
        NSArray *artists = [Artist rzv_allInContext:moc];
        XCTAssertEqual(artists.count, 3, @"Should be three artists to start");
        
        [Artist rzv_deleteAllInContext:moc];
        artists = [Artist rzv_allInContext:moc];
        XCTAssertEqual(artists.count, 0, @"Should be no artists after delete all");
        
        [moc reset];
        
        artists = [Artist rzv_allInContext:moc];
        XCTAssertEqual(artists.count, 3, @"Should be three artists to start");
        
        [Artist rzv_deleteAllWhere:@"songs.@count == 0"];
        artists = [Artist rzv_allInContext:moc];
        XCTAssertEqual(artists.count, 2, @"Should be 2 artists after delete all with predicate");
        
    } completion:^(NSError *err) {
        XCTAssertNil(err, @"An error occurred during the background save: %@", err);
        finished = YES;
    }];
    
    [RZWaiter waitWithTimeout:3 pollInterval:0.1 checkCondition:^BOOL{
        return finished;
    } onTimeout:^{
        XCTFail(@"Operation timed out");
    }];
}

@end