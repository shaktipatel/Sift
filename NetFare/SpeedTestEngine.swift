import Foundation
import Combine

struct SpeedTestProgress: Equatable {
    let phase: TestPhase
    let completedSteps: Int
    let totalSteps: Int
    let message: String
    let liveMbps: Double?
    let elapsedSeconds: Double
    let targetSeconds: Double

    var fraction: Double {
        guard totalSteps > 0 else { return 0 }
        return min(1, max(0, Double(completedSteps) / Double(totalSteps)))
    }

    var remainingSeconds: Int {
        max(0, Int(ceil(targetSeconds - elapsedSeconds)))
    }
}

@MainActor
final class SpeedTestEngine: ObservableObject {
    @Published private(set) var progress = SpeedTestProgress(
        phase: .preparing,
        completedSteps: 0,
        totalSteps: 1,
        message: "Ready when you are",
        liveMbps: nil,
        elapsedSeconds: 0,
        targetSeconds: 10
    )
    @Published private(set) var detectedProviderName: String?

    private let baseURL = URL(string: "https://speed.cloudflare.com")!
    private let testDuration: TimeInterval = 10
    private let latencyTrials = 2
    private let downloadTrials = 3
    private let uploadTrials = 2
    private var cancellationRequested = false
    private var activeSession: URLSession?
    private var progressStartedAt = Date()

    func cancel() {
        cancellationRequested = true
        activeSession?.invalidateAndCancel()
    }

