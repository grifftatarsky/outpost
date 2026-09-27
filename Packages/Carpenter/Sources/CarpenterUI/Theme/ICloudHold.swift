import SwiftUI

extension EnvironmentValues {
    @Entry public var iCloudHold: Bool = false
}

public struct ICloudHoldBanner: View {
    @Environment(\.palette) private var palette

    public init() {}

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.icloud")
                .font(.title3)
                .foregroundStyle(palette.secondaryText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                // COPY BEGIN ffbab6ed [NEEDS HUMAN REVIEW]
                Text("iCloud hasn't trusted this device", bundle: .module)
                    .font(CarpenterFont.rowTitle)
                    .foregroundStyle(palette.primaryText)
                Text(
                    "Your Apple Account's security settings, such as Advanced Data Protection, keep it out of iCloud until your other devices trust it. You can read what's here; sending waits.",
                    bundle: .module)
                    .font(CarpenterFont.rowDetail)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                // COPY END ffbab6ed
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(palette.elevatedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
    #Preview("iCloud holding this device") {
        ICloudHoldBanner()
            .themed(.default)
    }
#endif
