import SwiftUI

/// Flat vector of a wall-mounted split unit; airflow lines appear while running.
struct ACIllustration: View {
    let isOn: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: h * 0.14)
                    .fill(LinearGradient(colors: [.white, Color(white: 0.82)], startPoint: .top, endPoint: .bottom))
                    .frame(width: w, height: h * 0.62)
                    .shadow(color: .white.opacity(isOn ? 0.18 : 0.05), radius: 8)
                // Air outlet
                Capsule()
                    .fill(Color(white: 0.25))
                    .frame(width: w * 0.86, height: h * 0.07)
                    .offset(y: h * 0.48)
                // Status LED
                Circle()
                    .fill(isOn ? Theme.accent : Color(white: 0.6))
                    .frame(width: 4, height: 4)
                    .offset(x: w * 0.38, y: h * 0.32)
                if isOn {
                    HStack(spacing: w * 0.12) {
                        ForEach(0..<4, id: \.self) { _ in
                            Capsule().fill(Theme.accent.opacity(0.35)).frame(width: 2, height: h * 0.28)
                        }
                    }
                    .offset(y: h * 0.68)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut, value: isOn)
        }
    }
}
