import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 248, ideal: 268, max: 312)
        } detail: {
            TimerStageView()
        }
        .background(LumenTheme.ink)
        #if os(macOS)
        .toolbarBackground(.hidden, for: .windowToolbar)
        #endif
        .frame(minWidth: 880, minHeight: 560)
    }
}
