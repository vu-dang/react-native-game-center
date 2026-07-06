//
//  RNGameCenter.m
//  StockShot
//
//  Created by vyga on 9/18/17.
//  Copyright © 2017 Facebook. All rights reserved.
//

#import "RNGameCenter.h"
#import <GameKit/GameKit.h>
#import <React/RCTUtils.h>
#import <React/RCTConvert.h>
#import <React/RCTLog.h>
#import <Foundation/Foundation.h>


NSString *_leaderboardIdentifier;
NSString *_achievementIdentifier;
NSString *_playerId;
BOOL _isGameCenterAvailable = NO;

static RNGameCenter *SharedInstance = nil;

@interface RNGameCenter () <GKGameCenterControllerDelegate>
@property (nonatomic, strong) GKGameCenterViewController *gkView;
@property (nonatomic, strong) UIViewController *reactNativeViewController;
@property (nonatomic, strong) NSNumber *_currentAdditionCounter;

// Realtime multiplayer
@property (nonatomic, strong) GKMatch *currentMatch;
@property (nonatomic, copy) RCTPromiseResolveBlock matchmakerResolve;
@property (nonatomic, copy) RCTPromiseRejectBlock matchmakerReject;
@property (nonatomic, assign) BOOL hasListeners;
@property (nonatomic, assign) BOOL inviteListenerRegistered;
@end

@interface MobSvcSavedGameData : NSObject <NSSecureCoding>
@property (readwrite, retain) NSString *data;
+(instancetype)sharedGameData;
-(void)reset;
@end


@implementation RNGameCenter

- (dispatch_queue_t)methodQueue {
    return dispatch_get_main_queue();
}

+ (BOOL)requiresMainQueueSetup {
    return YES;
}

RCT_EXPORT_MODULE()

/* -----------------------------------------------------------------------------------------------------------------------------------------
 Event emitter plumbing
 -----------------------------------------------------------------------------------------------------------------------------------------*/

- (NSArray<NSString *> *)supportedEvents {
    return @[@"gc:matchFound", @"gc:data", @"gc:playerState", @"gc:inviteAccepted", @"gc:matchError"];
}

- (void)startObserving {
    self.hasListeners = YES;
}

- (void)stopObserving {
    self.hasListeners = NO;
}

- (void)emit:(NSString *)name body:(id)body {
    if (self.hasListeners) {
        [self sendEventWithName:name body:body];
    }
}

- (UIViewController *)getRootViewController {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *window in windowScene.windows) {
                    if (window.isKeyWindow) {
                        return window.rootViewController;
                    }
                }
            }
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [UIApplication sharedApplication].keyWindow.rootViewController;
#pragma clang diagnostic pop
}


/* -----------------------------------------------------------------------------------------------------------------------------------------
 Init Game Center
 -----------------------------------------------------------------------------------------------------------------------------------------*/

RCT_EXPORT_METHOD(init:(NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (options[@"leaderboardIdentifier"]) _leaderboardIdentifier = options[@"leaderboardIdentifier"];
    else return reject(@"Error", @"Error please pass your leaderboardIdentifier into init function", nil);

    if (options[@"achievementIdentifier"]) _achievementIdentifier = options[@"achievementIdentifier"];

    UIViewController *rnView = [self getRootViewController];
    GKLocalPlayer *localPlayer = [GKLocalPlayer localPlayer];
    localPlayer.authenticateHandler = ^(UIViewController *gcViewController, NSError *error) {
        if (gcViewController != nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [rnView presentViewController:gcViewController animated:YES completion:nil];
            });
        } else {
            if ([GKLocalPlayer localPlayer].authenticated) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                [[GKLocalPlayer localPlayer] loadDefaultLeaderboardIdentifierWithCompletionHandler:^(NSString *leaderboardIdentifier, NSError *error) {
                    if (error != nil) {
                        NSLog(@"%@", [error localizedDescription]);
                        reject(@"Error", @"Error initiating Game Center make sure you are enrolled in the apple program, you set up a game center in itunes connect, and you registered it to the correct and matching app bundle id", error);
                    } else {
                        _isGameCenterAvailable = YES;
                        _leaderboardIdentifier = leaderboardIdentifier;
                        resolve(@"init success");
                    }
                }];
#pragma clang diagnostic pop
            } else {
                reject(@"Error", @"Error initiating Game Center Player", error);
            }
        }
    };
}

RCT_EXPORT_METHOD(userLogged:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(_isGameCenterAvailable != NO ? @true : @false);
}


/* -----------------------------------------------------------------------------------------------------------------------------------------
 Player
 -----------------------------------------------------------------------------------------------------------------------------------------*/

