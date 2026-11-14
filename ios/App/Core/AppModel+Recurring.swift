import SwiftUI
import AkweKit

/// Bills & subscriptions: classification, manual entries, and keeping stream categories in step
/// with what the user does on transactions (re-categorising, creating rules).
extension AppModel {

    // MARK: Reading

    /// Visible streams going out (detected or manual), with their next due date rolled forward.
    func upcomingRecurring(today: Day = .today()) -> [RecurringStream] {
        recurring.compactMap { r -> RecurringStream? in
            guard r.isLive, r.isOutflow else { return nil }
            var r = r
            r.predictedNextDate = r.nextDue(onOrAfter: today)
            return r
        }
        .sorted { ($0.predictedNextDate ?? today) < ($1.predictedNextDate ?? today) }
    }

    /// User's choice wins; otherwise: subscription-type categories, or a small monthly charge.
    func isSubscription(_ r: RecurringStream) -> Bool {
        if let kind = r.kind { return kind == "subscription" }
        let key = ledger.category(r.categoryId)?.key ?? ""
        if ["subscriptions", "internet_phone", "fitness", "entertainment"].contains(key) { return true }
        if ["rent", "utilities", "insurance", "loan", "mortgage"].contains(key) { return false }
        return r.frequency.uppercased() == "MONTHLY" && r.averageAmount < 100
    }

    func monthlyTotal(_ streams: [RecurringStream]) -> Decimal {
        streams.reduce(Decimal(0)) { $0 + rates.convert($1.monthlyAmount, from: $1.currency, to: currency) }
    }

    /// The stream a transaction belongs to (same merchant, same account when the stream has one).
    func stream(for tx: Transaction) -> RecurringStream? {
        let txKeys: Set<String> = [MerchantNormalizer.key(tx.title), MerchantNormalizer.key(tx.rawName)]
        return recurring.first { r in
            (r.accountId == nil || r.accountId == tx.accountId) &&
            !txKeys.isDisjoint(with: [MerchantNormalizer.key(r.title), MerchantNormalizer.key(r.description)])
        }
    }

    // MARK: Editing

    /// Creates a manual entry or saves edits. Detected streams only accept preference fields
    /// (name, category, kind, hidden); the bank sync owns their amounts and dates.
    func saveRecurring(_ r: RecurringStream) async {
        var r = r
        if r.categoryId != nil { r.categoryLocked = true }
        let isNew = !recurring.contains { $0.id == r.id }
        withAnimation(Motion.smooth) {
            if let i = recurring.firstIndex(where: { $0.id == r.id }) { recurring[i] = r } else { recurring.append(r) }
        }
        writeWidgetSnapshot()
        guard let backend, let uid = userId else { return }

        struct Manual: Encodable {
            let id: UUID; let userId: UUID; let accountId: UUID?; let source = "manual"; let direction = "outflow"
            let description: String; let merchantName: String; let frequency: String
            let averageAmount: Decimal; let lastAmount: Decimal; let currency: String
            let predictedNextDate: Day?; let isActive = true
            let categoryId: UUID?; let categoryLocked: Bool; let kind: String?; let hidden: Bool
        }
        struct ManualEdit: Encodable {
            let accountId: UUID?; let description: String; let merchantName: String; let frequency: String
            let averageAmount: Decimal; let lastAmount: Decimal; let currency: String; let predictedNextDate: Day?
            let categoryId: UUID?; let categoryLocked: Bool; let kind: String?; let hidden: Bool
        }
        struct Prefs: Encodable { let merchantName: String?; let categoryId: UUID?; let categoryLocked: Bool; let kind: String?; let hidden: Bool }
        do {
            if r.isManual {
                let row = Manual(id: r.id, userId: uid, accountId: r.accountId, description: r.description, merchantName: r.title,
                                 frequency: r.frequency, averageAmount: r.averageAmount, lastAmount: r.lastAmount, currency: r.currency,
                                 predictedNextDate: r.predictedNextDate, categoryId: r.categoryId, categoryLocked: r.categoryLocked ?? false,
                                 kind: r.kind, hidden: r.isHidden)
                if isNew {
                    try await backend.insert("recurring_streams", row)
                } else {
                    // Updates may only touch user-editable columns (no id / user_id / source).
                    try await backend.update("recurring_streams", id: r.id, ManualEdit(
                        accountId: row.accountId, description: row.description, merchantName: row.merchantName, frequency: row.frequency,
                        averageAmount: row.averageAmount, lastAmount: row.lastAmount, currency: row.currency, predictedNextDate: row.predictedNextDate,
                        categoryId: row.categoryId, categoryLocked: row.categoryLocked, kind: row.kind, hidden: row.hidden))
                }
            } else {
                try await backend.update("recurring_streams", id: r.id,
                                         Prefs(merchantName: r.merchantName, categoryId: r.categoryId, categoryLocked: r.categoryLocked ?? false, kind: r.kind, hidden: r.isHidden))
            }
        } catch { show(error) }
    }

    func deleteRecurring(_ r: RecurringStream) async {
        guard r.isManual else { var h = r; h.hidden = true; await saveRecurring(h); return }
        withAnimation(Motion.smooth) { recurring.removeAll { $0.id == r.id } }
        writeWidgetSnapshot()
        do { try await backend?.delete("recurring_streams", id: r.id) } catch { show(error) }
    }

    // MARK: Following transaction categories

    /// Called after the user re-categorises a transaction: the stream it belongs to follows.
    func syncStreamCategory(from tx: Transaction, to categoryId: UUID) async {
        guard let s = stream(for: tx), s.categoryId != categoryId else { return }
        var r = s
        r.categoryId = categoryId
        await saveRecurring(r)
    }

    /// Called after a rule is created: streams for that merchant take its category (unless the user locked one).
    func applyRuleToStreams(merchantKey: String, categoryId: UUID) async {
        let matching = recurring.filter { r in
            !(r.categoryLocked ?? false) && r.categoryId != categoryId &&
            (MerchantNormalizer.key(r.title) == merchantKey || MerchantNormalizer.key(r.description) == merchantKey)
        }
        for s in matching {
            var r = s
            r.categoryId = categoryId
            await saveRecurring(r)
        }
    }
}
