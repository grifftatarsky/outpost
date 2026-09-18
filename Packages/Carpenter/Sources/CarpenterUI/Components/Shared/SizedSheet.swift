import SwiftUI

extension View {
    public func sizedSheet<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            content().sheetSizedForThisPlatform()
        }
    }

    public func sizedSheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        sheet(item: item, onDismiss: onDismiss) { presented in
            content(presented).sheetSizedForThisPlatform()
        }
    }

    @ViewBuilder
    fileprivate func sheetSizedForThisPlatform() -> some View {
        #if os(macOS)
            presentationSizing(.form)
        #else
            self
        #endif
    }
}
