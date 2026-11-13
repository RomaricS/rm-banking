import SwiftUI
import AuthenticationServices
import CryptoKit
import AkweKit

/// 1.1 Welcome — Sign in with Apple only.
struct WelcomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var scheme
    @State private var nonce = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            AuroraBackground(height: 700).ignoresSafeArea()
            FloatingChips().padding(.top, 60).frame(maxHeight: .infinity, alignment: .top)

            VStack(alignment: .leading, spacing: 16) {
                CowrieMark(size: 60).rise(0)
                Text(tr("welcome.title"))
                    .font(.system(size: 40, weight: .heavy)).tracking(-1.2)
                    .foregroundStyle(Palette.text).rise(1)
                Text(tr("welcome.subtitle"))
                    .font(.system(size: 16)).foregroundStyle(Palette.text2).rise(2)

                SignInWithAppleButton(.signIn) { request in
                    nonce = Self.randomNonce()
                    request.requestedScopes = [.fullName]
                    request.nonce = Self.sha256(nonce)
                } onCompletion: { result in
                    guard case .success(let auth) = result,
                          let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                          let tokenData = cred.identityToken, let token = String(data: tokenData, encoding: .utf8) else { return }
                    Task { await app.signIn(idToken: token, nonce: nonce) }
                }
                .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
                .frame(height: 56)
                .clipShape(Capsule())
                .padding(.top, 12)
                .rise(3)

                Text(tr("welcome.readOnly"))
                    .font(.system(size: 12)).foregroundStyle(Palette.text3)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<length).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }

    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Glass chips floating on slow, offset loops.
private struct FloatingChips: View {
    @State private var up = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            chip(tr("welcome.chip.paycheck"), "+$3,250", Palette.positive).rotationEffect(.degrees(-6)).offset(x: -90, y: up ? -10 : 4)
                .animation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true), value: up)
            chip(tr("welcome.chip.food"), "36%", Palette.text).rotationEffect(.degrees(5)).offset(x: 90, y: up ? 54 : 66)
                .animation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true), value: up)
            chip(tr("welcome.chip.goal"), tr("welcome.chip.onTrack"), Color(hex: 0x7C9CFF)).rotationEffect(.degrees(-3)).offset(x: -40, y: up ? 150 : 162)
                .animation(.easeInOut(duration: 3.1).repeatForever(autoreverses: true), value: up)
            chip(tr("welcome.chip.safe"), "$64", Palette.text).rotationEffect(.degrees(4)).offset(x: 100, y: up ? 214 : 226)
                .animation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true), value: up)
        }
        .accessibilityHidden(true)
        .onAppear { if !reduceMotion { up = true } }
    }

    private func chip(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12)).foregroundStyle(Palette.text2)
            Text(value).font(.system(size: 18, weight: .heavy)).foregroundStyle(color)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.stroke))
    }
}
