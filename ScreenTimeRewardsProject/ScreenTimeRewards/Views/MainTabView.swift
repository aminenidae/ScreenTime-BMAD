import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            RewardsTabView()
                .tabItem {
                    Label("Rewards", systemImage: "gamecontroller.fill")
                }

            LearningTabView()
                .tabItem {
                    Label("Learning", systemImage: "book.fill")
                }
        }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
