import Foundation

enum ProviderDetector {
    struct Result: Sendable {
        let name: String?
        let bytes: Int64
    }

    static func lookup(session: URLSession, traceData: Data, deadline: Date) async -> Result {
        guard let ipAddress = ipAddress(from: traceData),
              let encodedIP = ipAddress.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://ipwho.is/\(encodedIP)?fields=success,connection") else {
            return Result(name: nil, bytes: 0)
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = max(0.2, min(1.2, deadline.timeIntervalSinceNow))
        request.setValue("NetFare/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  data.count <= 32_000 else {
                return Result(name: nil, bytes: Int64(data.count))
            }
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard object?["success"] as? Bool != false,
                  let connection = object?["connection"] as? [String: Any] else {
                return Result(name: nil, bytes: Int64(data.count))
            }
            let candidate = [connection["isp"] as? String, connection["org"] as? String]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty })
            let provider = candidate.map { ProviderCatalog.match($0)?.name ?? $0 }
            return Result(name: sanitized(provider), bytes: Int64(data.count))
        } catch {
            return Result(name: nil, bytes: 0)
        }
    }

    private static func ipAddress(from data: Data) -> String? {
        guard let trace = String(data: data, encoding: .utf8) else { return nil }
        for line in trace.split(whereSeparator: { $0.isNewline }) {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2, parts[0].lowercased() == "ip" {
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty, value.count <= 64 { return value }
            }
        }
        return nil
    }

    private static func sanitized(_ value: String?) -> String? {
        guard let value else { return nil }
        let collapsed = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !collapsed.isEmpty, collapsed.count <= 80 else { return nil }
        return collapsed
    }
}
