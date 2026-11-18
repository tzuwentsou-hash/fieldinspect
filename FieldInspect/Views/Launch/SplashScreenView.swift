import SwiftUI

/// Branded launch splash view matching the native LaunchBackground (#0F172A) for a seamless transition.
struct SplashScreenView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isAppearing = false
    @State private var pulseRing = false
    @State private var scanProgress: CGFloat = 0

    var body: some View {
        ZStack {
            backgroundLayer

            blueprintGrid
                .opacity(isAppearing ? 1 : 0)

            VStack(spacing: 0) {
                Spacer()

                emblemSection

                Spacer()

                footerSection
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 36)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if reduceMotion {
                isAppearing = true
                scanProgress = 1
            } else {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.82)) {
                    isAppearing = true
                }
                withAnimation(.easeOut(duration: 2.7).delay(0.15)) {
                    scanProgress = 1
                }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    pulseRing = true
                }
            }
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    DesignSystem.Colors.backgroundDark,
                    DesignSystem.Colors.brandPrimary,
                    DesignSystem.Colors.backgroundDark
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    DesignSystem.Colors.brandAccent.opacity(0.18),
                    Color.clear
                ],
                center: .center,
                startRadius: 10,
                endRadius: 240
            )
            .offset(y: -40)
            .ignoresSafeArea()
        }
    }

    private var blueprintGrid: some View {
        Canvas { context, size in
            let step: CGFloat = 32
            var path = Path()
            for x in stride(from: 0, through: size.width, by: step) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 0, through: size.height, by: step) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.white.opacity(0.04)), lineWidth: 0.5)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var emblemSection: some View {
        VStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(DesignSystem.Colors.brandAccent.opacity(pulseRing ? 0.45 : 0.15), lineWidth: 1.5)
                    .frame(width: 128, height: 128)
                    .scaleEffect(pulseRing ? 1.06 : 0.98)

                Image("LaunchIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(.white.opacity(0.16), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 20, x: 0, y: 12)
            }
            .scaleEffect(isAppearing ? 1 : 0.88)
            .opacity(isAppearing ? 1 : 0)

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text(verbatim: "FieldInspect")
                        .font(.system(size: 32, weight: .bold, design: .default))
                        .tracking(-0.5)
                        .foregroundStyle(.white)

                    Text(verbatim: "AI")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            DesignSystem.Colors.brandAccent,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }

                Text("RESIDENTIAL INSPECTION SUITE")
                    .font(.caption.weight(.semibold))
                    .tracking(2.2)
                    .foregroundStyle(.white.opacity(0.62))
            }
            .offset(y: isAppearing ? 0 : 12)
            .opacity(isAppearing ? 1 : 0)
        }
    }

    private var footerSection: some View {
        VStack(spacing: 12) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.12))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    DesignSystem.Colors.brandAccent,
                                    Color(hex: 0xF59E0B)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * scanProgress)
                }
            }
            .frame(width: 140, height: 3.5)

            Text("InterNACHI® & ASHI® Ready")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .opacity(isAppearing ? 1 : 0)
    }
}

#Preview {
    SplashScreenView()
}