RCT_EXPORT_METHOD(getPlayer:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (_isGameCenterAvailable == NO) {
        return reject(@"Error", @"Game Center is Unavailable", nil);
    }
    @try {
        GKLocalPlayer *localPlayer = [GKLocalPlayer localPlayer];
        NSString *playerID;
        if (@available(iOS 12.4, *)) {
            playerID = localPlayer.gamePlayerID;
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            playerID = localPlayer.playerID;
#pragma clang diagnostic pop
        }
        NSDictionary *user = @{
            @"alias": localPlayer.alias ?: @"",
            @"displayName": localPlayer.displayName ?: @"",
            @"playerID": playerID ?: @""
        };
        resolve(user);
    } @catch (NSError *e) {
        reject(@"Error", @"Error getting user.", e);
    }
}

RCT_EXPORT_METHOD(getPlayerImage:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (_isGameCenterAvailable == NO) {
        return reject(@"Error", @"Game Center is Unavailable", nil);
    }
    @try {
        GKLocalPlayer *localPlayer = [GKLocalPlayer localPlayer];
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths objectAtIndex:0];
        NSString *path = [documentsDirectory stringByAppendingPathComponent:@"user.jpg"];
        BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:path];
        if (fileExists) {
            resolve(@{@"image": path});
        } else {
            [localPlayer loadPhotoForSize:GKPhotoSizeSmall withCompletionHandler:^(UIImage *photo, NSError *error) {
                if (error != nil) return reject(@"Error", @"Error fetching player image", error);
                if (photo != nil) {
                    NSData *data = UIImageJPEGRepresentation(photo, 0.8);
                    [data writeToFile:path atomically:YES];
                    resolve(@{@"image": path});
                } else {
                    resolve(@{@"image": [NSNull null]});
                }
            }];
        }
    } @catch (NSError *e) {
        reject(@"Error", @"Error fetching player image", e);
    }
}


/* -----------------------------------------------------------------------------------------------------------------------------------------
 Leaderboard
 -----------------------------------------------------------------------------------------------------------------------------------------*/

RCT_EXPORT_METHOD(openLeaderboardModal:(NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (_isGameCenterAvailable == NO) {
        return reject(@"Error", @"Game Center is Unavailable", nil);
    }
    NSString *leaderboardId = options[@"leaderboardIdentifier"] ?: _leaderboardIdentifier;
    UIViewController *rnView = [self getRootViewController];
    GKGameCenterViewController *leaderboardController;
    if (@available(iOS 14.0, *)) {
        leaderboardController = [[GKGameCenterViewController alloc] initWithLeaderboardID:leaderboardId
                                                                              playerScope:GKLeaderboardPlayerScopeGlobal
                                                                                timeScope:GKLeaderboardTimeScopeAllTime];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        leaderboardController = [[GKGameCenterViewController alloc] init];
        leaderboardController.leaderboardIdentifier = leaderboardId;
        leaderboardController.viewState = GKGameCenterViewControllerStateLeaderboards;
#pragma clang diagnostic pop
    }
    leaderboardController.gameCenterDelegate = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [rnView presentViewController:leaderboardController animated:YES completion:nil];
    });
    resolve(@"opened Leaderboard");
}

