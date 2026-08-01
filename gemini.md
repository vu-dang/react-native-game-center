# react-native-game-center Project Overview

## Project Description
`react-native-game-center` is a React Native native module fork (`vu-dang/react-native-game-center`) that provides integration with Apple's Game Center. It is used as a core dependency in the sibling applications (like TienLen, Spades, StackMatch, FreeCellChampion, KlondikeChampion) to power multiplayer networking, real-time game events, leaderboards, and achievements.

## Architecture & Codebase Notes
- **Native iOS Module**: Contains Objective-C code (`RNGameCenter.m` / `.h`) to interface with the iOS `GameKit` framework.
- **JavaScript Interface**: Exposes a React Native bridge for JavaScript clients to authenticate players, load friends, submit scores, and handle multiplayer matches.
- **Event Listeners**: It emits Game Center events (like `gc:authChanged`) to JavaScript, which dependent apps listen for to handle connection and authentication states.

## Guidelines for New Tasks
1. **Backward Compatibility**: Because this module is a core dependency for multiple games in this workspace, any changes to the native Objective-C interface or JS bridge must be carefully validated to ensure they do not break the dependent projects.
2. **Native iOS Builds**: Changes to iOS native code here will require the consuming apps to run `pod install` and clean their build folders.
3. **Maintain Documentation**: After every change or completed task, you must update this `gemini.md` file to reflect the current state of the project, adding any new architectural shifts, feature additions, or relevant context if applicable.
4. **Preserve External URLs & Domain Names**: Do NOT modify, update, or substitute existing domain names, URLs, or support emails (e.g., knownpoint.com) during refactoring unless explicitly requested by the user.
