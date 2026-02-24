//
//  LaunchScreenView.swift
//  ScreenTimeRewards
//
//  Custom launch screen with staggered 3D tile-flip animation
//

import SwiftUI

struct LaunchScreenView: View {
    // One rotation angle per tile in Z-pattern order: [TL, TR, BL, BR]
    @State private var tileRotations: [Double] = [0, 0, 0, 0]
    @State private var opacity: Double = 1.0
    @State private var isLaunchComplete = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if isLaunchComplete {
            RootView()
                .transition(.opacity)
        } else {
            launchScreenContent
                .opacity(opacity)
                .onAppear { startLaunchAnimation() }
        }
    }

    private var launchScreenContent: some View {
        ZStack {
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: AppTheme.Spacing.large) {
                tileGrid

                Text("Learn More... Earn More")
                    .font(AppTheme.Typography.title1)
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    .textCase(.uppercase)
                    .tracking(2)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var tileGrid: some View {
        let tileSize: CGFloat = 110 // Half of 220pt total

        // Z-pattern order: TL(index 0), TR(index 1), BL(index 2), BR(index 3)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                tileCellView(assetName: "LaunchTile_TL", animationIndex: 0, size: tileSize)
                tileCellView(assetName: "LaunchTile_TR", animationIndex: 1, size: tileSize)
            }
            HStack(spacing: 0) {
                tileCellView(assetName: "LaunchTile_BL", animationIndex: 2, size: tileSize)
                tileCellView(assetName: "LaunchTile_BR", animationIndex: 3, size: tileSize)
            }
        }
    }

    private func tileCellView(assetName: String, animationIndex: Int, size: CGFloat) -> some View {
        Image(assetName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .rotation3DEffect(
                .degrees(tileRotations[animationIndex]),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.3
            )
    }

    private func startLaunchAnimation() {
        let flipDuration: Double = 0.8
        let staggerDelay: Double = 1.0
        let initialDelay: Double = 0.3

        for i in 0..<4 {
            let delay = initialDelay + Double(i) * staggerDelay

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: flipDuration)) {
                    tileRotations[i] = 360
                }
            }
        }

        // All flips done at: initialDelay + 3*stagger + flipDuration = 4.1s
        let allFlipsDone = initialDelay + 3 * staggerDelay + flipDuration

        DispatchQueue.main.asyncAfter(deadline: .now() + allFlipsDone + 0.4) {
            withAnimation(.easeOut(duration: 0.5)) {
                opacity = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + allFlipsDone + 0.9) {
            isLaunchComplete = true
        }
    }
}
