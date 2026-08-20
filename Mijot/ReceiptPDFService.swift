import Foundation
import PDFKit
import UIKit
import Vision

enum TicketImportError: LocalizedError {
    case unreadablePDF
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .unreadablePDF:
            "Le document PDF n’a pas pu être ouvert."
        case .noTextFound:
            "Aucun texte exploitable n’a été trouvé dans ce ticket."
        }
    }
}

struct ExtractedTicket {
    let text: String
    let pdfData: Data?
}

enum PDFTicketExtractor {
    static func extract(from url: URL) async throws -> ExtractedTicket {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
        }

        guard let document = PDFDocument(url: url) else {
            throw TicketImportError.unreadablePDF
        }

        // Gemini accepte les petits PDF directement et conserve alors leur mise en page.
        let rawPDF = try? Data(contentsOf: url)
        let inlinePDF = rawPDF.flatMap { $0.count < 12_000_000 ? $0 : nil }

        let embeddedText = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")

        if embeddedText.filter(\.isLetter).count > 40 {
            return ExtractedTicket(text: embeddedText, pdfData: inlinePDF)
        }

        var recognizedPages: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let image = page.thumbnail(of: CGSize(width: 1800, height: 2400), for: .mediaBox)
            guard let cgImage = image.cgImage else { continue }
            let text = try recognizeText(in: cgImage)
            recognizedPages.append(text)
        }

        let result = recognizedPages.joined(separator: "\n")
        guard result.filter(\.isLetter).count > 20 else {
            throw TicketImportError.noTextFound
        }
        return ExtractedTicket(text: result, pdfData: inlinePDF)
    }

    static func extractText(from url: URL) async throws -> String {
        try await extract(from: url).text
    }

    private static func recognizeText(in image: CGImage) throws -> String {
        var lines: [String] = []
        let request = VNRecognizeTextRequest { request, _ in
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            lines = observations.compactMap { $0.topCandidates(1).first?.string }
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["fr-FR"]
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return lines.joined(separator: "\n")
    }
}

enum ReceiptParser {
    private static let ignoredTerms = [
        "total", "sous total", "sous-total", "tva", "carte bancaire", "paiement",
        "montant", "rendu", "a payer", "à payer", "remise", "fidelite", "fidélité",
        "intermarche", "intermarché", "siret", "ticket", "merci", "date", "heure",
        "terminal", "autorisation", "visa", "mastercard", "cb ", "magasin"
    ]

    static func parse(_ text: String) -> [ReceiptLineDraft] {
        text.components(separatedBy: .newlines)
            .compactMap(parseLine)
    }

    static func parseLine(_ rawLine: String) -> ReceiptLineDraft? {
        var line = rawLine
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard line.count >= 4 else { return nil }
        let folded = line.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard !ignoredTerms.contains(where: { folded.contains($0.folding(options: .diacriticInsensitive, locale: .current)) }) else {
            return nil
        }

        line = line.replacingOccurrences(
            of: #"\s+-?\d+[,.]\d{2}\s*€?\s*$"#,
            with: "",
            options: .regularExpression
        )
        line = line.replacingOccurrences(
            of: #"^\s*\d{6,}\s+"#,
            with: "",
            options: .regularExpression
        )

        var quantity = 1.0
        var unit = InventoryUnit.piece
        var confidence = 0.62

        if let measurement = firstMatch(
            pattern: #"(\d+(?:[,.]\d+)?)\s*(kg|g|ml|cl|l)\b"#,
            in: line
        ), let parsed = Double(measurement.value.replacingOccurrences(of: ",", with: ".")) {
            switch measurement.unit.lowercased() {
            case "kg": quantity = parsed * 1_000; unit = .gram
            case "g": quantity = parsed; unit = .gram
            case "l": quantity = parsed * 1_000; unit = .milliliter
            case "cl": quantity = parsed * 10; unit = .milliliter
            default: quantity = parsed; unit = .milliliter
            }
            line.removeSubrange(measurement.range)
            confidence = 0.86
        } else if let count = firstCount(in: line) {
            quantity = count.value
            line.removeSubrange(count.range)
            confidence = 0.78
        }

        let name = cleanedProductName(line)
        guard name.filter(\.isLetter).count >= 3 else { return nil }

        return ReceiptLineDraft(
            name: name,
            quantity: max(0.01, quantity),
            unit: unit,
            confidence: confidence
        )
    }

    private static func cleanedProductName(_ input: String) -> String {
        input
            .replacingOccurrences(of: #"[*#|]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -.:"))
            .lowercased()
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private static func firstMatch(pattern: String, in text: String) -> (value: String, unit: String, range: Range<String.Index>)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              match.numberOfRanges >= 3,
              let fullRange = Range(match.range(at: 0), in: text),
              let valueRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text) else { return nil }
        return (String(text[valueRange]), String(text[unitRange]), fullRange)
    }

    private static func firstCount(in text: String) -> (value: Double, range: Range<String.Index>)? {
        guard let regex = try? NSRegularExpression(pattern: #"\b(\d{1,2})\s*[xX]\s*"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let fullRange = Range(match.range(at: 0), in: text),
              let valueRange = Range(match.range(at: 1), in: text),
              let value = Double(text[valueRange]) else { return nil }
        return (value, fullRange)
    }
}
