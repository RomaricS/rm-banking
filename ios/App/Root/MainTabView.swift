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
            // Content fades out under the floating tab bar.
            LinearGradient(stops: [.init(color: Palette.ground.opacity(0), location: 0),
                                   .init(color: Palette.ground.opacity(0.72), location: 0.38),
                                   .init(color: Palette.ground, location: 0.72)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 150)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
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
                        TabIcon(tab: t)
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
                // The selected pill keeps its natural width (icon + label + padding) so the text never
                // touches its edges; the other tabs share the remaining space.
                .fixedSize(horizontal: selection == t, vertical: false)
                .layoutPriority(selection == t ? 1 : 0)
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

/// Tab icons. Activity and Insights are drawn from the design canvas's stroke icons (SF Symbols differ);
/// Home and Plan use SF Symbols, which already match.
struct TabIcon: View {
    let tab: AppTab
    var body: some View {
        switch tab {
        case .activity, .insights:
            StrokeIcon(kind: tab)
                .stroke(style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                .frame(width: 22, height: 22)
        default:
            Image(systemName: tab.icon).font(.system(size: 18, weight: .semibold))
        }
    }
}

/// Paths from the canvas SVGs (24×24 viewBox), scaled to the frame.
struct StrokeIcon: Shape {
    let kind: AppTab
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        switch kind {
        case .insights:
            // M5 20V11 M12 20V4 M19 20v-6
            path.move(to: p(5, 20)); path.addLine(to: p(5, 11))
            path.move(to: p(12, 20)); path.addLine(to: p(12, 4))
            path.move(to: p(19, 20)); path.addLine(to: p(19, 14))
        default:
            // M7 7h13 M16 3l4 4-4 4 M17 17H4 M8 13l-4 4 4 4
            path.move(to: p(7, 7)); path.addLine(to: p(20, 7))
            path.move(to: p(16, 3)); path.addLine(to: p(20, 7)); path.addLine(to: p(16, 11))
            path.move(to: p(17, 17)); path.addLine(to: p(4, 17))
            path.move(to: p(8, 13)); path.addLine(to: p(4, 17)); path.addLine(to: p(8, 21))
        }
        return path
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
