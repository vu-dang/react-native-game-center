import type { EmitterSubscription, NativeEventEmitter } from 'react-native';

export interface GCPlayer {
  /** GKPlayer.gamePlayerID — stable per game per player. */
  playerID: string;
  alias: string;
  displayName: string;
  isLocal: boolean;
}

export interface MatchFoundPayload {
  players: GCPlayer[];
  /** Players Game Center is still connecting; 0 when everyone is in. */
  expectedPlayerCount: number;
  localPlayerID: string;
  /**
   * playerGroup of the request (or accepted invite) that produced this
   * match; 0 when none was set.
   */
  playerGroup: number;
}

export interface MatchDataPayload {
  fromPlayerID: string;
  data: string;
}

export interface PlayerStatePayload {
  playerID: string;
  state: 'connected' | 'disconnected' | 'unknown';
  expectedPlayerCount: number;
}

export interface InviteAcceptedPayload {
  fromPlayerID: string;
  /** playerGroup the inviter matchmade with; 0 when none was set. */
  playerGroup: number;
  /** playerAttributes the inviter matchmade with; 0 when none were set. */
  playerAttributes: number;
}

export interface MatchErrorPayload {
  message: string;
}

export type GCEventName =
  | 'gc:matchFound'
  | 'gc:data'
  | 'gc:playerState'
  | 'gc:inviteAccepted'
  | 'gc:matchError';

export interface GCEventPayloads {
  'gc:matchFound': MatchFoundPayload;
  'gc:data': MatchDataPayload;
  'gc:playerState': PlayerStatePayload;
  'gc:inviteAccepted': InviteAcceptedPayload;
  'gc:matchError': MatchErrorPayload;
}

export interface PresentMatchmakerOptions {
  minPlayers?: number;
  maxPlayers?: number;
  inviteMessage?: string;
  /**
   * Auto-match pool. Game Center only pairs requests that share a
   * playerGroup, so give each multiplayer mode (e.g. 2v2, co-op, duel) its
   * own non-zero group to keep their queues separate.
   */
  playerGroup?: number;
  /**
   * uint32 bit mask of complementary roles for auto-matching within a
   * playerGroup (see GKMatchRequest.playerAttributes).
   */
  playerAttributes?: number;
}

export interface RNGameCenterModule {
  // Auth / player
  init(options: { leaderboardIdentifier: string; achievementIdentifier?: string }): Promise<any>;
  userLogged(): Promise<boolean>;
  getPlayer(): Promise<{ alias: string; displayName: string; playerID: string }>;
  getPlayerFriends(): Promise<any[]>;
  getPlayerImage(): Promise<{ image: string | null }>;

  // Leaderboards
  openLeaderboardModal(options?: { leaderboardIdentifier?: string }): Promise<any>;
  submitLeaderboardScore(options: { score: number; leaderboardIdentifier?: string }): Promise<any>;
  validateLeaderboardID(leaderboardIdentifier: string): Promise<{ leaderboardIdentifier: string; valid: boolean }>;
  reportScore(score: number, leaderboardIdentifier: string): Promise<any>;

  // Achievements
  openAchievementModal(options?: object): Promise<any>;
  getAchievements(): Promise<any[]>;
  resetAchievements(options?: { hideAlert?: boolean }): Promise<any>;
  submitAchievementScore(options: {
    percentComplete: number;
    achievementIdentifier?: string;
    hideCompletionBanner?: boolean;
  }): Promise<any>;

  // Saved games
  uploadSavedGameData(options: { name: string; data: string }): Promise<any>;
  loadSavedGameData(options: { name: string }): Promise<{ isConflict: boolean; data: string }>;

  // Realtime multiplayer (GKMatch)
  getEventEmitter(): NativeEventEmitter;
  addEventListener<E extends GCEventName>(
    event: E,
    handler: (payload: GCEventPayloads[E]) => void,
  ): EmitterSubscription;
  getLocalPlayerID(): Promise<GCPlayer>;
  presentMatchmaker(options?: PresentMatchmakerOptions): Promise<MatchFoundPayload>;
  sendMatchData(data: string, reliable?: boolean): Promise<void>;
  sendMatchDataToPlayers(playerIDs: string[], data: string, reliable?: boolean): Promise<void>;
  getMatchPlayers(): Promise<MatchFoundPayload>;
  disconnectMatch(): Promise<void>;

  // Turn-based multiplayer (GKTurnBasedMatch)
  startTurnBasedMatchmaker(options?: { minPlayers?: number; maxPlayers?: number; playerGroup?: number }): Promise<boolean>;
  loadTurnBasedMatches(): Promise<Array<{
    matchID: string;
    matchData: string;
    isMyTurn: boolean;
    status: number;
    opponentName: string;
    currentTurnPlayerId: string;
  }>>;
  endTurnWithNextParticipants(matchID: string, matchDataString: string): Promise<boolean>;
  quitTurnBasedMatch(matchID: string): Promise<boolean>;
}

declare const RNGameCenter: RNGameCenterModule;
export default RNGameCenter;
