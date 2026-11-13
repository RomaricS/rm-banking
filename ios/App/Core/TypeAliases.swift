import AkweKit

/// SwiftUI also exports `Transaction` (animation transactions). A module-level alias makes the
/// app target resolve the bare name to our model everywhere, without qualifying each use.
typealias Transaction = AkweKit.Transaction
