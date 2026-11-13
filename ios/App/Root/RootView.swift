import SwiftUI
import LocalAuthentication
import AkweKit

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            Palette.ground.ignoresSafeArea()
            switch app.phase {
            case .launching:
                CowrieMark(size: 84).transition(.opacity)
            case .signedOut:
                WelcomeView().transition(.opacity)
            case .onboarding:
                OnboardingFlow().transition(.move(edge: .trailing).combined(with: .opacity))
            case .ready:
                MainTabView().transition(.opacity)
            }
        }
        .animation(Motion.smooth, value: app.phase)
        .overlay(alignment: .top) { ToastView() }
        .overlay {
            if app.isLocked { LockView().transition(.opacity) }
        }
        .animation(Motion.smooth, value: app.isLocked)
        .sheet(item: Binding(get: { app.pendingInviteCode.map(InviteCode.init) }, set: { app.pendingInviteCode = $0?.code })) { invite in
            JoinGoalSheet(code: invite.code)
        }
    }
}

struct InviteCode: Identifiable { let code: String; var id: String { code } }

struct ToastView: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        if let t = app.toast {
            HStack(spacing: 10) {
                Image(systemName: t.icon).foregroundStyle(t.tint)
                Text(t.text).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .id(t.id)
            .accessibilityAddTraits(.isStaticText)
        }
    }
}

/// Face ID gate (also blurs the app in the app switcher).
struct LockView: View {
    @Environment(AppModel.self) private var app
    @State private var failed = false

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 22) {
                CowrieMark(size: 72)
                Button {
                    Task { await unlock() }
                } label: {
                    Label(tr("lock.unlock"), systemImage: "faceid")
                }
                .buttonStyle(SecondaryButtonStyle())
                if failed { Text(tr("lock.failed")).font(.footnote).foregroundStyle(Palette.text2) }
            }
        }
        .task { await unlock() }
    }

    private func unlock() async {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { app.isLocked = false; return }
        do {
            if try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: tr("lock.reason")) {
                Haptics.success()
                app.isLocked = false
            }
        } catch {
            failed = true
        }
    }
}
