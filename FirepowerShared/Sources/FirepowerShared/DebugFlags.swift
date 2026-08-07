import Foundation

/// Developer-only overrides for verifying fallback UI without per-call plumbing.
///
/// Shared between the app and widget extension targets (two separate processes
/// with no App Group configured), so a source-level constant — not UserDefaults,
/// which wouldn't sync across the process boundary — is the simplest way to flip
/// one switch and have both the game list and every Dynamic Island surface pick
/// it up in the same rebuild.
public enum DebugFlags {
    /// Forces the team-color tricode badge fallback everywhere a logo image would
    /// normally render — the game list (GameRowView) and every DI surface (compact,
    /// expanded, minimal) — even though the real logo assets are present in this
    /// build. Flip to `true`, rebuild, run in the simulator to verify the fallback
    /// appearance without needing Xcode Previews.
    ///
    /// This does NOT replace the real `UIImage(named:) != nil` check or the planned
    /// EXCLUDED_SOURCE_FILE_NAMES build-setting split for App Store submission —
    /// it's a developer convenience layered on top. The `#if DEBUG` guard means
    /// Release builds always evaluate this to `false` regardless of the literal
    /// below, so it can never affect what ships.
    #if DEBUG
    public static let forceTricodeFallback = false
    #else
    public static let forceTricodeFallback = false
    #endif
}
