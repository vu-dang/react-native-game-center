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
}

declare const RNGameCenter: RNGameCenterModule;
export default RNGameCenter;