RCT_EXPORT_METHOD(submitLeaderboardScore:(int64_t)score
                  options:(NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (_isGameCenterAvailable == NO) {
        return reject(@"Error", @"Game Center is Unavailable", nil);
    }
    @try {
        NSString *leaderboardId = options[@"leaderboardIdentifier"] ?: _leaderboardIdentifier;
        if (@available(iOS 14.0, *)) {
            [GKLeaderboard submitScore:score
                               context:0
                                player:[GKLocalPlayer localPlayer]
                        leaderboardIDs:@[leaderboardId]
                     completionHandler:^(NSError *error) {
                if (error) reject(@"Error", @"Error submitting score", error);
                else resolve(@"Successfully submitted score");
            }];
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            GKScore *scoreSubmitter = [[GKScore alloc] initWithLeaderboardIdentifier:leaderboardId];
            scoreSubmitter.value = score;
            scoreSubmitter.context = 0;
            [GKScore reportScores:@[scoreSubmitter] withCompletionHandler:^(NSError *error) {
                if (error) reject(@"Error", @"Error submitting score", error);
                else resolve(@"Successfully submitted score");
            }];
#pragma clang diagnostic pop
        }
    } @catch (NSError *e) {
        reject(@"Error", @"Error submitting score.", e);
    }
}

RCT_EXPORT_METHOD(getLeaderboardPlayers:(NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (_isGameCenterAvailable == NO) {
        return reject(@"Error", @"Game Center is Unavailable", nil);
    }
    @try {
        NSString *leaderboardId = options[@"leaderboardIdentifier"] ?: _leaderboardIdentifier;
        if (@available(iOS 14.0, *)) {
            [GKLeaderboard loadLeaderboardsWithIDs:@[leaderboardId] completionHandler:^(NSArray<GKLeaderboard *> *leaderboards, NSError *error) {
                if (error) return reject(@"Error", @"Error getting leaderboards", error);
                GKLeaderboard *leaderboard = leaderboards.firstObject;
                if (!leaderboard) return reject(@"Error", @"Leaderboard not found", nil);
                [leaderboard loadEntriesForPlayerScope:GKLeaderboardPlayerScopeGlobal
                                             timeScope:GKLeaderboardTimeScopeAllTime
                                                 range:NSMakeRange(1, 100)
                                     completionHandler:^(GKLeaderboardEntry *localPlayerEntry, NSArray<GKLeaderboardEntry *> *entries, NSInteger totalPlayerCount, NSError *entriesError) {
                    if (entriesError) {
                        reject(@"Error", @"Error getting leaderboard entries", entriesError);
                    } else {
                        NSMutableArray *result = [NSMutableArray array];
                        for (GKLeaderboardEntry *entry in entries) {
                            [result addObject:@{
                                @"rank": @(entry.rank),
                                @"score": @(entry.score),
                                @"displayName": entry.player.displayName ?: @""
                            }];
                        }
                        resolve(result);
                    }
                }];
            }];
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            NSArray *playerIds = options[@"playerIds"];
            GKLeaderboard *query = [[GKLeaderboard alloc] initWithPlayers:playerIds];
            if (query != nil) {
                [query loadScoresWithCompletionHandler:^(NSArray *scores, NSError *error) {
                    if (error != nil) reject(@"Error", @"Error getting players leaderboards", error);
                    else resolve(scores);
                }];
            } else {
                reject(@"Error", @"Error creating Leaderboard query", nil);
            }
#pragma clang diagnostic pop
        }
    } @catch (NSError *e) {
        reject(@"Error", @"Error getting leaderboard players.", e);
    }
}


/*
 -----------------------------------------------------------------------------------------------------------------------------------------
 Achievements
 -----------------------------------------------------------------------------------------------------------------------------------------
*/

RCT_EXPORT_METHOD(openAchievementModal:(NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (_isGameCenterAvailable == NO) {
        return reject(@"Error", @"Game Center is Unavailable", nil);
    }
    @try {
        UIViewController *rnView = [self getRootViewController];
        GKGameCenterViewController *gcViewController;
        if (@available(iOS 14.0, *)) {
            gcViewController = [[GKGameCenterViewController alloc] initWithState:GKGameCenterViewControllerStateAchievements];
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            gcViewController = [[GKGameCenterViewController alloc] init];
            gcViewController.viewState = GKGameCenterViewControllerStateAchievements;
            NSString *achievementId = options[@"achievementIdentifier"] ?: _achievementIdentifier;
            gcViewController.leaderboardIdentifier = achievementId;
#pragma clang diagnostic pop
        }
        gcViewController.gameCenterDelegate = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [rnView presentViewController:gcViewController animated:YES completion:nil];
        });
        resolve(@"Successfully opened achievements");
    } @catch (NSError *e) {
        reject(@"Error", @"Error opening achievements.", e);
    }
}

RCT_EXPORT_METHOD(getAchievements:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (_isGameCenterAvailable == NO) {
        return reject(@"Error", @"Game Center is Unavailable", nil);
    }
    NSMutableArray *earntAchievements = [NSMutableArray array];
    [GKAchievement loadAchievementsWithCompletionHandler:^(NSArray *achievements, NSError *error) {
        if (error == nil) {
            for (GKAchievement *achievement in achievements) {
                NSMutableDictionary *entry = [NSMutableDictionary dictionary];
                entry[@"identifier"] = achievement.identifier;
                entry[@"percentComplete"] = [NSNumber numberWithDouble:achievement.percentComplete];
                entry[@"completed"] = [NSNumber numberWithBool:achievement.completed];
                entry[@"lastReportedDate"] = [NSNumber numberWithDouble:[achievement.lastReportedDate timeIntervalSince1970] * 1000];
                entry[@"showsCompletionBanner"] = [NSNumber numberWithBool:achievement.showsCompletionBanner];
                [earntAchievements addObject:entry];
            }
            resolve(earntAchievements);
        } else {
            reject(@"Error", @"Error getting achievements", error);
        }
    }];
}

RCT_EXPORT_METHOD(resetAchievements:(NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (_isGameCenterAvailable == NO) {
        return reject(@"Error", @"Game Center is Unavailable", nil);
    }
    if (!options[@"hideAlert"]) {
        UIViewController *rnView = [self getRootViewController];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset Achievements?"
                                                                       message:@"Are you sure you want to reset your achievements. This can not be undone."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *yesButton = [UIAlertAction actionWithTitle:@"Reset"
                                                            style:UIAlertActionStyleDestructive
                                                          handler:^(UIAlertAction *action) {
            [GKAchievement resetAchievementsWithCompletionHandler:^(NSError *error) {
                if (error != nil) {
                    reject(@"Error", @"Error resetting achievements", error);
                } else {
                    UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"Success!"
                                                                                          message:@"You successfully reset your achievements!"
                                                                                   preferredStyle:UIAlertControllerStyleAlert];
                    [successAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [rnView presentViewController:successAlert animated:YES completion:nil];
                    });
                    resolve(@{@"message": @"User achievements reset", @"resetAchievements": @true});
                }
            }];
        }];
        UIAlertAction *noButton = [UIAlertAction actionWithTitle:@"No!"
                                                           style:UIAlertActionStyleCancel
                                                         handler:^(UIAlertAction *action) {
            resolve(@{@"message": @"User achievements not reset", @"resetAchievements": @false});
        }];
        [alert addAction:yesButton];
        [alert addAction:noButton];
        dispatch_async(dispatch_get_main_queue(), ^{
            [rnView presentViewController:alert animated:YES completion:nil];
        });
    } else {
        resolve(@{@"message": @"User achievements reset", @"resetAchievements": @true});
    }
}

