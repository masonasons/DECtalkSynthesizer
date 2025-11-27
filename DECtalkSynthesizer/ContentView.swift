import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                Text("DECtalk Synthesizer")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Classic speech synthesis for macOS")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top)

            Divider()

            // Instructions
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Setup Instructions")
                        .font(.headline)

                    Text("1. Run this app to register DECtalk voices with the system")
                    Text("2. Go to System Settings → Accessibility → Spoken Content")
                    Text("3. Click 'System Voice' and select a DECtalk voice")
                    Text("4. Use Option+Escape to speak selected text anywhere")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Spacer()

            Text("DECtalk voices are now available in System Settings")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom)
        }
        .frame(width: 400, height: 350)
    }
}

struct SettingsView: View {
    var body: some View {
        Form {
            Text("DECtalk Synthesizer Settings")
                .font(.headline)

            Text("Voice settings can be configured in System Settings → Accessibility → Spoken Content")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 400, height: 200)
    }
}

#Preview {
    ContentView()
}
