// SetupView.swift
// MacPilot — MacPilotHelper

import SwiftUI
import SharedCore

struct SetupView: View {
    @State private var currentStep: SetupStep = .welcome

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image("BrandLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                    )

                Image(systemName: currentStep.icon)
                    .font(.system(size: 34))
                    .foregroundStyle(.blue.gradient)
                    .symbolEffect(.bounce, value: currentStep)
            }

            Text(currentStep.title)
                .font(.title.bold())

            Text(currentStep.subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            // Action Button
            Button(action: advanceStep) {
                Text(currentStep.buttonTitle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .frame(width: 480, height: 400)
    }

    private func advanceStep() {
        withAnimation {
            currentStep = currentStep.next
        }
    }
}

// MARK: - Setup Steps

enum SetupStep: Int, CaseIterable {
    case welcome
    case permissions
    case pairing
    case complete

    var title: String {
        switch self {
        case .welcome:     return "MacPilot'a Hoş Geldiniz"
        case .permissions: return "İzinler"
        case .pairing:     return "Cihaz Eşleştirme"
        case .complete:    return "Hazır!"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:     return "Mac'inizi iPhone'dan güvenli şekilde kontrol edin."
        case .permissions: return "MacPilot'un mouse ve klavye kontrolü için Accessibility iznine ihtiyacı var."
        case .pairing:     return "iPhone'unuzla eşleştirmek için QR kodu tarayın."
        case .complete:    return "MacPilotAgent arka planda çalışıyor. iPhone'unuzdan bağlanabilirsiniz."
        }
    }

    var icon: String {
        switch self {
        case .welcome:     return "desktopcomputer"
        case .permissions: return "lock.shield"
        case .pairing:     return "qrcode"
        case .complete:    return "checkmark.circle"
        }
    }

    var buttonTitle: String {
        switch self {
        case .welcome:     return "Başla"
        case .permissions: return "İzin Ver"
        case .pairing:     return "Eşleştir"
        case .complete:    return "Kapat"
        }
    }

    var next: SetupStep {
        let allCases = SetupStep.allCases
        let nextIndex = min(rawValue + 1, allCases.count - 1)
        return allCases[nextIndex]
    }
}

#Preview {
    SetupView()
}
