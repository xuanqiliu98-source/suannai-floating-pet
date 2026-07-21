import Foundation

final class CodexBridge: @unchecked Sendable {
    typealias UsageHandler = @Sendable (Double) -> Void
    typealias StatusHandler = @Sendable (String) -> Void
    typealias ActivityHandler = @Sendable (Bool) -> Void
    typealias ApprovalHandler = @Sendable (Bool) -> Void
    typealias CompletionHandler = @Sendable (String) -> Void

    private let onWeeklyRemaining: UsageHandler
    private let onStatus: StatusHandler
    private let onActivity: ActivityHandler
    private let onApproval: ApprovalHandler
    private let onCompletion: CompletionHandler
    private let ioQueue = DispatchQueue(label: "yunduo.codex.bridge")

    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputBuffer = Data()
    private var lastReportedActivity: Bool?
    private var lastReportedApproval: Bool?
    private var logCursors: [String: LogCursor] = [:]
    private var pendingApprovalFirstSeen: [String: Date] = [:]

    init(
        onWeeklyRemaining: @escaping UsageHandler,
        onStatus: @escaping StatusHandler,
        onActivity: @escaping ActivityHandler,
        onApproval: @escaping ApprovalHandler,
        onCompletion: @escaping CompletionHandler
    ) {
        self.onWeeklyRemaining = onWeeklyRemaining
        self.onStatus = onStatus
        self.onActivity = onActivity
        self.onApproval = onApproval
        self.onCompletion = onCompletion
    }

    func start() {
        ioQueue.async { [weak self] in self?.launch() }
    }

    func stop() {
        ioQueue.async { [weak self] in
            self?.process?.terminate()
            self?.process = nil
            self?.inputHandle = nil
        }
    }

    func refreshUsage() {
        ioQueue.async { [weak self] in
            self?.send(method: "account/rateLimits/read", id: 2, params: NSNull())
        }
    }

    func refreshActivity() {
        ioQueue.async { [weak self] in
            self?.send(
                method: "thread/list",
                id: 3,
                params: [
                    "limit": 12,
                    "sortKey": "updated_at",
                    "sortDirection": "desc",
                    "archived": false,
                    "useStateDbOnly": true
                ]
            )
        }
    }

    private func launch() {
        guard process == nil else {
            refreshUsage()
            return
        }

        let codexPath = "/Applications/ChatGPT.app/Contents/Resources/codex"
        guard FileManager.default.isExecutableFile(atPath: codexPath) else {
            onStatus("未找到 Codex 本地接口")
            return
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()

        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        process.terminationHandler = { [weak self] task in
            guard task.terminationStatus != 0 else { return }
            self?.onStatus("Codex 连接已断开")
        }

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.ioQueue.async { self?.consume(data) }
        }
        error.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        do {
            try process.run()
            self.process = process
            self.inputHandle = input.fileHandleForWriting
            send(
                method: "initialize",
                id: 1,
                params: [
                    "clientInfo": [
                        "name": "suannai-floating-pet",
                        "title": "酸奶悬浮宠物",
                        "version": "0.1.0"
                    ],
                    "capabilities": NSNull()
                ]
            )
        } catch {
            onStatus("无法启动 Codex 接口")
        }
    }

    private func consume(_ data: Data) {
        outputBuffer.append(data)
        let newline = Data([0x0A])

        while let range = outputBuffer.range(of: newline) {
            let line = outputBuffer.subdata(in: outputBuffer.startIndex..<range.lowerBound)
            outputBuffer.removeSubrange(outputBuffer.startIndex...range.lowerBound)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
            else { continue }
            handle(object)
        }
    }

    private func handle(_ message: [String: Any]) {
        if let method = message["method"] as? String,
           Self.approvalRequestMethods.contains(method) {
            // Policy can resolve this request automatically without ever
            // presenting approval UI. Confirm the thread state first.
            refreshActivity()
            return
        }

        if (message["id"] as? Int) == 1 {
            sendNotification(method: "initialized")
            send(method: "account/rateLimits/read", id: 2, params: NSNull())
            refreshActivity()
            onStatus("已连接 Codex")
            return
        }

        if (message["id"] as? Int) == 2,
           let result = message["result"] as? [String: Any],
           let snapshot = result["rateLimits"] as? [String: Any] {
            updateUsage(from: snapshot)
            return
        }

        if message["method"] as? String == "account/rateLimits/updated",
           let params = message["params"] as? [String: Any],
           let snapshot = params["rateLimits"] as? [String: Any] {
            updateUsage(from: snapshot)
            return
        }

        if (message["id"] as? Int) == 3,
           let result = message["result"] as? [String: Any],
           let threads = result["data"] as? [[String: Any]] {
            let snapshot = detectActivity(in: threads)
            reportApproval(snapshot.waitingForApproval)
            reportActivity(snapshot.working)
            if let completedTaskName = snapshot.completedTaskName {
                onCompletion(completedTaskName)
            }
        }
    }

