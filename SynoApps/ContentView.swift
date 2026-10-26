import SwiftUI

struct ContentView: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        Group {
            if store.isAuthenticated {
                LibraryView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.22), value: store.isAuthenticated)
    }
}

#Preview {
    ContentView()
        .environment(LibraryStore())
}
