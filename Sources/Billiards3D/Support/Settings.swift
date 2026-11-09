import Foundation

/// The choices and the game in progress, kept between sessions in the user defaults. The window keeps its own frame.
struct Settings {
    var theme = 0
    var level = 3
    var mode = 0
    /// Eight-ball, nine-ball, «Американка».
    var game = 0
    /// Full, short, off.
    var aim = 0
    /// Overview, behind, top.
    var camera = 0
    var breaker = 0
    var sound = true
    var panel = true
    var language = Language.system
    /// The balls and the score, as text; see `Match.text(with:)`.
    var match = ""
    /// The lines of the game's history, each after its kind, separated by '|'.
    var history = ""

    private enum Key {
        static let theme = "Theme"
        static let level = "Level"
        static let mode = "Mode"
        static let game = "Game"
        static let aim = "Aim"
        static let camera = "Camera"
        static let breaker = "Breaker"
        static let sound = "Sound"
        static let panel = "Panel"
        static let language = "Language"
        static let match = "Match"
        static let history = "History"
    }

    static func load(themeCount: Int) -> Settings {
        let defaults = UserDefaults.standard
        func integer(_ key: String, _ fallback: Int) -> Int { defaults.object(forKey: key) as? Int ?? fallback }
        func clamped(_ key: String, _ fallback: Int, _ low: Int, _ high: Int) -> Int { min(max(integer(key, fallback), low), high) }
        var settings = Settings()
        settings.theme = clamped(Key.theme, 0, 0, themeCount - 1)
        settings.level = clamped(Key.level, 3, 1, 5)
        settings.mode = clamped(Key.mode, 0, 0, 3)
        settings.game = clamped(Key.game, 0, 0, 2)
        settings.aim = clamped(Key.aim, 0, 0, 2)
        settings.camera = clamped(Key.camera, 0, 0, 2)
        settings.breaker = clamped(Key.breaker, 0, 0, 1)
        settings.sound = integer(Key.sound, 1) != 0
        settings.panel = integer(Key.panel, 1) != 0
        settings.language = Language(rawValue: integer(Key.language, -1)) ?? Language.system
        settings.match = defaults.string(forKey: Key.match) ?? ""
        settings.history = defaults.string(forKey: Key.history) ?? ""
        return settings
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(theme, forKey: Key.theme)
        defaults.set(level, forKey: Key.level)
        defaults.set(mode, forKey: Key.mode)
        defaults.set(game, forKey: Key.game)
        defaults.set(aim, forKey: Key.aim)
        defaults.set(camera, forKey: Key.camera)
        defaults.set(breaker, forKey: Key.breaker)
        defaults.set(sound ? 1 : 0, forKey: Key.sound)
        defaults.set(panel ? 1 : 0, forKey: Key.panel)
        defaults.set(language.rawValue, forKey: Key.language)
        defaults.set(match, forKey: Key.match)
        defaults.set(history, forKey: Key.history)
    }
}