RCT_EXPORT_METHOD(submitAchievementScore:(NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (_isGameCenterAvailable == NO) {
        return reject(@"Error", @"Game Center is Unavailable", nil);
    }
    @try {
        NSString *percent = options[@"percentComplete"];
        float percentFloat = [percent floatValue];
        NSString *achievementId = options[@"achievementIdentifier"] ?: _achievementIdentifier;
        RCTLog(@"Will store: %@ (%f) on '%@'", percent, percentFloat, achievementId);
        if (!achievementId) return reject(@"Error", @"No Game Center `achievementIdentifier` passed and no default set", nil);
        BOOL showsCompletionBanner = options[@"hideCompletionBanner"] ? NO : YES;
        GKAchievement *achievement = [[GKAchievement alloc] initWithIdentifier:achievementId];
        if (achievement) {
            achievement.percentComplete = percentFloat;
            achievement.showsCompletionBanner = showsCompletionBanner;
            NSArray *achievements = @[achievement];
            [GKAchievement reportAchievements:achievements withCompletionHandler:^(NSError *error) {
                if (error != nil) reject(@"Error", @"Game Center setting Achievement", error);
                else resolve(achievements);
            }];
        }
    } @catch (NSError *e) {
        reject(@"Error", @"Error setting achievement.", e);
    }
}

RCT_EXPORT_METHOD(invite:(NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (_isGameCenterAvailable == NO) {
        return reject(@"Error", @"Game Center is Unavailable", nil);
    }
    GKMatchRequest *request = [[GKMatchRequest alloc] init];
    request.minPlayers = 2;
    request.maxPlayers = 4;
    request.recipients = @[@"G:8135064222"];
    request.inviteMessage = @"Your Custom Invitation Message Here";
    request.recipientResponseHandler = ^(GKPlayer *player, GKInviteeResponse response) {
        resolve(player);
    };
}

RCT_EXPORT_METHOD(getPlayerFriends:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (_isGameCenterAvailable == NO) {
        return reject(@"Error", @"Game Center is Unavailable", nil);
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [[GKLocalPlayer localPlayer] loadFriendPlayersWithCompletionHandler:^(NSArray<GKPlayer *> *friendPlayers, NSError *error) {
        if (error) reject(@"Error", @"Error getting player friends", error);
        else resolve(friendPlayers ?: @[]);
    }];
#pragma clang diagnostic pop
}

RCT_EXPORT_METHOD(challengePlayersToCompleteAchievement:(NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (_isGameCenterAvailable == NO) {
        return reject(@"Error", @"Game Center is Unavailable", nil);
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [[GKLocalPlayer localPlayer] loadFriendPlayersWithCompletionHandler:^(NSArray<GKPlayer *> *friendPlayers, NSError *error) {
        if (error) return reject(@"Error", @"Error loading friends for challenge", error);
        GKAchievement *achievement = [[GKAchievement alloc] init];
        [achievement selectChallengeablePlayers:friendPlayers withCompletionHandler:^(NSArray *challengeablePlayers, NSError *err) {
            if (challengeablePlayers) resolve(challengeablePlayers);
            else reject(@"Error", @"No challengeable players found", err);
        }];
    }];
#pragma clang diagnostic pop
}

#pragma mark - Realtime Multiplayer

/* -----------------------------------------------------------------------------------------------------------------------------------------
 Realtime multiplayer (GKMatch)
 -----------------------------------------------------------------------------------------------------------------------------------------*/

- (NSDictionary *)playerDict:(GKPlayer *)player {
    NSString *playerID;
    if (@available(iOS 12.4, *)) {
        playerID = player.gamePlayerID;
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        playerID = player.playerID;
#pragma clang diagnostic pop
    }
    return @{
        @"playerID": playerID ?: @"",
        @"alias": player.alias ?: @"",
        @"displayName": player.displayName ?: @"",
        @"isLocal": @([playerID isEqualToString:[self localPlayerID]]),
    };
}

- (NSString *)localPlayerID {
    GKLocalPlayer *localPlayer = [GKLocalPlayer localPlayer];
    if (@available(iOS 12.4, *)) {
        return localPlayer.gamePlayerID ?: @"";
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return localPlayer.playerID ?: @"";
#pragma clang diagnostic pop
}

- (NSDictionary *)matchPayload:(GKMatch *)match {
    NSMutableArray *players = [NSMutableArray array];
    for (GKPlayer *player in match.players) {
        [players addObject:[self playerDict:player]];
    }
    return @{
        @"players": players,
        @"expectedPlayerCount": @(match.expectedPlayerCount),
        @"localPlayerID": [self localPlayerID],
    };
}

- (void)registerInviteListenerIfNeeded {
    if (!self.inviteListenerRegistered) {
        self.inviteListenerRegistered = YES;
        [[GKLocalPlayer localPlayer] registerListener:self];
    }
}

RCT_EXPORT_METHOD(getLocalPlayerID:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (![GKLocalPlayer localPlayer].isAuthenticated) {
        return reject(@"not_authenticated", @"Local player is not authenticated with Game Center", nil);
    }
    resolve([self playerDict:[GKLocalPlayer localPlayer]]);
}

RCT_EXPORT_METHOD(presentMatchmaker:(NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (![GKLocalPlayer localPlayer].isAuthenticated) {
        return reject(@"not_authenticated", @"Local player is not authenticated with Game Center", nil);
    }
    if (self.matchmakerResolve != nil) {
        return reject(@"already_pending", @"A matchmaker request is already in progress", nil);
    }
    if (self.currentMatch != nil) {
        return reject(@"already_in_match", @"Already in a match; call disconnectMatch first", nil);
    }
    [self registerInviteListenerIfNeeded];

    GKMatchRequest *request = [[GKMatchRequest alloc] init];
    request.minPlayers = options[@"minPlayers"] ? [RCTConvert NSInteger:options[@"minPlayers"]] : 2;
    request.maxPlayers = options[@"maxPlayers"] ? [RCTConvert NSInteger:options[@"maxPlayers"]] : 4;
    if (options[@"inviteMessage"]) {
        request.inviteMessage = [RCTConvert NSString:options[@"inviteMessage"]];
    }

    GKMatchmakerViewController *matchmakerVC = [[GKMatchmakerViewController alloc] initWithMatchRequest:request];
    if (matchmakerVC == nil) {
        return reject(@"failed", @"Could not create matchmaker view controller", nil);
    }
    matchmakerVC.matchmakerDelegate = self;
    self.matchmakerResolve = resolve;
    self.matchmakerReject = reject;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[self getRootViewController] presentViewController:matchmakerVC animated:YES completion:nil];
    });
}

RCT_EXPORT_METHOD(sendMatchData:(NSString *)data
                  reliable:(BOOL)reliable
                  resolve:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (self.currentMatch == nil) {
        return reject(@"no_match", @"No active match", nil);
    }
    NSError *error = nil;
    BOOL sent = [self.currentMatch sendDataToAllPlayers:[data dataUsingEncoding:NSUTF8StringEncoding]
                                           withDataMode:reliable ? GKMatchSendDataReliable : GKMatchSendDataUnreliable
                                                  error:&error];
    if (!sent) {
        return reject(@"send_failed", error.localizedDescription ?: @"Failed to send match data", error);
    }
    resolve(nil);
}

RCT_EXPORT_METHOD(sendMatchDataToPlayers:(NSArray<NSString *> *)playerIDs
                  data:(NSString *)data
                  reliable:(BOOL)reliable
                  resolve:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (self.currentMatch == nil) {
        return reject(@"no_match", @"No active match", nil);
    }
    NSMutableArray<GKPlayer *> *recipients = [NSMutableArray array];
    for (GKPlayer *player in self.currentMatch.players) {
        NSString *playerID = [self playerDict:player][@"playerID"];
        if ([playerIDs containsObject:playerID]) {
            [recipients addObject:player];
        }
    }
    if (recipients.count == 0) {
        return reject(@"no_recipients", @"None of the given playerIDs are in the current match", nil);
    }
    NSError *error = nil;
    BOOL sent = [self.currentMatch sendData:[data dataUsingEncoding:NSUTF8StringEncoding]
                                  toPlayers:recipients
                                   dataMode:reliable ? GKMatchSendDataReliable : GKMatchSendDataUnreliable
                                      error:&error];
    if (!sent) {
        return reject(@"send_failed", error.localizedDescription ?: @"Failed to send match data", error);
    }
    resolve(nil);
}

RCT_EXPORT_METHOD(getMatchPlayers:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (self.currentMatch == nil) {
        return reject(@"no_match", @"No active match", nil);
    }
    resolve([self matchPayload:self.currentMatch]);
}

RCT_EXPORT_METHOD(disconnectMatch:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (self.currentMatch != nil) {
        self.currentMatch.delegate = nil;
        [self.currentMatch disconnect];
        self.currentMatch = nil;
    }
    resolve(nil);
}

#pragma mark GKMatchmakerViewControllerDelegate

- (void)matchmakerViewController:(GKMatchmakerViewController *)viewController didFindMatch:(GKMatch *)match {
    [viewController dismissViewControllerAnimated:YES completion:nil];
    match.delegate = self;
    self.currentMatch = match;
    NSDictionary *payload = [self matchPayload:match];
    if (self.matchmakerResolve) {
        RCTPromiseResolveBlock resolve = self.matchmakerResolve;
        self.matchmakerResolve = nil;
        self.matchmakerReject = nil;
        resolve(payload);
    }
    // Also emitted so the invite-accepted flow (no pending promise) shares one JS code path.
    [self emit:@"gc:matchFound" body:payload];
}

- (void)matchmakerViewControllerWasCancelled:(GKMatchmakerViewController *)viewController {
    [viewController dismissViewControllerAnimated:YES completion:nil];
    if (self.matchmakerReject) {
        RCTPromiseRejectBlock reject = self.matchmakerReject;
        self.matchmakerResolve = nil;
        self.matchmakerReject = nil;
        reject(@"cancelled", @"Matchmaking was cancelled", nil);
    }
}

- (void)matchmakerViewController:(GKMatchmakerViewController *)viewController didFailWithError:(NSError *)error {
    [viewController dismissViewControllerAnimated:YES completion:nil];
    if (self.matchmakerReject) {
        RCTPromiseRejectBlock reject = self.matchmakerReject;
        self.matchmakerResolve = nil;
        self.matchmakerReject = nil;
        reject(@"failed", error.localizedDescription ?: @"Matchmaking failed", error);
    }
}

#pragma mark GKMatchDelegate

- (void)match:(GKMatch *)match didReceiveData:(NSData *)data fromRemotePlayer:(GKPlayer *)player {
    if (match != self.currentMatch) return;
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [self emit:@"gc:data" body:@{
        @"fromPlayerID": [self playerDict:player][@"playerID"],
        @"data": string ?: @"",
    }];
}

- (void)match:(GKMatch *)match player:(GKPlayer *)player didChangeConnectionState:(GKPlayerConnectionState)state {
    if (match != self.currentMatch) return;
    NSString *stateName = state == GKPlayerStateConnected ? @"connected"
                        : state == GKPlayerStateDisconnected ? @"disconnected"
                        : @"unknown";
    [self emit:@"gc:playerState" body:@{
        @"playerID": [self playerDict:player][@"playerID"],
        @"state": stateName,
        @"expectedPlayerCount": @(match.expectedPlayerCount),
    }];
}

- (void)match:(GKMatch *)match didFailWithError:(NSError *)error {
    if (match != self.currentMatch) return;
    [self emit:@"gc:matchError" body:@{
        @"message": error.localizedDescription ?: @"Match failed",
    }];
}

- (BOOL)match:(GKMatch *)match shouldReinviteDisconnectedPlayer:(GKPlayer *)player {
    // The app converts disconnected seats to AI instead of stalling on a reinvite.
    return NO;
}

#pragma mark GKLocalPlayerListener (invites)

- (void)player:(GKPlayer *)player didAcceptInvite:(GKInvite *)invite {
    [self emit:@"gc:inviteAccepted" body:@{
        @"fromPlayerID": [self playerDict:player][@"playerID"],
    }];
    GKMatchmakerViewController *matchmakerVC = [[GKMatchmakerViewController alloc] initWithInvite:invite];
    if (matchmakerVC == nil) return;
    matchmakerVC.matchmakerDelegate = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[self getRootViewController] presentViewController:matchmakerVC animated:YES completion:nil];
    });
}

- (void)gameCenterViewControllerDidFinish:(GKGameCenterViewController *)viewController {
    [viewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)gameCenterViewControllerDidCancel:(GKGameCenterViewController *)gameCenterViewController {
    [gameCenterViewController dismissViewControllerAnimated:YES completion:nil];
}

-(void)showLeaderboardAndAchievements:(BOOL)shouldShowLeaderboard {
    UIViewController *mainController = [self getRootViewController];
    GKGameCenterViewController *gcViewController;
    if (@available(iOS 14.0, *)) {
        if (shouldShowLeaderboard) {
            gcViewController = [[GKGameCenterViewController alloc] initWithLeaderboardID:_leaderboardIdentifier
                                                                             playerScope:GKLeaderboardPlayerScopeGlobal
                                                                               timeScope:GKLeaderboardTimeScopeAllTime];
        } else {
            gcViewController = [[GKGameCenterViewController alloc] initWithState:GKGameCenterViewControllerStateAchievements];
        }
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        gcViewController = [[GKGameCenterViewController alloc] init];
        gcViewController.viewState = shouldShowLeaderboard ? GKGameCenterViewControllerStateLeaderboards : GKGameCenterViewControllerStateAchievements;
        if (shouldShowLeaderboard) gcViewController.leaderboardIdentifier = _leaderboardIdentifier;
#pragma clang diagnostic pop
    }
    gcViewController.gameCenterDelegate = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [mainController presentViewController:gcViewController animated:YES completion:nil];
    });
}

