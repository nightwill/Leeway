import Foundation

/// A variable of the user's login environment that the app has to know about,
/// kept across launches.
///
/// Asking the login shell costs a shell start-up, profile and all, which is why
/// the answer is remembered: the values are wanted from the app's first frame,
/// and only the very first launch has to open on a guess.
struct LoginVariable {

    /// The name the shell exports it under.
    let name: String

    /// Where the last answer is kept. It is passed in rather than derived from
    /// the name so a variable can be renamed without every user's remembered
    /// answer being dropped along with it.
    let defaultsKey: String

    /// What the variable holds, `nil` when it holds nothing.
    ///
    /// Our own environment answers for an app opened from a terminal. Opened
    /// from Finder we hold launchd's environment, where no profile has ever
    /// been read, and the last answer from the login shell is all there is.
    var value: String? {
        let inherited = ProcessInfo.processInfo.environment[name]
        if let inherited, !inherited.isEmpty { return inherited }
        return UserDefaults.standard.string(forKey: defaultsKey)
    }

    /// Asks the login shell and keeps the answer. Belongs off the main thread.
    ///
    /// A shell that could not be asked leaves the last answer standing — it is
    /// the better guess of the two, and a profile that has stopped exporting
    /// the variable says so the moment the shell can be asked again.
    func refresh() {
        switch LoginShell.reading(of: name) {
        case .exported(let value): UserDefaults.standard.set(value, forKey: defaultsKey)
        case .unset: UserDefaults.standard.removeObject(forKey: defaultsKey)
        case .unanswered: break
        }
    }
}
