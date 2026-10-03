/// Built for Google Play (`--dart-define=PLAY_STORE=true`). That build has
/// no background service: Play does not allow it for games.
const bool playStoreBuild = bool.fromEnvironment('PLAY_STORE');