RCT_EXPORT_METHOD(showLeaderBoard) {
    if (_isGameCenterAvailable == NO) return;
    [self showLeaderboardAndAchievements:YES];
}

RCT_EXPORT_METHOD(validateLeaderboardID:(NSString *)leaderboardIdentifier
                  resolve:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (_isGameCenterAvailable == NO) {
        return reject(@"Error", @"Game Center is Unavailable", nil);
    }
    if (@available(iOS 14.0, *)) {
        [GKLeaderboard loadLeaderboardsWithIDs:@[leaderboardIdentifier] completionHandler:^(NSArray<GKLeaderboard *> *leaderboards, NSError *error) {
            if (error) {
                reject(@"Error", @"Error validating leaderboard ID", error);
            } else if (leaderboards.count == 0) {
                reject(@"Error", [NSString stringWithFormat:@"Leaderboard ID not found: %@", leaderboardIdentifier], nil);
            } else {
                resolve(@{@"leaderboardIdentifier": leaderboardIdentifier, @"valid": @YES});
            }
        }];
    } else {
        // Pre-iOS 14: no side-effect-free validation API; assume valid.
        resolve(@{@"leaderboardIdentifier": leaderboardIdentifier, @"valid": @YES});
    }
}

RCT_EXPORT_METHOD(reportScore:(nonnull NSNumber *)newScore leaderboardIdentifier:(NSString *)leaderboardIdentifier
                  resolve:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (_isGameCenterAvailable == NO) {
        return reject(@"Error", @"Game Center is Unavailable", nil);
    }
    if (@available(iOS 14.0, *)) {
        [GKLeaderboard submitScore:newScore.integerValue
                           context:0
                            player:[GKLocalPlayer localPlayer]
                    leaderboardIDs:@[leaderboardIdentifier]
                 completionHandler:^(NSError *error) {
            if (error) reject(@"Error", @"Error submitting score", error);
            else resolve(@"Successfully submitted score");
        }];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        GKScore *score = [[GKScore alloc] initWithLeaderboardIdentifier:leaderboardIdentifier];
        score.value = newScore.doubleValue;
        [GKScore reportScores:@[score] withCompletionHandler:^(NSError *error) {
            if (error) reject(@"Error", @"Error submitting score", error);
            else resolve(@"Successfully submitted score");
        }];
#pragma clang diagnostic pop
    }
}

