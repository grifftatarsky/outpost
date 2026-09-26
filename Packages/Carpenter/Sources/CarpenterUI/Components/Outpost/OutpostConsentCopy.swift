import CarpenterKit
import SwiftUI

public enum OutpostConsentCopy {
    // COPY BEGIN ed0bc824 [NEEDS HUMAN REVIEW]
    public static func title(of standing: OutpostConsent) -> Text {
        switch standing {
        case .open: return Text("Open", bundle: .module)
        case .closed: return Text("Closed", bundle: .module)
        case .quiet: return Text("Read only", bundle: .module)
        case .off: return Text("Turn Outposts off", bundle: .module)
        }
    }
    // COPY END ed0bc824

    // COPY BEGIN 07cf4252 [NEEDS HUMAN REVIEW]
    public static func detail(of standing: OutpostConsent) -> Text {
        switch standing {
        case .open:
            return Text(
                "What you write on somebody's post reaches everybody they let in. People you have not met see one anonymous figure.",
                bundle: .module)
        case .closed:
            return Text(
                "What you write on somebody's post reaches only the people you have let into your own Outpost. To everybody else it is not there.",
                bundle: .module)
        case .quiet:
            return Text(
                "You read. Nothing of yours appears under anybody else's post.", bundle: .module)
        case .off:
            return Text("The tab goes away. Your own posts stay where they are.", bundle: .module)
        }
    }
    // COPY END 07cf4252

    public static func symbol(of standing: OutpostConsent) -> String {
        switch standing {
        case .open: return "person.2.wave.2.fill"
        case .closed: return "lock.fill"
        case .quiet: return "eyeglasses"
        case .off: return "rectangle.slash"
        }
    }
}
