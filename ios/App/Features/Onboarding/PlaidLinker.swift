import UIKit
import LinkKit

/// Opens Plaid Link (native SDK) and reports the public token. Keeps the handler alive while Link is open.
@MainActor
final class PlaidLinker {
    struct Result { let publicToken: String; let institutionId: String?; let institutionName: String? }

    private var handler: Handler?
    private var continuation: CheckedContinuation<Result?, Never>?

    func open(token: String) async -> Result? {
        finish(nil) // resolve any Link session that is still pending
        return await withCheckedContinuation { (cont: CheckedContinuation<Result?, Never>) in
            // The body runs synchronously on the caller's executor (the main actor), so this is safe.
            MainActor.assumeIsolated { self.start(token: token, continuation: cont) }
        }
    }

    private func start(token: String, continuation cont: CheckedContinuation<Result?, Never>) {
        continuation = cont
        var config = LinkTokenConfiguration(token: token) { [weak self] success in
            self?.finish(Result(publicToken: success.publicToken,
                                institutionId: success.metadata.institution.id,
                                institutionName: success.metadata.institution.name))
        }
        config.onExit = { [weak self] _ in self?.finish(nil) }

        switch Plaid.create(config) {
        case .failure(let error):
            print("Plaid create failed:", error)
            finish(nil)
        case .success(let handler):
            self.handler = handler
            guard let vc = Self.topViewController() else { finish(nil); return }
            handler.open(presentUsing: .viewController(vc))
        }
    }

    private func finish(_ result: Result?) {
        guard let cont = continuation else { return }
        continuation = nil
        handler = nil
        cont.resume(returning: result)
    }

    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var vc = scene?.keyWindow?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}