RCT_EXPORT_METHOD(authenticateLocalPlayer:(RCTResponseSenderBlock)callback) {
    UIViewController *mainController = [self getRootViewController];
    GKLocalPlayer *localPlayer = [GKLocalPlayer localPlayer];
    __block Boolean called = false;
    __weak typeof(self) weakSelf = self;
    localPlayer.authenticateHandler = ^(UIViewController *viewController, NSError *error) {
        if (viewController != nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [mainController presentViewController:viewController animated:YES completion:nil];
            });
        } else {
            if ([GKLocalPlayer localPlayer].authenticated) {
                _isGameCenterAvailable = YES;
                [weakSelf registerInviteListenerIfNeeded];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                [[GKLocalPlayer localPlayer] loadDefaultLeaderboardIdentifierWithCompletionHandler:^(NSString *leaderboardIdentifier, NSError *error) {
                    if (error != nil) NSLog(@"%@", [error localizedDescription]);
                    else _leaderboardIdentifier = leaderboardIdentifier;
                }];
#pragma clang diagnostic pop
            } else {
                _isGameCenterAvailable = NO;
                if (error != nil) NSLog(@"Game Center authentication failed: %@", [error localizedDescription]);
            }
            // Report the result once, on both success and failure, so the JS side
            // can react to a failed sign-in instead of waiting forever.
            if (!called) {
                called = true;
                callback(@[@{@"success": @(_isGameCenterAvailable)}]);
            }
        }
    };
}

