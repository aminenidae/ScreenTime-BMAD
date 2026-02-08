import SwiftUI

/// About screen showing app info and credits
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("\(appVersion) (\(buildNumber))")
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Link(destination: URL(string: "https://i6dev.ca/screentimerewards/privacy.html")!) {
                        HStack {
                            Text("Privacy Policy")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundColor(.secondary)
                        }
                    }

                    Link(destination: URL(string: "https://i6dev.ca/screentimerewards/terms.html")!) {
                        HStack {
                            Text("Terms of Service")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Legal")
                }

                Section {
                    Link(destination: URL(string: "https://i6dev.ca/screentimerewards/support.html")!) {
                        HStack {
                            Text("Help & Support")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundColor(.secondary)
                        }
                    }

                    Link(destination: URL(string: "mailto:support@i6dev.ca")!) {
                        HStack {
                            Text("Contact Us")
                            Spacer()
                            Image(systemName: "envelope")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Support")
                }

                Section {
                    Text("ScreenTime Rewards helps families balance screen time by rewarding learning app usage with game time.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
