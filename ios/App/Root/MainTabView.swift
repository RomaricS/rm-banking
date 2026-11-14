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
    @State private var tab: AppTab = {
        #if DEBUG
        // Screenshots / UI checks: launch with `-AkweTab insights` to open on a given tab.
        if let raw = UserDefaults.standard.string(forKey: "AkweTab"), let t = AppTab(rawValue: raw) { return t }
        #endif
        return .home
    }()
    @State private var homePath: NavigationPath = {
        var path = NavigationPath()
        #if DEBUG
        // Screenshots / UI checks: launch with `-AkweRoute accounts|review|settings` to open that screen.
        switch UserDefaults.standard.string(forKey: "AkweRoute") {
        case "accounts": path.append(Route.accounts)
        case "review": path.append(Route.review)
        case "settings": path.append(Route.settings)
        case "recurring": path.append(Route.recurring)
        default: break
        }
        #endif
        return path
    }()
    @State private var activityPath = NavigationPath()
    @State private var insightsPath = NavigationPath()
    @State private var planPath = NavigationPath()

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                nativeTabs
            } else {
                legacyTabs
            }
        }
        .ignoresSafeArea(.keyboard)
        .task {
            #if DEBUG
            // Screenshot runs (-AkweTab / -AkweRoute) skip the system prompt so it doesn't cover the screen.
            if UserDefaults.standard.string(forKey: "AkweTab") != nil || UserDefaults.standard.string(forKey: "AkweRoute") != nil { return }
            #endif
            await AppDelegate.requestPushPermission()
        }
    }

    /// iOS 26+: the system tab bar (Liquid Glass) — floating glass capsule, native selection morph,
    /// shrinks while scrolling down, and its own edge blur under the content.
    @available(iOS 26.0, *)
    private var nativeTabs: some View {
        TabView(selection: $tab) {
            Tab(value: AppTab.home) {
                NavigationStack(path: $homePath) { HomeView(tab: $tab).withDestinations() }
            } label: { tabLabel(.home) }
            Tab(value: AppTab.activity) {
                NavigationStack(path: $activityPath) { ActivityView().withDestinations() }
            } label: { tabLabel(.activity) }
            Tab(value: AppTab.insights) {
                NavigationStack(path: $insightsPath) { InsightsView().withDestinations() }
            } label: { tabLabel(.insights) }
            Tab(value: AppTab.plan) {
                NavigationStack(path: $planPath) { PlanView().withDestinations() }
            } label: { tabLabel(.plan) }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Palette.iris)
        .onChange(of: tab) { _, _ in Haptics.selection() }
    }

    private func tabLabel(_ t: AppTab) -> some View {
        Label { Text(t.title) } icon: { TabIcon.image(t) }
    }

    /// iOS 17–25: custom glass capsule from the design canvas.
    private var legacyTabs: some View {
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
            // Content fades out under the floating tab bar. Pinned in a VStack so the gradient itself
            // reaches the screen's bottom edge (a framed gradient stopped at the safe area).
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LinearGradient(stops: [.init(color: Palette.ground.opacity(0), location: 0),
                                       .init(color: Palette.ground.opacity(0.6), location: 0.45),
                                       .init(color: Palette.ground, location: 0.85)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 150)
            }
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            FloatingTabBar(selection: $tab)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
        }
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
                .buttonStyle(.row)
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

    /// Template image for the system tab bar (it only renders `Image`s). Custom stroke icons are
    /// rasterised once; Home and Plan stay SF Symbols.
    @MainActor
    static func image(_ tab: AppTab) -> Image {
        switch tab {
        case .activity, .insights:
            if let cached = cache[tab] { return cached }
            let renderer = ImageRenderer(content:
                StrokeIcon(kind: tab)
                    .stroke(Color.black, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                    .frame(width: 24, height: 24))
            renderer.scale = 3
            guard let ui = renderer.uiImage else { return Image(systemName: tab.icon) }
            let image = Image(uiImage: ui.withRenderingMode(.alwaysTemplate))
            cache[tab] = image
            return image
        default:
            return Image(systemName: tab.icon)
        }
    }
    @MainActor private static var cache: [AppTab: Image] = [:]

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
    case pocket(UUID, PeriodKind = .payPeriod, offset: Int = 0)
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
            case .pocket(let id, let kind, let offset): PocketDetailView(pocketId: id, kind: kind, offset: offset)
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
var tabBarClearance: CGFloat {
    // The native iOS 26 tab bar already insets content; the custom bar floats over it.
    if #available(iOS 26.0, *) { return 24 } else { return 96 }
}
