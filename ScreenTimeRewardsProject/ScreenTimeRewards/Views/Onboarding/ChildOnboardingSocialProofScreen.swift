import SwiftUI

/// Screen 5: Social Proof - Kid testimonials carousel
struct ChildOnboardingSocialProofScreen: View {
    @Environment(\.colorScheme) private var colorScheme

    let onContinue: () -> Void
    let onBack: () -> Void

    @State private var currentTestimonialIndex = 0
    @State private var timer: Timer?

    // Parent testimonials
    private let testimonials: [Testimonial] = [
        Testimonial(
            quote: "My 8-year-old asks to do Khan Academy now. I never thought I'd see that!",
            name: "Jennifer M.",
            location: "San Diego, CA"
        ),
        Testimonial(
            quote: "The daily battles are over. My kids actually enjoy learning now.",
            name: "Michael T.",
            location: "Austin, TX"
        ),
        Testimonial(
            quote: "Finally, screen time that doesn't make me feel guilty!",
            name: "Sarah L.",
            location: "Portland, OR"
        ),
        Testimonial(
            quote: "Game changer. My kids are reading 2 hours a day voluntarily.",
            name: "David K.",
            location: "Boston, MA"
        )
    ]

    var body: some View {
        ZStack {
            // Background
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress indicator
                OnboardingProgressIndicator(currentStep: 3)

                Spacer()
                    .frame(height: 40)

                // Headline
                VStack(spacing: 16) {
                    Text("You're Not Alone In This")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .multilineTextAlignment(.center)

                    // Social metrics
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            VStack(spacing: 4) {
                                Text("12,847")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(AppTheme.vibrantTeal)
                                Text("Families")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }

                            Divider()
                                .frame(height: 40)

                            VStack(spacing: 4) {
                                HStack(spacing: 4) {
                                    Text("4.8")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(AppTheme.sunnyYellow)
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(AppTheme.sunnyYellow)
                                }
                                Text("3,421 reviews")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 32)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(AppTheme.card(for: colorScheme))
                                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
                        )
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
                    .frame(height: 30)

                // Testimonial carousel
                TabView(selection: $currentTestimonialIndex) {
                    ForEach(Array(testimonials.enumerated()), id: \.offset) { index, testimonial in
                        testimonialCard(testimonial)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(height: 300)
                .padding(.horizontal, 16)

                Spacer()

                // Buttons
                VStack(spacing: 12) {
                    // Continue
                    Button(action: onContinue) {
                        Text("Set Up My System")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(AppTheme.vibrantTeal)
                            .cornerRadius(16)
                    }

                    // Back
                    Button(action: onBack) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            startAutoRotation()
        }
        .onDisappear {
            stopAutoRotation()
        }
    }

    // MARK: - Subviews

    private func testimonialCard(_ testimonial: Testimonial) -> some View {
        VStack(spacing: 20) {
            // Star rating
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 18))
                        .foregroundColor(AppTheme.sunnyYellow)
                }
            }

            // Quote
            VStack(spacing: 12) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 20))
                    .foregroundColor(AppTheme.vibrantTeal.opacity(0.5))

                Text(testimonial.quote)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .minimumScaleFactor(0.8)

                Image(systemName: "quote.closing")
                    .font(.system(size: 20))
                    .foregroundColor(AppTheme.vibrantTeal.opacity(0.5))
            }

            // Attribution
            VStack(spacing: 4) {
                Text("— \(testimonial.name)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                Text(testimonial.location)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: Color.black.opacity(0.1), radius: 16, x: 0, y: 8)
        )
        .padding(.horizontal, 8)
    }

    // MARK: - Auto-rotation Logic

    private func startAutoRotation() {
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                currentTestimonialIndex = (currentTestimonialIndex + 1) % testimonials.count
            }
        }
    }

    private func stopAutoRotation() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Models

private struct Testimonial {
    let quote: String
    let name: String
    let location: String
}

// MARK: - Preview
#Preview {
    ChildOnboardingSocialProofScreen(
        onContinue: { print("Continue") },
        onBack: { print("Back") }
    )
}
