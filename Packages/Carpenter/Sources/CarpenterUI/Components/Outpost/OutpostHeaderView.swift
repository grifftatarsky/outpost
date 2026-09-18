import CarpenterKit
import PhotosUI
import SwiftUI

struct OutpostHeaderView: View {
    @Environment(\.palette) private var palette

    let person: Member
    let blurb: String?
    let isViewer: Bool
    var picking: Binding<PhotosPickerItem?>?

    @State private var choosing = false

    @ViewBuilder private var disc: some View {
        let face = PersonAvatarView(member: person, diameter: 56, isAccented: isViewer, onOutpost: true)
        if let picking, isViewer {
            Button { choosing = true } label: {
                face
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(palette.accentFill, in: .circle)
                            .overlay(Circle().strokeBorder(palette.background, lineWidth: 2))
                            .offset(x: 2, y: 2)
                            .accessibilityHidden(true)
                    }
            }
            .buttonStyle(.plain)
            .photosPicker(isPresented: $choosing, selection: picking, matching: .images)
            .accessibilityLabel(Text("Change the picture on your Outpost", bundle: .module))
        } else {
            face
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                disc

                VStack(alignment: .leading, spacing: 3) {
                    if !person.isPlaceholder {
                        Text(verbatim: person.displayName)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(palette.primaryText)
                    }
                    if !person.isAnonymous {
                        Text(verbatim: person.id.groupedFingerprint)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(palette.tertiaryText)
                    }
                }

                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            if let blurb {
                Text(verbatim: blurb)
                    .font(CarpenterFont.rowDetail)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 14)
        .padding(.horizontal, CarpenterMetrics.screenMargin)
    }
}

struct OutpostHeaderDivider: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Rectangle()
            // divides regions: the header from the wall
            .fill(palette.separator)
            .frame(height: 0.5)
            .padding(.horizontal, CarpenterMetrics.screenMargin)
            .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview("An Outpost header") {
        VStack(spacing: 0) {
            OutpostHeaderView(
                person: Fixtures.camilla,
                blurb: "Keeping the masthead honest since the second dirigible.",
                isViewer: false)
            OutpostHeaderDivider()
            Spacer()
        }
        .themed(.default)
    }
#endif
