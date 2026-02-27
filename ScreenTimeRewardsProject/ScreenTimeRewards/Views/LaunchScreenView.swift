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

    private let backFaceTexts = ["Br", "ain", "Co", "inz"]

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
                tileCellView(assetName: "LaunchTile_TL", backText: "Br", animationIndex: 0, size: tileSize, textAlignment: .trailing)
                tileCellView(assetName: "LaunchTile_TR", backText: "ain", animationIndex: 1, size: tileSize, textAlignment: .leading)
            }
            HStack(spacing: 0) {
                tileCellView(assetName: "LaunchTile_BL", backText: "Co", animationIndex: 2, size: tileSize, textAlignment: .trailing)
                tileCellView(assetName: "LaunchTile_BR", backText: "inz", animationIndex: 3, size: tileSize, textAlignment: .leading)
            }
        }
    }

    private func tileCellView(assetName: String, backText: String, animationIndex: Int, size: CGFloat, textAlignment: Alignment = .center) -> some View {
        let rotation = tileRotations[animationIndex]
        let showBack = rotation >= 90

        return ZStack {
            // Front face: the image tile
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .opacity(showBack ? 0 : 1)

            // Back face: the text label (pre-rotated 180° so it reads correctly when flipped)
            Text(backText)
                .font(.system(size: 44, weight: .black))
                .foregroundColor(AppTheme.brandedText(for: colorScheme))
                .frame(width: size, height: size, alignment: textAlignment)
                .rotation3DEffect(
                    .degrees(180),
                    axis: (x: 0, y: 1, z: 0)
                )
                .opacity(showBack ? 1 : 0)
        }
        .rotation3DEffect(
            .degrees(rotation),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.3
        )
    }

    private func startLaunchAnimation() {
        let flipDuration: Double = 0.4
        let staggerDelay: Double = 0.5
        let initialDelay: Double = 0.15

        for i in 0..<4 {
            let delay = initialDelay + Double(i) * staggerDelay

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: flipDuration)) {
                    tileRotations[i] = 180
                }
            }
        }

        // All flips done at: 0.15 + 3*0.5 + 0.4 = 2.05s
        let allFlipsDone = initialDelay + 3 * staggerDelay + flipDuration

        DispatchQueue.main.asyncAfter(deadline: .now() + allFlipsDone + 1.0) {
            withAnimation(.easeOut(duration: 0.8)) {
                opacity = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + allFlipsDone + 1.8) {
            isLaunchComplete = true
        }
    }
}
