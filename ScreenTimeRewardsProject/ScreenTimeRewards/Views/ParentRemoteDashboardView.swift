import SwiftUI

struct ParentRemoteDashboardView: View {
    @StateObject private var modeManager = DeviceModeManager.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Parent Remote Dashboard")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Welcome, Parent!")
                    .font(.title2)
                
                Text("Device: \(modeManager.deviceName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Remote Monitoring & Configuration")
                        .font(.headline)
                    
                    Text("This dashboard will allow you to:")
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text("• Monitor your child's app usage")
                        Text("• Configure learning and reward apps")
                        Text("• Set point values for activities")
                        Text("• Block or unblock specific apps")
                        Text("• View usage reports and trends")
                    }
                    .font(.subheadline)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Remote Dashboard")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct ParentRemoteDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        ParentRemoteDashboardView()
    }
}