    func run(
        profileID: UUID,
        initialPath: NetworkPathSnapshot,
        allowCellular: Bool,
        allowConstrained: Bool,
        currentPath: @escaping () -> NetworkPathSnapshot
    ) async -> SpeedTestRun {
        let startedAt = Date()
        progressStartedAt = startedAt
        detectedProviderName = nil
        cancellationRequested = false
        var dataUsed: Int64 = 0
        var latencies: [Double] = []
        var downloads: [Double] = []
        var uploads: [Double] = []
        var errors: [String] = []
        var interfaceStable = true
        let isMetered = initialPath.isExpensive || initialPath.interface == .cellular
        let dataBudget: Int64 = isMetered ? 5_000_000 : 25_000_000
        let deadline = startedAt.addingTimeInterval(testDuration)

        do {
            try checkForCancellation()
            try validatePath(initialPath, allowCellular: allowCellular, allowConstrained: allowConstrained)
            let session = makeSession(allowCellular: allowCellular, allowConstrained: allowConstrained)
            activeSession = session
            defer {
                session.invalidateAndCancel()
                if activeSession === session { activeSession = nil }
            }

            setProgress(.preparing, completed: 0, total: totalSteps, message: "Checking the test path")
            try checkBudget(used: dataUsed, expectedAdditional: 64_000, limit: dataBudget)
            let preflight = try await perform(
                session: session,
                request: makeRequest(path: "cdn-cgi/trace", query: [URLQueryItem(name: "nf", value: UUID().uuidString)], timeout: timeRemaining(deadline, maximum: 2)),
                expectedHost: baseURL.host!,
                maximumResponseBytes: 64_000
            )
            dataUsed += Int64(preflight.data.count)

            let providerTask = Task {
                await ProviderDetector.lookup(session: session, traceData: preflight.data, deadline: deadline)
            }

            setProgress(.latency, completed: 0, total: totalSteps, message: "Measuring latency")
            for index in 0..<latencyTrials {
                try checkForCancellation()
                if Date() >= deadline { break }
                try validateStablePath(initialPath, current: currentPath())
                try checkBudget(used: dataUsed, expectedAdditional: 64_000, limit: dataBudget)
                do {
                    let measured = try await perform(
                        session: session,
                        request: makeRequest(path: "cdn-cgi/trace", query: [URLQueryItem(name: "nf", value: "latency-\(index)-\(UUID().uuidString)")], timeout: timeRemaining(deadline, maximum: 1.5)),
                        expectedHost: baseURL.host!,
                        maximumResponseBytes: 64_000
                    )
                    dataUsed += Int64(measured.data.count)
                    latencies.append(measured.seconds * 1_000)
                } catch {
                    errors.append("Latency: \(error.localizedDescription)")
                }
                setProgress(.latency, completed: index + 1, total: totalSteps, message: "Measuring latency")
            }

            let downloadBytes = isMetered ? 750_000 : 4_000_000
            let uploadBytes = isMetered ? 250_000 : 1_000_000

            setProgress(.download, completed: latencyTrials, total: totalSteps, message: "Measuring download speed")
            for index in 0..<downloadTrials {
                try checkForCancellation()
                if Date() >= deadline { break }
                try validateStablePath(initialPath, current: currentPath())
                try checkBudget(used: dataUsed, expectedAdditional: Int64(downloadBytes), limit: dataBudget)
                do {
                    let measured = try await perform(
                        session: session,
                        request: makeRequest(path: "__down", query: [
                            URLQueryItem(name: "bytes", value: String(downloadBytes)),
                            URLQueryItem(name: "nf", value: "download-\(index)-\(UUID().uuidString)")
                        ], timeout: timeRemaining(deadline, maximum: 2.5)),
                        expectedHost: baseURL.host!,
                        maximumResponseBytes: downloadBytes
                    )
                    guard measured.data.count == downloadBytes else {
                        throw SpeedTestError.incompletePayload(expected: downloadBytes, actual: measured.data.count)
                    }
                    dataUsed += Int64(measured.data.count)
                    if let throughput = NetFareStatistics.throughputMbps(bytes: Int64(measured.data.count), seconds: measured.seconds) {
                        downloads.append(throughput)
                        setProgress(.download, completed: latencyTrials + index + 1, total: totalSteps, liveMbps: throughput, message: "Measuring download speed")
                    }
                } catch {
                    errors.append("Download: \(error.localizedDescription)")
                }
                setProgress(.download, completed: latencyTrials + index + 1, total: totalSteps, liveMbps: downloads.last, message: "Measuring download speed")
            }

            setProgress(.upload, completed: latencyTrials + downloadTrials, total: totalSteps, message: "Measuring upload speed")
            for index in 0..<uploadTrials {
                try checkForCancellation()
                if Date() >= deadline { break }
                try validateStablePath(initialPath, current: currentPath())
                do {
                    let payload = makePayload(byteCount: uploadBytes)
                    try checkBudget(used: dataUsed, expectedAdditional: Int64(payload.count + 64_000), limit: dataBudget)
                    let measured = try await perform(
                        session: session,
                        request: makeUploadRequest(query: [URLQueryItem(name: "nf", value: "upload-\(index)-\(UUID().uuidString)")], payloadSize: payload.count, timeout: timeRemaining(deadline, maximum: 2.5)),
                        body: payload,
                        expectedHost: baseURL.host!,
                        maximumResponseBytes: 64_000
                    )
                    dataUsed += Int64(payload.count + measured.data.count)
                    if let throughput = NetFareStatistics.throughputMbps(bytes: Int64(payload.count), seconds: measured.seconds) {
                        uploads.append(throughput)
                        setProgress(.upload, completed: latencyTrials + downloadTrials + index + 1, total: totalSteps, liveMbps: throughput, message: "Measuring upload speed")
                    }
                } catch {
                    errors.append("Upload: \(error.localizedDescription)")
                }
                setProgress(.upload, completed: latencyTrials + downloadTrials + index + 1, total: totalSteps, liveMbps: uploads.last, message: "Measuring upload speed")
            }

            guard downloads.count >= 2 else {
                throw SpeedTestError.insufficientDownloadSamples
            }

            let providerResult = await providerTask.value
            detectedProviderName = providerResult.name
            dataUsed += providerResult.bytes
            try await holdUntil(deadline)
            setProgress(.calculating, completed: totalSteps - 1, total: totalSteps, message: "Calculating a stable result")
            let run = NetFareScoring.makeRun(
                profileID: profileID,
                interface: initialPath.interface,
                status: .completed,
                failureReason: errors.isEmpty ? nil : errors.joined(separator: "\n"),
                latency: latencies,
                download: downloads,
                upload: uploads,
                dataUsedBytes: dataUsed,
                startedAt: startedAt,
                endedAt: Date(),
                interfaceStable: interfaceStable
            )
            setProgress(.finished, completed: totalSteps, total: totalSteps, liveMbps: downloads.last ?? uploads.last, message: "Test complete")
            return run
        } catch is CancellationError {
            setProgress(.finished, completed: 0, total: totalSteps, message: "Test cancelled")
            return NetFareScoring.makeRun(
                profileID: profileID,
                interface: initialPath.interface,
                status: .cancelled,
                failureReason: "The test was cancelled.",
                latency: latencies,
                download: downloads,
                upload: uploads,
                dataUsedBytes: dataUsed,
                startedAt: startedAt,
                endedAt: Date(),
                interfaceStable: interfaceStable
            )
        } catch {
            if cancellationRequested || Task.isCancelled {
                setProgress(.finished, completed: 0, total: totalSteps, message: "Test cancelled")
                return NetFareScoring.makeRun(
                    profileID: profileID,
                    interface: initialPath.interface,
                    status: .cancelled,
                    failureReason: "The test was cancelled.",
                    latency: latencies,
                    download: downloads,
                    upload: uploads,
                    dataUsedBytes: dataUsed,
                    startedAt: startedAt,
                    endedAt: Date(),
                    interfaceStable: interfaceStable
                )
            }
            if let speedError = error as? SpeedTestError, case .pathChanged = speedError {
                interfaceStable = false
            }
            setProgress(.finished, completed: 0, total: totalSteps, message: "Test incomplete")
            return NetFareScoring.makeRun(
                profileID: profileID,
                interface: initialPath.interface,
                status: downloads.isEmpty ? .failed : .incomplete,
                failureReason: error.localizedDescription,
                latency: latencies,
                download: downloads,
                upload: uploads,
                dataUsedBytes: dataUsed,
                startedAt: startedAt,
                endedAt: Date(),
                interfaceStable: interfaceStable
            )
        }
    }

