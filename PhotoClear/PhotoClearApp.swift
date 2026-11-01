import SwiftUI

@main
struct PhotoClearApp: App {
    @StateObject private var library = PhotoLibraryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .preferredColorScheme(.light)
        }
    }
}
