import Foundation
import SwiftUI
import WidgetKit
import Supabase
import AkweKit

/// Single source of truth for the app. Views read from it and call its intent methods.
@Observable
@MainActor
final class AppModel {
    enum Phase: Equatable { case launching, signedOut, onboarding, ready }

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let icon: String
        let text: String
        var tint: Color = Palette.positive
    }

    // MARK: State
    var phase: Phase = .launching
    var isLocked = false
    var isSyncing = false
    var toast: Toast?
    var lastError: String?

    var userId: UUID?
    var profile: Profile?
    var schedule = PaySchedule(frequency: .monthly, anchorDate: Day(Day.today().year, Day.today().month, 1))
    var prefs = NotificationPrefs()
    var items: [BankItem] = []
    var accounts: [Account] = []
    var pockets: [Pocket] = []
    var categories: [TxCategory] = []
    var transactions: [Transaction] = []
    var rules: [Rule] = []
    var budgets: [Budget] = []
    var recurring: [RecurringStream] = []
    var goals: [Goal] = []
    var members: [GoalMember] = []
    var ownFunding: [GoalFundingSettings] = []
    var events: [GoalEvent] = []
    var rates = RateBook()

    /// How many times the user moved a merchant to a category (rule suggestion after 2).
    private(set) var recategorizations: [String: (category: UUID, count: Int)] = [:]
    /// Pending deep link (goal invite code) to handle after sign-in.
    var pendingInviteCode: String?

    // MARK: Device settings (App Group defaults so widgets can read them)
    private let defaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    var hideBalances: Bool { didSet { defaults.set(hideBalances, forKey: "hideBalances"); writeWidgetSnapshot() } }
    var faceIDEnabled: Bool { didSet { defaults.set(faceIDEnabled, forKey: "faceID") } }
    var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }

    let backend: Backend?
    var isDemo: Bool { backend == nil }

    init() {
        hideBalances = defaults.bool(forKey: "hideBalances")
        faceIDEnabled = defaults.object(forKey: "faceID") as? Bool ?? true
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "system") ?? .system
        if let url = AppConfig.supabaseURL, !AppConfig.isDemo {
            backend = Backend(url: url, key: AppConfig.supabaseKey)
        } else {
            backend = nil
        }
    }

    // MARK: Derived
    var currency: String { profile?.displayCurrency ?? "USD" }

    var ledger: Ledger {
        Ledger(accounts: accounts, transactions: transactions, categories: categories.filter { !$0.archived }, pockets: pockets,
               budgets: budgets, recurring: recurring, goals: goals.filter { $0.archivedAt == nil }, members: members,
               rates: rates, currency: currency, schedule: schedule)
    }

    var colorScheme: ColorScheme? {
        switch appearance { case .light: .light; case .dark: .dark; case .system: nil }
    }

    func item(for account: Account) -> BankItem? { items.first { $0.id == account.itemId } }
    func accountColor(_ a: Account) -> Color { Color(hexString: a.color ?? (a.isCredit ? "#FFB86B" : "#A99FFF")) }
    var itemsNeedingAttention: [BankItem] { items.filter { $0.status.needsAttention } }
    var spendingCategories: [TxCategory] {
        let incomePockets = Set(pockets.filter(\.isIncome).map(\.id))
        return categories.filter { !$0.archived && !incomePockets.contains($0.pocketId) }
    }

    // MARK: Lifecycle

    func start() async {
        if isDemo {
            applyDemo()
            phase = .ready
            return
        }
        loadCache()
        guard let backend, let uid = await backend.currentUserId() else {
            phase = .signedOut
            return
        }
        userId = uid
        if profile != nil { phase = profile?.onboardedAt == nil ? .onboarding : .ready }
        await load()
        phase = profile?.onboardedAt == nil ? .onboarding : .ready
        isLocked = faceIDEnabled
    }

    func applyDemo() {
        let d = DemoData.make()
        userId = DemoData.userId
        profile = d.profile; schedule = d.schedule; items = d.items; accounts = d.accounts
        pockets = d.pockets; categories = d.categories; transactions = d.transactions; recurring = d.recurring
        budgets = d.budgets; goals = d.goals; members = d.members; events = d.events; rates = RateBook(rates: d.rates)
        ownFunding = d.members.filter { $0.userId == DemoData.userId }.map {
            GoalFundingSettings(goalId: $0.goalId, userId: $0.userId, funding: $0.funding, accountId: nil, earmarkAmount: $0.currentAmount, currentAmount: $0.currentAmount ?? 0)
        }
        writeWidgetSnapshot()
    }

    func signIn(idToken: String, nonce: String) async {
        guard let backend else { phase = .onboarding; return }
        do {
            try await backend.signInWithApple(idToken: idToken, nonce: nonce)
            userId = await backend.currentUserId()
            await load()
            phase = profile?.onboardedAt == nil ? .onboarding : .ready
        } catch {
            show(error)
        }
    }

    func signOut() async {
        await backend?.signOut()
        clearCache()
        userId = nil; profile = nil; items = []; accounts = []; transactions = []; goals = []; members = []
        phase = .signedOut
    }

    /// Loads everything from Supabase (RLS scopes it to the user).
    func load() async {
        guard let backend, let uid = userId else { return }
        let since = Day.today().adding(days: -730)
        do {
            async let p = backend.profile(uid)
            async let s = backend.paySchedule()
            async let pr = backend.prefs()
            async let it: [BankItem] = backend.fetch("bank_items", order: "created_at")
            async let ac: [Account] = backend.fetch("accounts", order: "sort")
            async let po: [Pocket] = backend.fetch("pockets", order: "sort")
            async let ca: [TxCategory] = backend.fetch("categories", order: "sort")
            async let tx = backend.transactions(since: since)
            async let ru: [Rule] = backend.fetch("rules")
            async let bu: [Budget] = backend.fetch("budgets")
            async let re: [RecurringStream] = backend.fetch("recurring_streams")
            async let go: [Goal] = backend.fetch("goals", order: "created_at")
            async let me: [GoalMember] = backend.fetch("goal_member_progress")
            async let fu: [GoalFundingSettings] = backend.fetch("goal_members")
            async let ev: [GoalEvent] = backend.fetch("goal_events", order: "created_at", ascending: false, limit: 200)
            async let fx = backend.fxRates(since: since)

            profile = try await p
            if let sched = try await s { schedule = sched }
            prefs = (try? await pr) ?? NotificationPrefs()
            items = try await it; accounts = try await ac; pockets = try await po; categories = try await ca
            transactions = try await tx; rules = try await ru; budgets = try await bu; recurring = try await re
            goals = try await go; members = try await me
            ownFunding = (try await fu).filter { $0.userId == uid }
            events = try await ev
            rates = RateBook(rates: try await fx)
            lastError = nil
            saveCache()
            writeWidgetSnapshot()
        } catch {
            show(error)
        }
    }

    /// Pull-to-refresh: asks the server to sync every bank, then reloads.
    func sync(itemId: UUID? = nil) async {
        guard !isSyncing else { return }
        guard let backend else {
            isSyncing = true
            try? await Task.sleep(for: .milliseconds(900))
            isSyncing = false
            showToast("checkmark.circle.fill", tr("toast.synced"))
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        do {
            var body: [String: AnyJSON] = [:]
            if let itemId { body["itemId"] = .string(itemId.uuidString) }
            try await backend.invokeVoid("plaid-sync", body)
            await load()
            showToast("checkmark.circle.fill", tr("toast.synced"))
        } catch {
            show(error)
        }
    }

    // MARK: Banks

    func linkToken(repairing itemId: UUID? = nil) async throws -> String {
        guard let backend else { throw AppError.demo }
        struct R: Decodable { let linkToken: String }
        var body: [String: AnyJSON] = ["locale": .string(Locale.current.identifier)]
        if let itemId { body["itemId"] = .string(itemId.uuidString) }
        let r: R = try await backend.invoke("plaid-link-token", body)
        return r.linkToken
    }

    func exchange(publicToken: String, institutionId: String?, institutionName: String?) async {
        guard let backend else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            var inst: [String: AnyJSON] = [:]
            if let institutionId { inst["id"] = .string(institutionId) }
            if let institutionName { inst["name"] = .string(institutionName) }
            try await backend.invokeVoid("plaid-exchange", ["publicToken": .string(publicToken), "institution": .object(inst)])
            await load()
            Haptics.success()
        } catch {
            show(error)
        }
    }

    func removeItem(_ item: BankItem) async {
        items.removeAll { $0.id == item.id }
        let gone = Set(accounts.filter { $0.itemId == item.id }.map(\.id))
        accounts.removeAll { gone.contains($0.id) }
        transactions.removeAll { gone.contains($0.accountId) }
        guard let backend else { return }
        do { try await backend.invokeVoid("plaid-remove-item", ["itemId": .string(item.id.uuidString)]) } catch { show(error) }
    }

    func updateAccount(_ account: Account) async {
        guard let i = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[i] = account
        writeWidgetSnapshot()
        struct U: Encodable { let nickname: String?; let includeInTotals: Bool; let color: String?; let cardKind: CardKind? }
        do { try await backend?.update("accounts", id: account.id, U(nickname: account.nickname, includeInTotals: account.includeInTotals, color: account.color, cardKind: account.cardKind)) } catch { show(error) }
    }

    // MARK: Onboarding

    func savePaySchedule(_ s: PaySchedule) async {
        var s = s
        s.detected = false
        if s.incomeSource == nil { s.incomeSource = "manual" }
        schedule = s
        guard let backend, let uid = userId else { return }
        struct U: Encodable { let userId: UUID; let frequency: PayFrequency; let anchorDate: Day; let semimonthlyDays: [Int]; let incomeSource: String?; let detected: Bool }
        do { try await backend.upsert("pay_schedules", U(userId: uid, frequency: s.frequency, anchorDate: s.anchorDate, semimonthlyDays: s.semimonthlyDays, incomeSource: s.incomeSource, detected: false), onConflict: "user_id") } catch { show(error) }
    }

    func completeOnboarding() async {
        profile?.onboardedAt = Date()
        withAnimation(Motion.smooth) { phase = .ready }
        guard let backend, let uid = userId else { return }
        struct U: Encodable { let onboardedAt: Date }
        do { try await backend.update("profiles", id: uid, U(onboardedAt: Date())) } catch { show(error) }
    }

    // MARK: Transactions

    /// Recategorize. Returns a merchant key if a rule should be suggested ("you moved it twice").
    @discardableResult
    func setCategory(_ tx: Transaction, to categoryId: UUID) async -> String? {
        guard let i = transactions.firstIndex(where: { $0.id == tx.id }) else { return nil }
        transactions[i].categoryId = categoryId
        transactions[i].categorySource = .user
        transactions[i].needsReview = false
        writeWidgetSnapshot()
        struct U: Encodable { let categoryId: UUID; let categorySource: String; let needsReview: Bool }
        do { try await backend?.update("transactions", id: tx.id, U(categoryId: categoryId, categorySource: "user", needsReview: false)) } catch { show(error) }

        let key = MerchantNormalizer.key(tx.title)
        guard !rules.contains(where: { $0.merchantKey == key }) else { return nil }
        let prev = recategorizations[key]
        let count = prev?.category == categoryId ? (prev!.count + 1) : 1
        recategorizations[key] = (categoryId, count)
        let samePastCount = transactions.filter { MerchantNormalizer.key($0.title) == key && $0.categoryId == categoryId && $0.categorySource == .user }.count
        return (count >= 2 || samePastCount >= 2) ? key : nil
    }

    func confirmReview(_ tx: Transaction) async {
        guard let i = transactions.firstIndex(where: { $0.id == tx.id }) else { return }
        transactions[i].needsReview = false
        struct U: Encodable { let needsReview: Bool }
        do { try await backend?.update("transactions", id: tx.id, U(needsReview: false)) } catch { show(error) }
    }

    func setExcluded(_ tx: Transaction, _ excluded: Bool) async {
        guard let i = transactions.firstIndex(where: { $0.id == tx.id }) else { return }
        transactions[i].excluded = excluded
        writeWidgetSnapshot()
        struct U: Encodable { let excluded: Bool }
        do { try await backend?.update("transactions", id: tx.id, U(excluded: excluded)) } catch { show(error) }
    }

    func setNote(_ tx: Transaction, _ note: String) async {
        guard let i = transactions.firstIndex(where: { $0.id == tx.id }) else { return }
        transactions[i].note = note.isEmpty ? nil : note
        struct U: Encodable { let note: String? }
        do { try await backend?.update("transactions", id: tx.id, U(note: note.isEmpty ? nil : note)) } catch { show(error) }
    }

    func rename(_ tx: Transaction, to name: String) async {
        guard let i = transactions.firstIndex(where: { $0.id == tx.id }) else { return }
        transactions[i].merchantName = name
        struct U: Encodable { let merchantName: String }
        do { try await backend?.update("transactions", id: tx.id, U(merchantName: name)) } catch { show(error) }
    }

    /// Creates "always put <merchant> in <category>" and applies it to past transactions. Returns how many changed.
    @discardableResult
    func createRule(merchantKey: String, categoryId: UUID) async -> Int {
        let rule = Rule(merchantKey: merchantKey, categoryId: categoryId)
        rules.append(rule)
        recategorizations[merchantKey] = nil
        var changed: [UUID] = []
        for i in transactions.indices where MerchantNormalizer.key(transactions[i].title) == merchantKey && transactions[i].categorySource != .user {
            transactions[i].categoryId = categoryId
            transactions[i].categorySource = .rule
            transactions[i].needsReview = false
            changed.append(transactions[i].id)
        }
        writeWidgetSnapshot()
        guard let backend, let uid = userId else { return changed.count }
        struct R: Encodable { let id: UUID; let userId: UUID; let merchantKey: String; let categoryId: UUID }
        struct U: Encodable { let categoryId: UUID; let categorySource: String; let needsReview: Bool }
        do {
            try await backend.insert("rules", R(id: rule.id, userId: uid, merchantKey: merchantKey, categoryId: categoryId))
            for chunk in stride(from: 0, to: changed.count, by: 200) {
                let ids = changed[chunk..<min(chunk + 200, changed.count)].map(\.uuidString)
                try await backend.client.from("transactions").update(U(categoryId: categoryId, categorySource: "rule", needsReview: false)).in("id", values: ids).execute()
            }
        } catch { show(error) }
        return changed.count
    }

    /// Splits a transaction into parts (category, amount). Parts must add up to the original amount.
    func split(_ tx: Transaction, parts: [(UUID, Decimal)]) async {
        let children = parts.map { cat, amount in
            Transaction(accountId: tx.accountId, amount: -amount.abs, currency: tx.currency, date: tx.date, rawName: tx.rawName, merchantName: tx.merchantName, paymentMethod: tx.paymentMethod, kind: tx.kind, categoryId: cat, categorySource: .user, splitParentId: tx.id)
        }
        transactions.append(contentsOf: children)
        guard let backend, let uid = userId else { return }
        struct S: Encodable { let id: UUID; let userId: UUID; let accountId: UUID; let amount: Decimal; let currency: String; let date: Day; let rawName: String; let merchantName: String?; let paymentMethod: String; let kind: String; let categoryId: UUID?; let categorySource: String; let splitParentId: UUID }
        do {
            try await backend.insert("transactions", children.map { S(id: $0.id, userId: uid, accountId: $0.accountId, amount: $0.amount, currency: $0.currency, date: $0.date, rawName: $0.rawName, merchantName: $0.merchantName, paymentMethod: $0.paymentMethod.rawValue, kind: $0.kind.rawValue, categoryId: $0.categoryId, categorySource: "user", splitParentId: tx.id) })
        } catch { show(error) }
    }

    // MARK: Pockets & categories

    func moveCategory(_ category: TxCategory, to pocket: Pocket) async {
        guard let i = categories.firstIndex(where: { $0.id == category.id }) else { return }
        categories[i].pocketId = pocket.id
        Haptics.success()
        struct U: Encodable { let pocketId: UUID }
        do { try await backend?.update("categories", id: category.id, U(pocketId: pocket.id)) } catch { show(error) }
    }

    func savePocket(_ pocket: Pocket) async {
        if let i = pockets.firstIndex(where: { $0.id == pocket.id }) { pockets[i] = pocket } else { pockets.append(pocket) }
        guard let backend, let uid = userId else { return }
        struct P: Encodable { let id: UUID; let userId: UUID; let name: String; let icon: String; let color: String; let sort: Int }
        do { try await backend.upsert("pockets", P(id: pocket.id, userId: uid, name: pocket.name, icon: pocket.icon, color: pocket.color, sort: pocket.sort)) } catch { show(error) }
    }

    func saveCategory(_ category: TxCategory) async {
        if let i = categories.firstIndex(where: { $0.id == category.id }) { categories[i] = category } else { categories.append(category) }
        guard let backend, let uid = userId else { return }
        struct C: Encodable { let id: UUID; let userId: UUID; let pocketId: UUID; let name: String; let icon: String; let sort: Int; let archived: Bool }
        do { try await backend.upsert("categories", C(id: category.id, userId: uid, pocketId: category.pocketId, name: category.name, icon: category.icon, sort: category.sort, archived: category.archived)) } catch { show(error) }
    }

    // MARK: Budgets

    func setBudget(pocketId: UUID?, categoryId: UUID?, amount: Decimal?) async {
        let existing = budgets.first { $0.pocketId == pocketId && $0.categoryId == categoryId }
        if let amount, amount > 0 {
            var b = existing ?? Budget(pocketId: pocketId, categoryId: categoryId, amount: amount, currency: currency)
            b.amount = amount
            if let i = budgets.firstIndex(where: { $0.id == b.id }) { budgets[i] = b } else { budgets.append(b) }
            guard let backend, let uid = userId else { return }
            struct B: Encodable { let id: UUID; let userId: UUID; let pocketId: UUID?; let categoryId: UUID?; let amount: Decimal; let currency: String; let period: String }
            do {
                try await backend.upsert("budgets", B(id: b.id, userId: uid, pocketId: pocketId, categoryId: categoryId, amount: amount, currency: b.currency, period: b.period.rawValue))
                try await backend.invokeVoid("notify", ["mode": .string("evaluate")])
            } catch { show(error) }
        } else if let existing {
            budgets.removeAll { $0.id == existing.id }
            do { try await backend?.delete("budgets", id: existing.id) } catch { show(error) }
        }
    }

    // MARK: Goals

    func createGoal(name: String, icon: String, color: String, target: Decimal, date: Day?, funding: GoalFunding, accountId: UUID?, earmark: Decimal?) async -> Goal? {
        guard let uid = userId else { return nil }
        let goal = Goal(ownerId: uid, name: name, icon: icon, color: color, targetAmount: target, currency: currency, targetDate: date)
        let start: Decimal = funding == .earmark ? (earmark ?? 0) : (funding == .account ? (accounts.first { $0.id == accountId }?.currentBalance ?? 0) : 0)
        goals.append(goal)
        members.append(GoalMember(goalId: goal.id, userId: uid, funding: funding, currentAmount: start))
        ownFunding.append(GoalFundingSettings(goalId: goal.id, userId: uid, funding: funding, accountId: accountId, earmarkAmount: earmark, currentAmount: start))
        writeWidgetSnapshot()
        guard let backend else { return goal }
        struct G: Encodable { let id: UUID; let ownerId: UUID; let name: String; let icon: String; let color: String; let targetAmount: Decimal; let currency: String; let targetDate: Day? }
        struct M: Encodable { let goalId: UUID; let userId: UUID; let role: String; let funding: GoalFunding; let accountId: UUID?; let earmarkAmount: Decimal? }
        do {
            try await backend.insert("goals", G(id: goal.id, ownerId: uid, name: name, icon: icon, color: color, targetAmount: target, currency: currency, targetDate: date))
            try await backend.insert("goal_members", M(goalId: goal.id, userId: uid, role: "owner", funding: funding, accountId: accountId, earmarkAmount: earmark))
            try await backend.invokeVoid("goal-action", ["action": .string("check"), "goalId": .string(goal.id.uuidString)])
            await load()
        } catch { show(error) }
        return goal
    }

    func contribute(_ goal: Goal, amount: Decimal) async {
        guard let uid = userId, let i = members.firstIndex(where: { $0.goalId == goal.id && $0.userId == uid }) else { return }
        let funding = ownFunding.first { $0.goalId == goal.id }?.funding ?? .manual
        members[i].currentAmount = (members[i].currentAmount ?? 0) + amount
        events.insert(GoalEvent(goalId: goal.id, userId: uid, kind: amount >= 0 ? "contribution" : "withdrawal", amount: amount.abs), at: 0)
        Haptics.success()
        writeWidgetSnapshot()
        guard let backend else { return }
        struct E: Encodable { let goalId: UUID; let userId: UUID; let kind: String; let amount: Decimal }
        struct F: Encodable { let earmarkAmount: Decimal }
        do {
            if funding == .earmark {
                let newEarmark = members[i].currentAmount ?? 0
                try await backend.client.from("goal_members").update(F(earmarkAmount: newEarmark)).eq("goal_id", value: goal.id).eq("user_id", value: uid).execute()
            }
            try await backend.insert("goal_events", E(goalId: goal.id, userId: uid, kind: amount >= 0 ? "contribution" : "withdrawal", amount: amount.abs))
            try await backend.invokeVoid("goal-action", ["action": .string("check"), "goalId": .string(goal.id.uuidString)])
        } catch { show(error) }
    }

    func archiveGoal(_ goal: Goal) async {
        goals.removeAll { $0.id == goal.id }
        writeWidgetSnapshot()
        struct U: Encodable { let archivedAt: Date }
        do { try await backend?.update("goals", id: goal.id, U(archivedAt: Date())) } catch { show(error) }
    }

    func inviteLink(for goal: Goal, shareAmount: Bool, shareActivity: Bool) async -> URL? {
        guard let backend else { return URL(string: "https://\(AppConfig.linkDomain)/join?code=DEMO") }
        struct R: Decodable { let url: String }
        do {
            let r: R = try await backend.invoke("goal-action", [
                "action": .string("invite"), "goalId": .string(goal.id.uuidString),
                "shareAmountVisible": .bool(shareAmount), "shareActivity": .bool(shareActivity),
            ])
            return URL(string: r.url)
        } catch { show(error); return nil }
    }

    struct InvitePreview: Decodable { struct G: Decodable { let name: String; let targetAmount: Decimal; let currency: String }; let goal: G; let inviter: String }

    func previewInvite(code: String) async -> InvitePreview? {
        guard let backend else { return nil }
        do { return try await backend.invoke("goal-action", ["action": .string("preview"), "code": .string(code)]) } catch { show(error); return nil }
    }

    func joinGoal(code: String, funding: GoalFunding) async {
        guard let backend else { return }
        do {
            try await backend.invokeVoid("goal-action", ["action": .string("join"), "code": .string(code), "funding": .string(funding.rawValue)])
            await load()
            Haptics.success()
            showToast("person.2.fill", tr("toast.joinedGoal"))
        } catch { show(error) }
    }

    func cheer(_ goal: Goal) async {
        Haptics.success()
        guard let backend else { return }
        do { try await backend.invokeVoid("goal-action", ["action": .string("cheer"), "goalId": .string(goal.id.uuidString)]) } catch { show(error) }
    }

    func leave(_ goal: Goal) async {
        goals.removeAll { $0.id == goal.id }
        guard let backend else { return }
        do { try await backend.invokeVoid("goal-action", ["action": .string("leave"), "goalId": .string(goal.id.uuidString)]) } catch { show(error) }
    }

    // MARK: Settings

    func setCurrency(_ code: String) async {
        profile?.displayCurrency = code
        writeWidgetSnapshot()
        guard let backend, let uid = userId else { return }
        struct U: Encodable { let displayCurrency: String }
        do { try await backend.update("profiles", id: uid, U(displayCurrency: code)) } catch { show(error) }
    }

    func setPrefs(_ p: NotificationPrefs) async {
        prefs = p
        guard let backend, let uid = userId else { return }
        struct U: Encodable { let userId: UUID; let goalReached, goalMilestones, budgetWarning, budgetExceeded, billsDue, paydaySummary, reauth: Bool }
        do { try await backend.upsert("notification_prefs", U(userId: uid, goalReached: p.goalReached, goalMilestones: p.goalMilestones, budgetWarning: p.budgetWarning, budgetExceeded: p.budgetExceeded, billsDue: p.billsDue, paydaySummary: p.paydaySummary, reauth: p.reauth), onConflict: "user_id") } catch { show(error) }
    }

    func registerDevice(token: Data) async {
        guard let backend, let uid = userId else { return }
        let hex = token.map { String(format: "%02x", $0) }.joined()
        #if DEBUG
        let env = "sandbox"
        #else
        let env = "production"
        #endif
        struct D: Encodable { let token: String; let userId: UUID; let environment: String; let locale: String }
        do { try await backend.upsert("device_tokens", D(token: hex, userId: uid, environment: env, locale: Locale.current.identifier), onConflict: "token") } catch { print("device token", error) }
    }

    func deleteAccount() async {
        do { try await backend?.invokeVoid("delete-account") } catch { show(error); return }
        await signOut()
    }

    // MARK: Feedback

    func showToast(_ icon: String, _ text: String, tint: Color = Palette.positive) {
        withAnimation(Motion.bouncy) { toast = Toast(icon: icon, text: text, tint: tint) }
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(Motion.smooth) { if toast?.text == text { toast = nil } }
        }
    }

    func show(_ error: Error) {
        lastError = error.localizedDescription
        showToast("exclamationmark.triangle.fill", tr("toast.error"), tint: Palette.over)
        print("akwe error:", error)
    }

    // MARK: Widgets

    func writeWidgetSnapshot() {
        AppGroup.write(ledger.widgetSnapshot(hideBalances: hideBalances))
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Cache (fast cold start; server stays the source of truth)

    private struct Cache: Codable {
        var profile: Profile?; var schedule: PaySchedule; var items: [BankItem]; var accounts: [Account]; var pockets: [Pocket]
        var categories: [TxCategory]; var transactions: [Transaction]; var budgets: [Budget]; var recurring: [RecurringStream]
        var goals: [Goal]; var members: [GoalMember]
    }

    private var cacheURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("akwe-cache.json")
    }

    private func saveCache() {
        guard let url = cacheURL else { return }
        let c = Cache(profile: profile, schedule: schedule, items: items, accounts: accounts, pockets: pockets, categories: categories, transactions: transactions, budgets: budgets, recurring: recurring, goals: goals, members: members)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(c) {
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }

    private func loadCache() {
        guard let url = cacheURL, let data = try? Data(contentsOf: url), let c = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        profile = c.profile; schedule = c.schedule; items = c.items; accounts = c.accounts; pockets = c.pockets
        categories = c.categories; transactions = c.transactions; budgets = c.budgets; recurring = c.recurring; goals = c.goals; members = c.members
    }

    private func clearCache() {
        if let url = cacheURL { try? FileManager.default.removeItem(at: url) }
    }
}

enum AppError: LocalizedError {
    case demo
    var errorDescription: String? { tr("error.demo") }
}
