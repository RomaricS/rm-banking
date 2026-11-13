import SwiftUI
import AkweKit

enum AppTab: String, CaseIterable, Identifiable {
    case home, activity, insights, plan
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: "house.fill"
        case .activity: "arrow.left.arrow.right"
        case .insights: "chart.bar.fill"
        case .plan: "target"
        }
    }
    var title: String { tr("tab.\(rawValue)") }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var app
    @State private var tab: AppTab = .home
    @State private var homePath = NavigationPath()
    @State private var activityPath = NavigationPath()
    @State private var insightsPath = NavigationPath()
    @State private var planPath = NavigationPath()

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .home: NavigationStack(path: $homePath) { HomeView(tab: $tab).withDestinations() }
                case .activity: NavigationStack(path: $activityPath) { ActivityView().withDestinations() }
                case .insights: NavigationStack(path: $insightsPath) { InsightsView().withDestinations() }
                case .plan: NavigationStack(path: $planPath) { PlanView().withDestinations() }
                }
            }
            .transition(.opacity)
            FloatingTabBar(selection: $tab)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
        }
        .ignoresSafeArea(.keyboard)
        .task { await AppDelegate.requestPushPermission() }
    }
}

/// Glass capsule with a pill that morphs between tabs (canvas › Motion › Tab pill morph).
struct FloatingTabBar: View {
    @Binding var selection: AppTab
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { t in
                Button {
                    guard t != selection else { return }
                    Haptics.selection()
                    withAnimation(.snappy(duration: 0.35, extraBounce: 0.12)) { selection = t }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: t.icon).font(.system(size: 18, weight: .semibold))
                        if selection == t {
                            Text(t.title).font(.system(size: 15, weight: .bold)).lineLimit(1).fixedSize()
                                .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                        }
                    }
                    .foregroundStyle(selection == t ? Palette.onInverse : Palette.text2)
                    .padding(.horizontal, selection == t ? 18 : 0)
                    .frame(minWidth: 52, minHeight: 48)
                    .background {
                        if selection == t {
                            Capsule().fill(Palette.inverse).matchedGeometryEffect(id: "tabpill", in: ns)
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: selection == t ? nil : .infinity)
                .accessibilityLabel(t.title)
                .accessibilityAddTraits(selection == t ? .isSelected : [])
            }
        }
        .padding(8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Palette.stroke))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
    }
}

// MARK: - Navigation destinations shared by all tabs

enum Route: Hashable {
    case transaction(UUID)
    case pocket(UUID)
    case managePockets
    case recurring
    case goal(UUID)
    case review
    case accounts
    case settings
    case alerts
    case currency
}

extension View {
    func withDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .transaction(let id): TransactionDetailView(id: id)
            case .pocket(let id): PocketDetailView(pocketId: id)
            case .managePockets: ManagePocketsView()
            case .recurring: RecurringView()
            case .goal(let id): GoalDetailView(goalId: id)
            case .review: ReviewView()
            case .accounts: AccountsView()
            case .settings: SettingsView()
            case .alerts: AlertSettingsView()
            case .currency: CurrencyView()
            }
        }
    }
}

/// Bottom padding so scroll content clears the floating tab bar.
let tabBarClearance: CGFloat = 96