    private static let approvalRequestMethods: Set<String> = [
        "item/commandExecution/requestApproval",
        "item/fileChange/requestApproval",
        "item/permissions/requestApproval",
        "execCommandApproval",
        "applyPatchApproval"
    ]

    private func reportApproval(_ waiting: Bool) {
        guard lastReportedApproval != waiting else { return }
        lastReportedApproval = waiting
        onApproval(waiting)
    }

    private struct ActivitySnapshot {
        var working = false
        var waitingForApproval = false
        var completedTaskName: String?
    }

    private struct LogSignals {
        var latestTaskMarker: TaskMarker?
        var hasPendingApproval = false
    }

    private struct LogCursor {
        var offset: UInt64
        var partialLine = Data()
        var discardingLeadingPartialLine = false
        var latestTaskMarker: TaskMarker?
        var taskCompletionCount = 0
        var pendingApprovalCallIDs = Set<String>()

        var signals: LogSignals {
            LogSignals(
                latestTaskMarker: latestTaskMarker,
                hasPendingApproval: !pendingApprovalCallIDs.isEmpty
            )
        }
    }

    private struct LogUpdate {
        let signals: LogSignals
        let didCompleteTask: Bool
    }

    private func detectActivity(in threads: [[String: Any]]) -> ActivitySnapshot {
        var snapshot = ActivitySnapshot()

        snapshot.waitingForApproval = threads.contains { thread in
            guard let status = thread["status"] as? [String: Any],
                  status["type"] as? String == "active",
                  let flags = status["activeFlags"] as? [String]
            else { return false }
            return flags.contains("waitingOnApproval")
        }

        let now = Date()
        let paths = Array(threads.compactMap { $0["path"] as? String }.prefix(6))
        let monitoredPaths = Set(paths)
        logCursors = logCursors.filter { monitoredPaths.contains($0.key) }
        pendingApprovalFirstSeen = pendingApprovalFirstSeen.filter { monitoredPaths.contains($0.key) }

        for thread in threads.prefix(6) {
            guard let path = thread["path"] as? String else { continue }
            let threadIsActive = Self.isActiveThread(thread)
            let url = URL(fileURLWithPath: path)
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate,
                  now.timeIntervalSince(modified) < 15 * 60,
                  let update = incrementalLogSignals(in: url)
            else { continue }

            let signals = update.signals
            if signals.latestTaskMarker == .started { snapshot.working = true }
            if threadIsActive && signals.hasPendingApproval {
                let firstSeen = pendingApprovalFirstSeen[path] ?? now
                pendingApprovalFirstSeen[path] = firstSeen
                // A real user prompt persists. Automatically approved calls
                // normally resolve before a second snapshot reaches this age.
                if now.timeIntervalSince(firstSeen) >= 0.75 {
                    snapshot.waitingForApproval = true
                }
            } else {
                pendingApprovalFirstSeen.removeValue(forKey: path)
            }
            if update.didCompleteTask, snapshot.completedTaskName == nil {
                snapshot.completedTaskName = taskName(from: thread)
            }
        }
        return snapshot
    }

    private static func isActiveThread(_ thread: [String: Any]) -> Bool {
        guard let status = thread["status"] as? [String: Any] else { return false }
        return status["type"] as? String == "active"
    }

    private func taskName(from thread: [String: Any]) -> String {
        let candidates = [thread["name"] as? String, thread["preview"] as? String]
        for candidate in candidates {
            let compact = candidate?
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let compact, !compact.isEmpty {
                return compact
            }
        }
        return "Codex 任务"
    }

    private func reportActivity(_ active: Bool) {
        guard lastReportedActivity != active else { return }
        lastReportedActivity = active
        onActivity(active)
    }

    private enum TaskMarker {
        case started
        case completed
    }

    private func incrementalLogSignals(in url: URL) -> LogUpdate? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let end = (try? handle.seekToEnd()) ?? 0
        let path = url.path
        let maximumInitialBytes: UInt64 = 32 * 1_024 * 1_024
        var cursor: LogCursor

