//
//  SetupCompleteScreen.swift
//  ScreenTimeRewards
//
//  Option D: First Launch Setup Flow
//  Shows setup completion and instructions
//

import SwiftUI

struct SetupCompleteScreen: View {
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [Color.green.opacity(0.3), Color.blue.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Success icon with animation
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 100))
                    .foregroundColor(.green)

                // Title
                Text("Setup Complete!")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                // Success message
                Text("Your app is ready to use")
                    .font(.title3)
                    .foregroundColor(.secondary)

                Spacer()

                // Instructions
                VStack(alignment: .leading, spacing: 20) {
                    Text("How to use the app:")
                        .font(.headline)
                        .padding(.bottom, 8)

                    InstructionRow(
                        number: "1",
                        text: "Choose Parent Mode or Child Mode"
                    )

                    InstructionRow(
                        number: "2",
                        text: "Parents: Enter your PIN to access settings"
                    )

                    InstructionRow(
                        number: "3",
                        text: "Set up learning and reward apps"
                    )

                    InstructionRow(
                        number: "4",
                        text: "Children: Use learning apps to earn points!"
                    )
                }
                .padding(.horizontal, 40)

                Spacer()

                // Start button
                Button(action: onComplete) {
                    HStack {
                        Text("Start Using App")
                            .font(.headline)
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                    .shadow(radius: 5)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
    }
}

struct InstructionRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            // Number circle
            Text(number)
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Color.blue)
                .clipShape(Circle())

            Text(text)
                .font(.body)
        }
    }
}

struct SetupCompleteScreen_Previews: PreviewProvider {
    static var previews: some View {
        SetupCompleteScreen(onComplete: {})
    }
}