    private var totalSteps: Int { latencyTrials + downloadTrials + uploadTrials }

    private func setProgress(_ phase: TestPhase, completed: Int, total: Int, liveMbps: Double? = nil, message: String) {
        let elapsed = min(testDuration, max(0, Date().timeIntervalSince(progressStartedAt)))
        progress = SpeedTestProgress(
            phase: phase,
            completedSteps: completed,
            totalSteps: total,
            message: message,
            liveMbps: liveMbps,
            elapsedSeconds: elapsed,
            targetSeconds: testDuration
        )
    }

    private func checkForCancellation() throws {
        try Task.checkCancellation()
        if cancellationRequested { throw CancellationError() }
    }

    private func checkBudget(used: Int64, expectedAdditional: Int64, limit: Int64) throws {
        guard expectedAdditional >= 0, used >= 0, used <= limit, expectedAdditional <= limit - used else {
            throw SpeedTestError.dataBudgetExceeded
        }
    }

    private func validatePath(_ path: NetworkPathSnapshot, allowCellular: Bool, allowConstrained: Bool) throws {
        guard path.isSatisfied else { throw SpeedTestError.offline }
        if path.isExpensive && !allowCellular { throw SpeedTestError.meteredNotAllowed }
        if path.isConstrained && !allowConstrained { throw SpeedTestError.constrainedNotAllowed }
    }

    private func validateStablePath(_ initial: NetworkPathSnapshot, current: NetworkPathSnapshot) throws {
        guard current.isSatisfied else { throw SpeedTestError.pathChanged }
        guard current.interface == initial.interface else { throw SpeedTestError.pathChanged }
        guard current.isExpensive == initial.isExpensive else { throw SpeedTestError.pathChanged }
    }

    private func holdUntil(_ deadline: Date) async throws {
        while deadline.timeIntervalSinceNow > 0 {
            try checkForCancellation()
            let remaining = min(0.1, deadline.timeIntervalSinceNow)
            try await Task.sleep(for: .seconds(remaining))
        }
    }

