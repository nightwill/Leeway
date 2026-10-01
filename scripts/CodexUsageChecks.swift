import Foundation

// Fixture strings belong to the test protocol, not the app's interface.
// swiftlint:disable non_localized_string

@main
struct CodexUsageChecks {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let fiveHour: [String: Any] = ["usedPercent": 25, "windowDurationMins": 300, "resetsAt": 1_800_010_000]
    static let sevenDay: [String: Any] = ["usedPercent": 60, "windowDurationMins": 10_080, "resetsAt": 1_800_100_000]
    static let limits: [String: Any] = ["limitId": "codex", "primary": fiveHour, "secondary": sevenDay]

    static func main() async throws {
        if CommandLine.arguments.dropFirst().first == "app-server" {
            try fixture()
            return
        }
        if CommandLine.arguments.contains("--live") {
            let reading = try await CodexUsageCommand.read()
            print("Live Codex reading: 5h=\(reading.fiveHour?.usedPercentage.description ?? "—"), 7d=\(reading.sevenDay?.usedPercentage.description ?? "—")")
            return
        }
        try checkSnapshots()
        try checkTransport()
        try checkModelMenu()
        print("Codex usage checks passed: quota parsing, the model menu with its levels, RPC handshake, errors, timeouts and process cleanup.")
    }

    static func snapshot(_ payload: [String: Any]) throws -> UsageSnapshot {
        try CodexUsageCommand.snapshot(from: JSONSerialization.data(withJSONObject: payload), now: now)
    }

    static func checkSnapshots() throws {
        let reading = try snapshot(["rateLimits": limits])
        precondition(reading.fiveHour?.usedPercentage == 25 && reading.sevenDay?.usedPercentage == 60)
        precondition(reading.fiveHour?.timeLeft(at: now) == 10_000)
        precondition(reading.fiveHour?.usedPercentage(at: now + 10_001) == nil)

        let multiple = try snapshot([
            "rateLimits": ["limitId": "other", "primary": ["usedPercent": 99]],
            "rateLimitsByLimitId": ["codex": limits],
        ])
        precondition(multiple == reading)
        let reversed = try snapshot(["rateLimits": ["primary": sevenDay, "secondary": fiveHour]])
        precondition(reversed == reading)
        let empty = try snapshot(["rateLimits": ["primary": NSNull(), "secondary": NSNull()]])
        precondition(empty.isEmpty)
        let missingReset = try snapshot(["rateLimits": ["primary": ["usedPercent": 0, "windowDurationMins": 300]]])
        precondition(missingReset.isEmpty)

        for payload: [String: Any] in [
            [:],
            ["rateLimits": ["limitId": "other", "primary": fiveHour]],
            ["rateLimits": ["primary": ["usedPercent": "bad"]]],
            ["rateLimits": ["primary": ["usedPercent": 2, "windowDurationMins": 15, "resetsAt": 1_800_010_000]]],
        ] {
            do {
                _ = try snapshot(payload)
                preconditionFailure("Invalid or unsupported quota was accepted")
            } catch { /* Expected rejection. */ }
        }
    }

    static func checkTransport() throws {
        let executable = URL(filePath: CommandLine.arguments[0])
        let reading = try CodexUsageCommand.read(executable: executable, environment: ["LEEWAY_FIXTURE": "success"])
        precondition(reading.fiveHour?.usedPercentage == 25 && reading.sevenDay?.usedPercentage == 60)
        for mode in ["signedOut", "apiKey", "rpcError", "malformed", "exit", "timeout"] {
            let started = Date.now
            do {
                _ = try CodexUsageCommand.read(executable: executable, environment: ["LEEWAY_FIXTURE": mode], timeout: 0.5)
                preconditionFailure("Expected failure for \(mode)")
            } catch let failure as CodexUsageCommand.Failure {
                switch (mode, failure) {
                case ("signedOut", .signInRequired), ("apiKey", .subscriptionRequired),
                     ("rpcError", .reported), ("exit", .unreadable), ("timeout", .timedOut): break
                default: preconditionFailure("Wrong failure for \(mode): \(failure)")
                }
            } catch {
                precondition(mode == "malformed", "Unexpected error: \(error)")
            }
            precondition(Date.now.timeIntervalSince(started) < 3, "Child process outlived its deadline")
        }
        let echo = try ChildProcess.run(URL(filePath: "/bin/echo"), arguments: ["unchanged"], keepingStandardError: true, timeout: 2)
        precondition(echo.status == 0 && echo.output == "unchanged\n" && !echo.timedOut)
    }