        let isIncrementalRead: Bool
        if let cached = logCursors[path], cached.offset <= end {
            cursor = cached
            isIncrementalRead = true
        } else {
            let start = end > maximumInitialBytes ? end - maximumInitialBytes : 0
            cursor = LogCursor(
                offset: start,
                discardingLeadingPartialLine: start > 0
            )
            isIncrementalRead = false
        }

        let completionCountBeforeRead = cursor.taskCompletionCount

        do {
            if cursor.offset < end {
                try handle.seek(toOffset: cursor.offset)
                if let appended = try handle.readToEnd(), !appended.isEmpty {
                    cursor.offset += UInt64(appended.count)
                    consumeLogBytes(appended, into: &cursor)
                }
            }
            logCursors[path] = cursor
            return LogUpdate(
                signals: cursor.signals,
                didCompleteTask: isIncrementalRead
                    && cursor.taskCompletionCount > completionCountBeforeRead
            )
        } catch {
            return nil
        }
    }

    private func consumeLogBytes(_ bytes: Data, into cursor: inout LogCursor) {
        var data = cursor.partialLine
        data.append(bytes)
        cursor.partialLine.removeAll(keepingCapacity: false)

        let newline = Data([0x0A])
        var lineStart = data.startIndex

        // An initial tail read may begin in the middle of a large JSONL record.
        if cursor.discardingLeadingPartialLine {
            guard let firstNewline = data.range(of: newline, in: lineStart..<data.endIndex) else {
                return
            }
            lineStart = firstNewline.upperBound
            cursor.discardingLeadingPartialLine = false
        }

        while let lineEnd = data.range(of: newline, in: lineStart..<data.endIndex) {
            if lineStart < lineEnd.lowerBound {
                processLogLine(data.subdata(in: lineStart..<lineEnd.lowerBound), into: &cursor)
            }
            lineStart = lineEnd.upperBound
        }

        if lineStart < data.endIndex {
            let remainder = data.subdata(in: lineStart..<data.endIndex)
            let maximumPartialLineBytes = 2 * 1_024 * 1_024
            if remainder.count <= maximumPartialLineBytes {
                cursor.partialLine = remainder
            } else {
                // Avoid retaining an unbounded tool-output record in memory.
                cursor.discardingLeadingPartialLine = true
            }
        }
    }

    private func processLogLine(_ line: Data, into cursor: inout LogCursor) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let recordType = object["type"] as? String,
              let payload = object["payload"] as? [String: Any]
        else { return }

        if recordType == "event_msg", let eventType = payload["type"] as? String {
            if eventType == "task_started" { cursor.latestTaskMarker = .started }
            if eventType == "task_complete" {
                cursor.latestTaskMarker = .completed
                cursor.taskCompletionCount += 1
                cursor.pendingApprovalCallIDs.removeAll()
            }
            return
        }

        guard recordType == "response_item",
              let itemType = payload["type"] as? String,
              let callID = payload["call_id"] as? String
        else { return }

        if itemType == "custom_tool_call",
           let input = payload["input"] as? String,
           input.contains("sandbox_permissions"),
           input.contains("require_escalated") {
            cursor.pendingApprovalCallIDs.insert(callID)
        } else if itemType == "custom_tool_call_output" {
            cursor.pendingApprovalCallIDs.remove(callID)
        }
    }

    private func updateUsage(from snapshot: [String: Any]) {
        let candidates = [snapshot["primary"], snapshot["secondary"]]
        for candidate in candidates {
            guard let window = candidate as? [String: Any],
                  let minutes = window["windowDurationMins"] as? NSNumber,
                  minutes.intValue == 10_080,
                  let used = window["usedPercent"] as? NSNumber
            else { continue }

            let remaining = min(max(1 - used.doubleValue / 100, 0), 1)
            onWeeklyRemaining(remaining)
            return
        }
        onStatus("未找到 7 天用量窗口")
    }

    private func send(method: String, id: Int, params: Any) {
        write(["method": method, "id": id, "params": params])
    }

    private func sendNotification(method: String) {
        write(["method": method])
    }

    private func write(_ object: [String: Any]) {
        guard let inputHandle,
              let data = try? JSONSerialization.data(withJSONObject: object)
        else { return }
        inputHandle.write(data)
        inputHandle.write(Data([0x0A]))
    }
}
