import UIKit
import LinkKit

/// Opens Plaid Link (native SDK) and reports the public token. Keeps the handler alive while Link is open.
@MainActor
final class PlaidLinker {
    struct Result { let publicToken: String; let institutionId: String?; let institutionName: String? }

    private var handler: Handler?

    func open(token: String) async -> Result? {
        await withCheckedContinuation { (cont: CheckedContinuation<Result?, Never>) in
            var finished = false
            func finish(_ r: Result?) {
                guard !finished else { return }
                finished = true
                self.handler = nil
                cont.resume(returning: r)
            }
            var config = LinkTokenConfiguration(token: token) { success in
                finish(Result(publicToken: success.publicToken,
                              institutionId: success.metadata.institution.id,
                              institutionName: success.metadata.institution.name))
            }
            config.onExit = { _ in finish(nil) }

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
    }

    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var vc = scene?.keyWindow?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}