    static func checkModelMenu() throws {
        let executable = URL(filePath: CommandLine.arguments[0])
        let menu = try CodexAppServer.run(executable: executable, environment: ["LEEWAY_FIXTURE": "models"], timeout: 2) {
            try CodexModelCommand.menu(over: &$0)
        }
        // The provider's own choice leads, hidden models are left out, and the
        // configured model is in the menu although the listing never named it.
        precondition(menu.options.map(\.id) == [nil, "gpt-5-codex", "gpt-5", "gpt-6-unlisted"])
        precondition(menu.options.map(\.title) == ["Default", "GPT-5 Codex", "gpt-5", "gpt-6-unlisted"])
        precondition(menu.current == "gpt-6-unlisted")
        // Each entry offers its own model's levels, the provider's choice those
        // of the model Codex marks as default, and all show the one level set.
        precondition(menu.options.map(\.levels) == [["low", "high"], ["low", "high"], nil, nil])
        precondition(menu.options.allSatisfy { $0.levels == nil || $0.effort == "high" })

        for (mode, model) in [("modelWrite", "gpt-5"), ("modelClear", nil)] as [(String, String?)] {
            try CodexAppServer.run(executable: executable, environment: ["LEEWAY_FIXTURE": mode], timeout: 2) {
                try CodexModelCommand.set(model, over: &$0)
            }
        }
        try CodexAppServer.run(executable: executable, environment: ["LEEWAY_FIXTURE": "modelEffortWrite"], timeout: 2) {
            try CodexModelCommand.set("gpt-5", effort: .some(nil), over: &$0)
        }

        let unchanged = ModelMenu(options: menu.options, current: "gpt-5")
        precondition(unchanged.options.count == menu.options.count, "A listed model was added to the menu twice")

        // A level is shared on Codex, and an entry without levels moves none.
        let lowered = menu.choosing(menu.options[1], effort: "low", sharedEffort: true)
        precondition(lowered.options.filter { $0.levels != nil }.allSatisfy { $0.effort == "low" })
        let unlisted = lowered.choosing(menu.options[3], effort: nil, sharedEffort: true)
        precondition(unlisted.current == "gpt-6-unlisted" && unlisted.options[1].effort == "low")
    }

    static func receive(_ method: String) throws -> Int? {
        try request(method)["id"] as? Int
    }

    static func request(_ method: String) throws -> [String: Any] {
        guard let line = readLine(), let message = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            preconditionFailure("Missing request")
        }
        precondition(message["method"] as? String == method, "Unexpected request order or model turn")
        return message
    }

    static func send(_ message: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        // Splitting a message exercises framing across pipe reads.
        try FileHandle.standardOutput.write(contentsOf: data.prefix(3))
        try FileHandle.standardOutput.write(contentsOf: data.dropFirst(3))
    }

    /// A server that answers the model menu and takes the setting back.
    static func models(_ mode: String) throws {
        if mode == "models" {
            let listID = try receive("model/list")!
            try send(["id": listID, "result": ["data": [
                ["id": "gpt-5-codex", "displayName": "GPT-5 Codex", "hidden": false, "isDefault": true,
                 "supportedReasoningEfforts": [["reasoningEffort": "low"], ["reasoningEffort": "high"]]],
                ["id": "gpt-5"],
                ["id": "gpt-5-internal", "displayName": "Internal", "hidden": true],
            ]]])
            let configID = try receive("config/read")!
            try send(["id": configID, "result": ["config": ["model": "gpt-6-unlisted", "model_reasoning_effort": "high"]]])
            return
        }

        let write = try request("config/value/write")
        let params = write["params"] as? [String: Any]
        precondition(params?["keyPath"] as? String == "model" && params?["mergeStrategy"] as? String == "replace")
        if mode == "modelClear" {
            precondition(params?["value"] is NSNull, "Clearing the model has to be written as a null")
        } else {
            precondition(params?["value"] as? String == "gpt-5", "The chosen model never reached the server")
        }
        try send(["id": write["id"] as? Int ?? 0, "result": ["status": "ok"]])
        guard mode == "modelEffortWrite" else { return }

        let effort = try request("config/value/write")
        let effortParams = effort["params"] as? [String: Any]
        precondition(effortParams?["keyPath"] as? String == "model_reasoning_effort", "The level was not written after the model")
        precondition(effortParams?["value"] is NSNull, "The model's own default level has to be written as a null")
        try send(["id": effort["id"] as? Int ?? 0, "result": ["status": "ok"]])
    }

    static func fixture() throws {
        let mode = ProcessInfo.processInfo.environment["LEEWAY_FIXTURE"] ?? "success"
        if mode == "exit" { return }
        if mode == "timeout" { Thread.sleep(forTimeInterval: 10); return }
        let initializeID = try receive("initialize")!
        if mode == "malformed" {
            try FileHandle.standardOutput.write(contentsOf: Data("not json\n".utf8))
            return
        }
        try send(["id": initializeID, "result": [:]])
        _ = try receive("initialized")
        if mode.hasPrefix("model") {
            try models(mode)
            return
        }
        let accountID = try receive("account/read")!
        let account: Any = mode == "signedOut" ? NSNull() : ["type": mode == "apiKey" ? "apiKey" : "chatgpt"]
        try send(["id": accountID, "result": ["account": account]])
        if mode == "signedOut" || mode == "apiKey" { return }
        let limitsID = try receive("account/rateLimits/read")!
        // A notification larger than a pipe buffer must be drained and ignored.
        try send(["method": "account/updated", "params": ["padding": String(repeating: "x", count: 100_000)]])
        if mode == "rpcError" {
            try send(["id": limitsID, "error": ["code": -1, "message": "fixture failure"]])
        } else {
            try send(["id": limitsID, "result": ["rateLimits": limits]])
        }
        // The parent must stop a server that stays alive after its response.
        Thread.sleep(forTimeInterval: 10)
    }
}
// swiftlint:enable non_localized_string