    private func timeRemaining(_ deadline: Date, maximum: TimeInterval) -> TimeInterval {
        max(0.2, min(maximum, deadline.timeIntervalSinceNow))
    }

    private func makeSession(allowCellular: Bool, allowConstrained: Bool) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.allowsExpensiveNetworkAccess = allowCellular
        configuration.allowsConstrainedNetworkAccess = allowConstrained
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 4
        configuration.httpAdditionalHeaders = [
            "Cache-Control": "no-cache",
            "Accept-Encoding": "identity",
            "User-Agent": "NetFare/1.0"
        ]
        return URLSession(configuration: configuration)
    }

    private func makeRequest(path: String, query: [URLQueryItem], timeout: TimeInterval = 2.5) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        return request
    }

    private func makeUploadRequest(query: [URLQueryItem], payloadSize: Int, timeout: TimeInterval = 2.5) -> URLRequest {
        var request = makeRequest(path: "__up", query: query, timeout: timeout)
        request.httpMethod = "POST"
        request.setValue(String(payloadSize), forHTTPHeaderField: "Content-Length")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func makePayload(byteCount: Int) -> Data {
        var payload = Data(count: byteCount)
        payload.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            let pointer = base.assumingMemoryBound(to: UInt8.self)
            for index in 0..<byteCount {
                pointer[index] = UInt8(truncatingIfNeeded: (index &* 31) &+ (index >> 3) &+ 17)
            }
        }
        return payload
    }

    private func perform(
        session: URLSession,
        request: URLRequest,
        body: Data? = nil,
        expectedHost: String,
        maximumResponseBytes: Int
    ) async throws -> (data: Data, response: HTTPURLResponse, seconds: Double) {
        try checkForCancellation()
        let start = ContinuousClock.now
        let result: (Data, URLResponse)
        if let body {
            result = try await session.upload(for: request, from: body)
        } else {
            result = try await session.data(for: request)
        }
        let elapsed = start.duration(to: .now).secondsDouble
        guard let response = result.1 as? HTTPURLResponse else { throw SpeedTestError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw SpeedTestError.httpStatus(response.statusCode) }
        guard response.url?.host == expectedHost else { throw SpeedTestError.captivePortal }
        guard result.0.count <= maximumResponseBytes else { throw SpeedTestError.payloadTooLarge }
        guard elapsed.isFinite, elapsed > 0 else { throw SpeedTestError.invalidDuration }
        return (result.0, response, elapsed)
    }
}

private enum SpeedTestError: LocalizedError {
    case offline
    case meteredNotAllowed
    case constrainedNotAllowed
    case pathChanged
    case dataBudgetExceeded
    case payloadTooLarge
    case incompletePayload(expected: Int, actual: Int)
    case insufficientDownloadSamples
    case invalidResponse
    case invalidDuration
    case captivePortal
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .offline: "No network connection is available."
        case .meteredNotAllowed: "This connection is metered. Enable cellular testing to continue."
        case .constrainedNotAllowed: "Low Data Mode is enabled. Enable constrained-network testing to continue."
        case .pathChanged: "The network path changed during the test."
        case .dataBudgetExceeded: "The test reached its data budget before enough valid samples were collected."
        case .payloadTooLarge: "The test endpoint returned more data than the safety limit."
        case .incompletePayload(let expected, let actual): "The download was incomplete (received \(actual) of \(expected) bytes)."
        case .insufficientDownloadSamples: "The test could not collect enough valid download samples."
        case .invalidResponse: "The test endpoint returned an invalid response."
        case .invalidDuration: "The test duration was invalid."
        case .captivePortal: "The connection redirected to a sign-in or captive portal."
        case .httpStatus(let status): "The test endpoint returned HTTP \(status)."
        }
    }
}

private extension Duration {
    var secondsDouble: Double {
        let value = components
        return Double(value.seconds) + Double(value.attoseconds) / 1_000_000_000_000_000_000
    }
}
