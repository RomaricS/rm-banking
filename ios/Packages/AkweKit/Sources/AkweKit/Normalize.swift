import Foundation

/// Merchant keys for rules. MUST stay identical to backend/supabase/functions/_shared/normalize.ts
/// (the app creates rules, the server applies them).
public enum MerchantNormalizer {
    private static let prefixes: [NSRegularExpression] = [
        #"^achat\s+cb\s+"#, #"^paiement\s+(par\s+)?carte\s+"#, #"^paiement\s+cb\s+"#, #"^cb\s*\*?\s*"#, #"^carte\s+(x?\d{4}\s+)?"#,
        #"^prlv\s+(sepa\s+)?"#, #"^prelevement\s+(sepa\s+)?"#, #"^vir(ement)?\s+(sepa\s+)?(inst(antane)?\s+)?(recu\s+|emis\s+)?"#,
        #"^retrait\s+(dab\s+)?"#, #"^facture\s+carte\s+"#,
        #"^card\s+payment\s+(to\s+)?"#, #"^kartenzahlung\s+"#, #"^lastschrift\s+"#, #"^ueberweisung\s+|^überweisung\s+"#,
        #"^sq\s*\*\s*"#, #"^tst\s*\*\s*"#, #"^sp\s*\*?\s+"#, #"^paypal\s*\*\s*"#, #"^pp\s*\*\s*"#, #"^dd\s*\*?\s*(doordash\s*)?"#,
        #"^pos\s+(purchase\s+)?"#, #"^debit\s+card\s+purchase\s+"#, #"^idp\s+purchase\s*-?\s*"#, #"^interac\s+(purchase\s*-?\s*)?"#,
        #"^purchase\s+"#, #"^recurring\s+payment\s+"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    private static let noise: [NSRegularExpression] = [
        #"\b\d{2}[/.-]\d{2}([/.-]\d{2,4})?\b"#,
        #"\bcarte\s+x?\d{4}\b"#,
        #"\bx{2,}\d{2,4}\b"#,
        #"#\s?\d+"#,
        #"\b\d{3,}\b"#,
        #"\b(fr|us|ca|gb|de)\b$"#,
        #"\*+"#,
        #"[^\p{L}\p{N}&' ]+"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    private static func replace(_ re: NSRegularExpression, in s: String, with r: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: r)
    }

    private static func collapse(_ s: String) -> String {
        s.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).joined(separator: " ")
    }

    public static func strip(_ raw: String) -> String {
        var s = collapse(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        for _ in 0..<3 {
            let before = s
            for p in prefixes { s = replace(p, in: s, with: "") }
            if s == before { break }
        }
        for n in noise { s = replace(n, in: s, with: " ") }
        return collapse(s).trimmingCharacters(in: .whitespaces)
    }

    public static func key(_ nameOrLabel: String) -> String {
        let s = strip(nameOrLabel)
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        let stop: Set<String> = ["the", "inc", "llc", "ltd", "sa", "sas", "sarl"]
        let words = s.split(separator: " ").map(String.init).filter { $0.count > 1 && !stop.contains($0) }
        let joined = words.prefix(3).joined(separator: " ")
        return joined.isEmpty ? s : joined
    }
}
