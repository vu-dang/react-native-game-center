//
//  RNGameCenter.h
//  StockShot
//
//  Created by vyga on 9/18/17.
//  Copyright © 2017 Facebook. All rights reserved.
//

#import <GameKit/GameKit.h>

#if __has_include("RCTBridgeModule.h")
#import "RCTBridgeModule.h"
#else
#import <React/RCTBridgeModule.h>
#endif

#if __has_include("RCTEventEmitter.h")
#import "RCTEventEmitter.h"
#else
#import <React/RCTEventEmitter.h>
#endif

@interface RNGameCenter : RCTEventEmitter <RCTBridgeModule,
                                           GKMatchDelegate,
                                           GKMatchmakerViewControllerDelegate,
                                           GKTurnBasedMatchmakerViewControllerDelegate,
                                           GKTurnBasedEventListener,
                                           GKLocalPlayerListener>

@end
