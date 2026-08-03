import Foundation
import ImageIO
import Vision

struct BillScanDraft: Sendable {
    var providerName: String = ""
    var totalCents: Int?
    var basePriceCents: Int?
    var equipmentFeeCents: Int?
    var promotionalText: String?
    var rawText: String = ""
    var confidence: Double = 0
}

enum BillScannerError: LocalizedError, Sendable {
    case invalidImage
    case noText

    var errorDescription: String? {
        switch self {
        case .invalidImage: "The image could not be read."
        case .noText: "No readable text was found. Try a flatter, brighter photo."
        }
    }
}

enum BillScanner {
    static func scan(data: Data) async throws -> BillScanDraft {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw BillScannerError.invalidImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.01
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let lines = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
        guard !lines.isEmpty else { throw BillScannerError.noText }
        return parse(lines: lines)
    }

    private static func parse(lines: [String]) -> BillScanDraft {
        let normalizedLines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let rawText = normalizedLines.joined(separator: "\n")
        let amountValues = normalizedLines.flatMap { amounts(in: [$0]) }
        let total = labeledAmount(in: normalizedLines, labels: ["amount due", "total due", "balance due", "total"])
            ?? amountValues.max()
        let base = labeledAmount(in: normalizedLines, labels: ["internet", "service", "monthly service", "plan"])
        let equipment = labeledAmount(in: normalizedLines, labels: ["equipment", "modem", "router", "gateway"])
        let provider = normalizedLines.first(where: { line in
            let lower = line.lowercased()
            return lower.contains("xfinity") || lower.contains("spectrum") || lower.contains("verizon") || lower.contains("at&t") || lower.contains("cox") || lower.contains("frontier") || lower.contains("google fiber")
        }) ?? ""
        let promo = normalizedLines.first(where: { $0.lowercased().contains("promo") || $0.lowercased().contains("promotion") || $0.lowercased().contains("discount") })
        let confidence = amountValues.isEmpty ? 0.2 : min(0.95, 0.35 + Double(amountValues.count) * 0.08)
        return BillScanDraft(providerName: provider, totalCents: total, basePriceCents: base, equipmentFeeCents: equipment, promotionalText: promo, rawText: rawText, confidence: confidence)
    }

    private static func labeledAmount(in lines: [String], labels: [String]) -> Int? {
        for line in lines {
            let lower = line.lowercased()
            guard labels.contains(where: { lower.contains($0) }) else { continue }
            if let amount = amounts(in: [line]).last { return amount }
        }
        return nil
    }

    private static func amounts(in lines: [String]) -> [Int] {
        let pattern = #"(?<!\d)\$?\s*\d{1,4}(?:,\d{3})*(?:\.\d{2})(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return lines.flatMap { line in
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            return regex.matches(in: line, range: range).compactMap { match -> Int? in
                guard let swiftRange = Range(match.range, in: line) else { return nil }
                let raw = line[swiftRange].replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
                guard let decimal = Double(raw), decimal.isFinite, decimal >= 0, decimal <= Double(Int.max) / 100 else { return nil }
                return Int((decimal * 100).rounded())
            }
        }
    }
}