RCT_EXPORT_METHOD(loadSavedGameData:(NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    GKLocalPlayer *mobSvcAccount = [GKLocalPlayer localPlayer];
    if (!mobSvcAccount.isAuthenticated) {
        return reject(@"Error", @"Can't load game: Game center is not initialized...", nil);
    }
    [mobSvcAccount fetchSavedGamesWithCompletionHandler:^(NSArray<GKSavedGame *> *savedGames, NSError *error) {
        if (error != nil) {
            NSLog(@"Failed to prepare saved game data: %@", error.description);
            return reject(@"Error", @"Can't load game", nil);
        }
        GKSavedGame *savedGameToLoad = nil;
        for (GKSavedGame *savedGame in savedGames) {
            if ([savedGame.name isEqualToString:options[@"name"]]) {
                if (savedGameToLoad == nil || savedGameToLoad.modificationDate < savedGame.modificationDate) {
                    savedGameToLoad = savedGame;
                }
            }
        }
        if (savedGameToLoad == nil) {
            resolve(@{@"isConflict": @false, @"data": @""});
            return;
        }
        [savedGameToLoad loadDataWithCompletionHandler:^(NSData *data, NSError *loadError) {
            if (loadError == nil) {
                NSError *unarchiveError = nil;
                MobSvcSavedGameData *savedGameData;
                if (@available(iOS 12.0, *)) {
                    savedGameData = [NSKeyedUnarchiver unarchivedObjectOfClass:[MobSvcSavedGameData class]
                                                                      fromData:data
                                                                         error:&unarchiveError];
                } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                    savedGameData = [NSKeyedUnarchiver unarchiveObjectWithData:data];
#pragma clang diagnostic pop
                }
                if (savedGameData) {
                    resolve(@{@"isConflict": @false, @"data": savedGameData.data ?: @""});
                } else {
                    reject(@"Error", @"Can't decode saved game data", unarchiveError);
                }
            } else {
                NSLog(@"Failed to download saved game data: %@", loadError.description);
                reject(@"Error", @"Can't load game", loadError);
            }
        }];
    }];
}

