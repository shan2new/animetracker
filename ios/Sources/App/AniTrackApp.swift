import SwiftUI
import ClerkKit

@main
struct AniTrackApp: App {
    @State private var auth = AuthManager()
    @State private var appModel: AppModel

    init() {
        // Configure Clerk synchronously so Clerk.shared is valid before the view hierarchy builds.
        if AppConfig.isClerkConfigured {
            Clerk.configure(publishableKey: AppConfig.clerkPublishableKey)
        }
        let auth = AuthManager()
        _auth = State(initialValue: auth)
        _appModel = State(initialValue: AppModel(api: APIClient(tokenProvider: auth)))
    }

    var body: some Scene {
        WindowGroup {
            rootContent
                .environment(auth)
                .environment(appModel)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .task { await auth.bootstrap() }
        }
    }

    // Inject Clerk.shared only when a key is configured — accessing Clerk.shared without
    // calling configure() first triggers an assertion failure.
    @ViewBuilder
    private var rootContent: some View {
        if AppConfig.isClerkConfigured {
            RootView().environment(Clerk.shared)
        } else {
            RootView()
        }
    }
}
