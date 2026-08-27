import Foundation

/// Shared `UserDefaults` key so `SettingsView` (writer) and the poke
/// backend's `handleIncomingPoke` (reader) agree on the same string.
enum PokeSettings {
    static let doNotDisturbKey = "cz.peelco.jolt.pokesDoNotDisturb"
}