RCT_EXPORT_METHOD(uploadSavedGameData:(NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    GKLocalPlayer *mobSvcAccount = [GKLocalPlayer localPlayer];
    if (!mobSvcAccount.isAuthenticated) {
        return reject(@"Error", @"Can't save game: Game center is not initialized...", nil);
    }
    MobSvcSavedGameData *savedGameData = [[MobSvcSavedGameData alloc] init];
    savedGameData.data = options[@"data"];
    NSData *archivedData;
    NSError *archiveError = nil;
    if (@available(iOS 12.0, *)) {
        archivedData = [NSKeyedArchiver archivedDataWithRootObject:savedGameData
                                            requiringSecureCoding:YES
                                                            error:&archiveError];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        archivedData = [NSKeyedArchiver archivedDataWithRootObject:savedGameData];
#pragma clang diagnostic pop
    }
    if (!archivedData) {
        return reject(@"Error", @"Can't encode game data", archiveError);
    }
    [mobSvcAccount saveGameData:archivedData withName:options[@"name"] completionHandler:^(GKSavedGame *savedGame __unused, NSError *error) {
        if (error == nil) {
            NSLog(@"Successfully uploaded saved game data");
            resolve(@"Saved game data");
        } else {
            NSLog(@"Failed to upload saved game data: %@", error.description);
            reject(@"Error", @"Can't save game", error);
        }
    }];
}

@end


@implementation MobSvcSavedGameData

#pragma mark MobSvcSavedGameData implementation

static NSString * const sgDataKey = @"data";

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)sharedGameData {
    static id sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (void)reset {
    self.data = nil;
}

- (void)encodeWithCoder:(NSCoder *)encoder {
    [encoder encodeObject:self.data forKey:sgDataKey];
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)decoder {
    self = [self init];
    if (self) {
        self.data = [decoder decodeObjectOfClass:[NSString class] forKey:sgDataKey];
    }
    return self;
}

@end
