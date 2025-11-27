import SwiftUI
import AVFoundation

/// App group identifier for shared settings
private let kAppGroupIdentifier = "group.com.dectalk.synthesizer"
private let kSPFSettingKey = "dectalk_spf_value"

struct ContentView: View {
    @StateObject private var viewModel = DECtalkViewModel()
    @State private var spfValue: Double = 100
    @State private var appGroupWorking: Bool = false

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: kAppGroupIdentifier)
    }

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

            // Voice Selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Available Voices")
                    .font(.headline)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 10) {
                    ForEach(viewModel.voices, id: \.identifier) { voice in
                        VoiceButton(
                            voice: voice,
                            isSelected: viewModel.selectedVoice?.identifier == voice.identifier
                        ) {
                            viewModel.selectVoice(voice)
                        }
                    }
                }
            }
            .padding(.horizontal)

            // Speed Factor (SPF)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Speed Factor (SPF)")
                        .font(.headline)
                    Spacer()
                    Text("\(Int(spfValue))")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Fast")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $spfValue, in: 50...200, step: 5)
                        .onChange(of: spfValue) { _, newValue in
                            saveSPFValue(Int(newValue))
                        }
                    Text("Slow")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Lower values = faster speech. Default is 100.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !appGroupWorking {
                    Text("Note: SPF requires Apple Developer account for app group support.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal)

            Divider()

            // Status
            VStack(spacing: 8) {
                HStack {
                    Circle()
                        .fill(viewModel.isAvailable ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(viewModel.isAvailable ? "DECtalk is available in System Settings" : "Run app to register voices")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !viewModel.statusMessage.isEmpty {
                    Text(viewModel.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

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
            .padding(.bottom)
        }
        .frame(width: 450, height: 550)
        .onAppear {
            viewModel.loadVoices()
            loadSPFValue()
        }
    }

    private func loadSPFValue() {
        // Test if app group is working by trying to write and read
        let testKey = "app_group_test"
        sharedDefaults?.set(true, forKey: testKey)
        appGroupWorking = sharedDefaults?.bool(forKey: testKey) == true

        let stored = sharedDefaults?.integer(forKey: kSPFSettingKey) ?? 0
        spfValue = stored > 0 ? Double(stored) : 100
    }

    private func saveSPFValue(_ value: Int) {
        sharedDefaults?.set(value, forKey: kSPFSettingKey)
    }
}

struct VoiceButton: View {
    let voice: DECtalkVoiceInfo
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: voice.icon)
                    .font(.title2)

                Text(voice.name)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
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
