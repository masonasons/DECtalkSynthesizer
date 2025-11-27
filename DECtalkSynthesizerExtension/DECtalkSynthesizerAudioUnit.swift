import AVFoundation
import AudioToolbox
import CoreMedia
import OSLog
import Accelerate

fileprivate let log = Logger(subsystem: "com.dectalk.synthesizer", category: "AudioUnit")

/// Default SPF value (hardcoded since app group preferences are disabled)
private let kDefaultSPFValue = 100

/// DECtalk Speech Synthesis Provider Audio Unit
/// Provides DECtalk text-to-speech synthesis as a system-wide speech synthesizer
public class DECtalkSynthesizerAudioUnit: AVSpeechSynthesisProviderAudioUnit {

    // MARK: - Audio Bus Properties

    /// Output bus for audio data
    private var outputBus: AUAudioUnitBus
    private var _outputBusses: AUAudioUnitBusArray!

    /// Audio format (22050 Hz, 32-bit float, mono) - system expects Float format
    private let audioFormat: AVAudioFormat

    // MARK: - Synthesis Properties

    /// Audio buffer for synthesis output
    private var output: [Float32] = []
    private var outputOffset: Int = 0
    private let outputMutex = DispatchSemaphore(value: 1)

    /// Current voice identifier
    private var currentVoiceIdentifier: String = "com.dectalk.voice.paul"

    // MARK: - Voice Definitions

    /// Map of voice identifiers to DECtalk voice indices
    private static let voiceMap: [String: Int32] = [
        "com.dectalk.voice.paul": 0,
        "com.dectalk.voice.betty": 1,
        "com.dectalk.voice.harry": 2,
        "com.dectalk.voice.frank": 3,
        "com.dectalk.voice.dennis": 4,
        "com.dectalk.voice.kit": 5,
        "com.dectalk.voice.ursula": 6,
        "com.dectalk.voice.rita": 7,
        "com.dectalk.voice.wendy": 8
    ]

    /// Default pitch (Hz) for each voice - from DECtalk documentation
    private static let voiceBasePitch: [String: Int] = [
        "com.dectalk.voice.paul": 122,
        "com.dectalk.voice.betty": 208,
        "com.dectalk.voice.harry": 89,
        "com.dectalk.voice.frank": 155,
        "com.dectalk.voice.dennis": 110,
        "com.dectalk.voice.kit": 296,
        "com.dectalk.voice.ursula": 240,
        "com.dectalk.voice.rita": 106,
        "com.dectalk.voice.wendy": 200
    ]

    /// All available DECtalk voices
    private static let allVoices: [AVSpeechSynthesisProviderVoice] = [
        AVSpeechSynthesisProviderVoice(name: "Paul (DECtalk)", identifier: "com.dectalk.voice.paul",
                                        primaryLanguages: ["en-US"], supportedLanguages: ["en-US", "en-GB"]),
        AVSpeechSynthesisProviderVoice(name: "Betty (DECtalk)", identifier: "com.dectalk.voice.betty",
                                        primaryLanguages: ["en-US"], supportedLanguages: ["en-US", "en-GB"]),
        AVSpeechSynthesisProviderVoice(name: "Harry (DECtalk)", identifier: "com.dectalk.voice.harry",
                                        primaryLanguages: ["en-US"], supportedLanguages: ["en-US", "en-GB"]),
        AVSpeechSynthesisProviderVoice(name: "Frank (DECtalk)", identifier: "com.dectalk.voice.frank",
                                        primaryLanguages: ["en-US"], supportedLanguages: ["en-US", "en-GB"]),
        AVSpeechSynthesisProviderVoice(name: "Dennis (DECtalk)", identifier: "com.dectalk.voice.dennis",
                                        primaryLanguages: ["en-US"], supportedLanguages: ["en-US", "en-GB"]),
        AVSpeechSynthesisProviderVoice(name: "Kit (DECtalk)", identifier: "com.dectalk.voice.kit",
                                        primaryLanguages: ["en-US"], supportedLanguages: ["en-US", "en-GB"]),
        AVSpeechSynthesisProviderVoice(name: "Ursula (DECtalk)", identifier: "com.dectalk.voice.ursula",
                                        primaryLanguages: ["en-US"], supportedLanguages: ["en-US", "en-GB"]),
        AVSpeechSynthesisProviderVoice(name: "Rita (DECtalk)", identifier: "com.dectalk.voice.rita",
                                        primaryLanguages: ["en-US"], supportedLanguages: ["en-US", "en-GB"]),
        AVSpeechSynthesisProviderVoice(name: "Wendy (DECtalk)", identifier: "com.dectalk.voice.wendy",
                                        primaryLanguages: ["en-US"], supportedLanguages: ["en-US", "en-GB"])
    ]

    // MARK: - Initialization

    @objc
    public override init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions = []) throws {

        // Set up audio format: 22050 Hz, 32-bit float, mono, non-interleaved
        let basicDescription = AudioStreamBasicDescription(
            mSampleRate: 22050,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        audioFormat = AVAudioFormat(cmAudioFormatDescription: try CMAudioFormatDescription(audioStreamBasicDescription: basicDescription))
        outputBus = try AUAudioUnitBus(format: audioFormat)

        try super.init(componentDescription: componentDescription, options: options)

        _outputBusses = AUAudioUnitBusArray(audioUnit: self,
                                             busType: .output,
                                             busses: [outputBus])

        // Initialize DECtalk engine
        let result = dectalk_init()
        if result != Int32(DECtalkErrorNone.rawValue) {
            log.warning("DECtalk engine initialization deferred (error: \(result, privacy: .public))")
        }
    }

    deinit {
        dectalk_shutdown()
    }

    // MARK: - Bus Configuration

    public override var outputBusses: AUAudioUnitBusArray {
        return _outputBusses
    }

    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()
    }

    // MARK: - AVSpeechSynthesisProviderAudioUnit Overrides

    /// Provides the list of available voices to the system
    public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
        get { Self.allVoices }
        set { /* Ignored */ }
    }

    // MARK: - Render Implementation

    private func performRender(
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timestamp: UnsafePointer<AudioTimeStamp>,
        frameCount: AUAudioFrameCount,
        outputBusNumber: Int,
        outputAudioBufferList: UnsafeMutablePointer<AudioBufferList>,
        renderEvents: UnsafePointer<AURenderEvent>?,
        renderPull: AURenderPullInputBlock?
    ) -> AUAudioUnitStatus {
        let unsafeBuffer = UnsafeMutableAudioBufferListPointer(outputAudioBufferList)
        let frames = unsafeBuffer[0].mData!.assumingMemoryBound(to: Float32.self)
        frames.assign(repeating: 0, count: Int(frameCount))

        outputMutex.wait()
        let count = min(output.count - outputOffset, Int(frameCount))

        if count > 0 {
            output.withUnsafeBufferPointer { ptr in
                frames.assign(from: ptr.baseAddress!.advanced(by: outputOffset), count: count)
            }
            outputAudioBufferList.pointee.mBuffers.mDataByteSize = UInt32(count * MemoryLayout<Float32>.size)
        }

        outputOffset += count
        if outputOffset >= output.count {
            actionFlags.pointee = .offlineUnitRenderAction_Complete
            output.removeAll()
            outputOffset = 0
        }
        outputMutex.signal()

        return noErr
    }

    public override var internalRenderBlock: AUInternalRenderBlock { performRender }

    /// Called when the system wants to synthesize speech
    public override func synthesizeSpeechRequest(_ speechRequest: AVSpeechSynthesisProviderRequest) {
        // Get the voice from the request
        currentVoiceIdentifier = speechRequest.voice.identifier

        // Set the DECtalk voice
        if let voiceIndex = Self.voiceMap[currentVoiceIdentifier] {
            dectalk_set_voice(DECtalkVoice(rawValue: UInt32(voiceIndex)))
        }

        // Parse SSML and extract text with prosody commands
        let ssml = speechRequest.ssmlRepresentation
        let (plainText, dectalkCommands) = parseSSML(ssml)

        // Use default SPF value (app group preferences disabled to avoid permission dialogs)
        let spfValue = kDefaultSPFValue
        let spfCommand = "[:spf \(spfValue)]"

        // Estimate buffer size based on text length
        // Roughly 150 words per minute at 11025 Hz = ~4400 samples per word
        // Average word is ~5 chars, so ~880 samples per character
        // Add 50% headroom for pauses and commands
        // Adjust for SPF - lower SPF means faster speech, so less audio
        let spfFactor = Double(spfValue) / 100.0
        let estimatedSamples = max(11025, min(11025 * 60, Int(Double(plainText.count * 1300) * spfFactor)))

        // Create audio buffer for DECtalk output (11025 Hz, 16-bit)
        var dectalkBuffer = [Int16](repeating: 0, count: estimatedSamples)
        var samplesWritten: Int32 = 0

        // Prepend SPF and DECtalk commands to text
        let fullText = spfCommand + dectalkCommands + plainText

        log.info("Synthesizing: \(fullText.prefix(200), privacy: .public)")

        // Synthesize the text
        let result = dectalk_synthesize(
            fullText,
            &dectalkBuffer,
            Int32(estimatedSamples),
            &samplesWritten
        )

        if result == Int32(DECtalkErrorNone.rawValue) && samplesWritten > 0 {
            // Convert DECtalk 11025 Hz 16-bit to 22050 Hz 32-bit float
            let floatSamples = resampleAudioFast(dectalkBuffer, sampleCount: Int(samplesWritten))

            outputMutex.wait()
            output = floatSamples
            outputOffset = 0
            outputMutex.signal()
        } else {
            outputMutex.wait()
            output.removeAll()
            outputOffset = 0
            outputMutex.signal()
        }
    }

    /// Cancel any ongoing speech synthesis
    public override func cancelSpeechRequest() {
        outputMutex.wait()
        output.removeAll()
        outputOffset = 0
        dectalk_reset()
        outputMutex.signal()
    }

    // MARK: - SSML Parsing

    /// Parse SSML and extract text with DECtalk prosody commands
    private func parseSSML(_ ssml: String) -> (text: String, commands: String) {
        var commands = ""
        var rate: Double?
        var pitch: Double?
        var volume: Double?

        // Log the raw SSML for debugging
        log.info("Raw SSML: \(ssml.prefix(500), privacy: .public)")

        // Parse prosody attributes from SSML
        // Rate: x-slow, slow, medium, fast, x-fast, or percentage
        if let rateMatch = ssml.range(of: #"rate="([^"]+)""#, options: .regularExpression) {
            let rateValue = String(ssml[rateMatch]).replacingOccurrences(of: "rate=\"", with: "").dropLast()
            rate = parseRate(String(rateValue))
            log.info("Parsed rate: \(rateValue, privacy: .public) -> \(rate ?? 0, privacy: .public)")
        }

        // Pitch: x-low, low, medium, high, x-high, or percentage/Hz
        if let pitchMatch = ssml.range(of: #"pitch="([^"]+)""#, options: .regularExpression) {
            let pitchValue = String(ssml[pitchMatch]).replacingOccurrences(of: "pitch=\"", with: "").dropLast()
            pitch = parsePitch(String(pitchValue))
            log.info("Parsed pitch: \(pitchValue, privacy: .public) -> \(pitch ?? 0, privacy: .public)")
        }

        // Volume: silent, x-soft, soft, medium, loud, x-loud, or percentage/dB
        if let volumeMatch = ssml.range(of: #"volume="([^"]+)""#, options: .regularExpression) {
            let volumeValue = String(ssml[volumeMatch]).replacingOccurrences(of: "volume=\"", with: "").dropLast()
            volume = parseVolume(String(volumeValue))
            log.info("Parsed volume: \(volumeValue, privacy: .public) -> \(volume ?? 0, privacy: .public)")
        }

        // Build DECtalk commands
        // Rate: DECtalk uses words per minute, range 75-650, default ~180
        if let r = rate {
            let wpm = Int(180.0 * r)
            let clampedWpm = max(75, min(650, wpm))
            commands += "[:rate \(clampedWpm)]"
        }

        // Pitch: DECtalk uses absolute Hz values for baseline pitch
        // Default varies by voice (Paul 122Hz, Betty 208Hz, etc.)
        // We use [:dv ap N] where N is absolute pitch in Hz
        // DECtalk pitch range: 50-350 Hz
        if let p = pitch, p > 0 {
            // p is a multiplier (1.0 = normal, 2.0 = double, 0.5 = half)
            // Get the base pitch for the current voice
            let basePitch = Double(Self.voiceBasePitch[currentVoiceIdentifier] ?? 122)
            let newPitch = Int(basePitch * p)
            // Clamp to DECtalk's valid pitch range (50-350 Hz)
            let clampedPitch = max(50, min(350, newPitch))
            let pitchCmd = "[:dv ap \(clampedPitch)]"
            commands += pitchCmd
            log.info("Generated pitch command: \(pitchCmd, privacy: .public) (base: \(Int(basePitch), privacy: .public)Hz, mult: \(p, privacy: .public))")
        }

        // Volume: DECtalk uses 0-100 scale
        if let v = volume {
            let vol = Int(v * 100.0)
            let clampedVol = max(0, min(100, vol))
            commands += "[:volume set \(clampedVol)]"
        }

        // Process SSML elements (break, emphasis, say-as) by converting to DECtalk inline commands
        var processedSSML = ssml
        processedSSML = processBreakElements(processedSSML)
        processedSSML = processEmphasisElements(processedSSML)
        processedSSML = processSayAsElements(processedSSML)

        // Extract plain text from SSML
        var buffer = [CChar](repeating: 0, count: processedSSML.utf8.count * 2 + 1)
        processedSSML.withCString { ssmlPtr in
            _ = dectalk_extract_text_from_ssml(ssmlPtr, &buffer, Int32(buffer.count))
        }
        var plainText = String(cString: buffer)

        // Fix DECtalk commands that got mangled by SSML processing
        // The system strips '[' from '[:command]', leaving ':command]'
        // We need to reconstruct these back to proper DECtalk format
        plainText = reconstructDECtalkCommands(plainText)

        return (plainText, commands)
    }

    // MARK: - SSML Element Processing

    /// Process <break> elements and convert to DECtalk pause commands
    /// Supports: time="500ms", time="1s", strength="weak|medium|strong|x-strong"
    private func processBreakElements(_ ssml: String) -> String {
        var result = ssml

        // Match <break .../> or <break ...></break>
        let breakPattern = #"<break\s+([^>]*?)\s*/?>(?:</break>)?"#

        guard let regex = try? NSRegularExpression(pattern: breakPattern, options: [.caseInsensitive]) else {
            return result
        }

        let matches = regex.matches(in: result, options: [], range: NSRange(result.startIndex..., in: result))

        // Process matches in reverse order to preserve string positions
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result),
                  let attrRange = Range(match.range(at: 1), in: result) else { continue }

            let attributes = String(result[attrRange])
            var pauseMs = 250 // Default pause

            // Check for time attribute (e.g., time="500ms" or time="1s")
            if let timeMatch = attributes.range(of: #"time="([^"]+)""#, options: .regularExpression) {
                let timeValue = String(attributes[timeMatch])
                    .replacingOccurrences(of: "time=\"", with: "")
                    .dropLast()
                pauseMs = parseTimeToMs(String(timeValue))
            }
            // Check for strength attribute
            else if let strengthMatch = attributes.range(of: #"strength="([^"]+)""#, options: .regularExpression) {
                let strength = String(attributes[strengthMatch])
                    .replacingOccurrences(of: "strength=\"", with: "")
                    .dropLast()
                    .lowercased()

                switch strength {
                case "none": pauseMs = 0
                case "x-weak": pauseMs = 100
                case "weak": pauseMs = 150
                case "medium": pauseMs = 300
                case "strong": pauseMs = 500
                case "x-strong": pauseMs = 1000
                default: pauseMs = 250
                }
            }

            // Replace with DECtalk pause command
            // DECtalk uses [:pause N] where N is milliseconds
            let replacement = pauseMs > 0 ? " [:pause \(pauseMs)] " : ""
            result.replaceSubrange(range, with: replacement)
        }

        return result
    }

    /// Process <emphasis> elements and convert to DECtalk commands
    /// Supports: level="strong|moderate|reduced|none"
    private func processEmphasisElements(_ ssml: String) -> String {
        var result = ssml

        // Match <emphasis level="...">text</emphasis>
        let emphasisPattern = #"<emphasis(?:\s+level="([^"]*)")?\s*>(.*?)</emphasis>"#

        guard let regex = try? NSRegularExpression(pattern: emphasisPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return result
        }

        let matches = regex.matches(in: result, options: [], range: NSRange(result.startIndex..., in: result))

        // Process matches in reverse order
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let contentRange = Range(match.range(at: 2), in: result) else { continue }

            let content = String(result[contentRange])
            var level = "moderate" // Default

            if match.range(at: 1).location != NSNotFound,
               let levelRange = Range(match.range(at: 1), in: result) {
                level = String(result[levelRange]).lowercased()
            }

            // Convert emphasis to DECtalk commands
            // Use combination of rate and pitch changes for emphasis
            var replacement: String
            switch level {
            case "none":
                // No emphasis - just the text
                replacement = content
            case "reduced":
                // Softer, slower
                replacement = "[:rate -20][:dv ap -2]\(content)[:rate +20][:dv ap +2]"
            case "moderate":
                // Slightly louder and higher pitch
                replacement = "[:dv ap +3]\(content)[:dv ap -3]"
            case "strong":
                // Slower, louder, higher pitch
                replacement = "[:rate -30][:dv ap +5]\(content)[:rate +30][:dv ap -5]"
            default:
                replacement = content
            }

            result.replaceSubrange(fullRange, with: replacement)
        }

        return result
    }

    /// Process <say-as> elements for special pronunciation
    /// Supports: interpret-as="date|time|telephone|characters|ordinal|cardinal"
    private func processSayAsElements(_ ssml: String) -> String {
        var result = ssml

        // Match <say-as interpret-as="...">text</say-as>
        let sayAsPattern = #"<say-as\s+interpret-as="([^"]+)"(?:\s+format="([^"]+)")?\s*>(.*?)</say-as>"#

        guard let regex = try? NSRegularExpression(pattern: sayAsPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return result
        }

        let matches = regex.matches(in: result, options: [], range: NSRange(result.startIndex..., in: result))

        // Process matches in reverse order
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let typeRange = Range(match.range(at: 1), in: result),
                  let contentRange = Range(match.range(at: 3), in: result) else { continue }

            let interpretAs = String(result[typeRange]).lowercased()
            let content = String(result[contentRange])

            var format: String? = nil
            if match.range(at: 2).location != NSNotFound,
               let formatRange = Range(match.range(at: 2), in: result) {
                format = String(result[formatRange])
            }

            let replacement = convertSayAs(content: content, interpretAs: interpretAs, format: format)
            result.replaceSubrange(fullRange, with: replacement)
        }

        return result
    }

    /// Convert say-as content to speakable text
    private func convertSayAs(content: String, interpretAs: String, format: String?) -> String {
        switch interpretAs {
        case "characters", "spell-out":
            // Spell out each character with pauses
            return content.map { char in
                if char.isLetter {
                    return "\(char) [:pause 100]"
                } else if char.isNumber {
                    return "\(char) [:pause 100]"
                } else if char == " " {
                    return "[:pause 200] space [:pause 200]"
                } else {
                    return "\(char) [:pause 100]"
                }
            }.joined()

        case "cardinal", "number":
            // Just pass through - DECtalk handles numbers well
            return content

        case "ordinal":
            // Convert number to ordinal (e.g., 1 -> first)
            return convertToOrdinal(content)

        case "telephone":
            // Read phone number digit by digit with grouping
            return formatTelephone(content)

        case "date":
            // Format date appropriately
            return formatDate(content, format: format)

        case "time":
            // Format time appropriately
            return formatTime(content)

        case "currency":
            // Read currency values
            return formatCurrency(content)

        case "fraction":
            // Read as fraction
            return formatFraction(content)

        default:
            return content
        }
    }

    /// Convert a number string to ordinal words
    private func convertToOrdinal(_ text: String) -> String {
        guard let number = Int(text.trimmingCharacters(in: .whitespaces)) else {
            return text
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: number)) ?? text
    }

    /// Format telephone number for speaking
    private func formatTelephone(_ text: String) -> String {
        // Extract just digits
        let digits = text.filter { $0.isNumber }

        // Format with pauses between groups
        var result = ""
        for (index, digit) in digits.enumerated() {
            result += "\(digit) "
            // Add longer pause after area code (3 digits) and exchange (3 more)
            if index == 2 || index == 5 {
                result += "[:pause 200]"
            } else {
                result += "[:pause 80]"
            }
        }
        return result
    }

    /// Format date for speaking
    private func formatDate(_ text: String, format: String?) -> String {
        // Try to parse common date formats
        let dateFormatters = [
            "yyyy-MM-dd",
            "MM/dd/yyyy",
            "dd/MM/yyyy",
            "MMMM d, yyyy",
            "MMM d, yyyy"
        ]

        for formatString in dateFormatters {
            let formatter = DateFormatter()
            formatter.dateFormat = formatString
            if let date = formatter.date(from: text) {
                // Output in a speakable format
                let outputFormatter = DateFormatter()
                outputFormatter.dateStyle = .long
                return outputFormatter.string(from: date)
            }
        }

        // If we can't parse, return as-is
        return text
    }

    /// Format time for speaking
    private func formatTime(_ text: String) -> String {
        // Try to parse time formats
        let timeFormatters = ["HH:mm", "H:mm", "hh:mm a", "h:mm a"]

        for formatString in timeFormatters {
            let formatter = DateFormatter()
            formatter.dateFormat = formatString
            if let date = formatter.date(from: text) {
                let outputFormatter = DateFormatter()
                outputFormatter.dateFormat = "h:mm a"
                return outputFormatter.string(from: date)
            }
        }

        return text
    }

    /// Format currency for speaking
    private func formatCurrency(_ text: String) -> String {
        // Extract number and format
        let cleaned = text.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")

        if let amount = Double(cleaned) {
            let dollars = Int(amount)
            let cents = Int((amount - Double(dollars)) * 100)

            if cents > 0 {
                return "\(dollars) dollars and \(cents) cents"
            } else {
                return "\(dollars) dollars"
            }
        }

        return text
    }

    /// Format fraction for speaking
    private func formatFraction(_ text: String) -> String {
        // Handle formats like "1/2", "3/4"
        let parts = text.split(separator: "/")
        if parts.count == 2,
           let numerator = Int(parts[0]),
           let denominator = Int(parts[1]) {

            let denominatorWord: String
            switch denominator {
            case 2: denominatorWord = numerator == 1 ? "half" : "halves"
            case 3: denominatorWord = numerator == 1 ? "third" : "thirds"
            case 4: denominatorWord = numerator == 1 ? "quarter" : "quarters"
            case 5: denominatorWord = numerator == 1 ? "fifth" : "fifths"
            case 6: denominatorWord = numerator == 1 ? "sixth" : "sixths"
            case 8: denominatorWord = numerator == 1 ? "eighth" : "eighths"
            case 10: denominatorWord = numerator == 1 ? "tenth" : "tenths"
            default:
                let ordinal = convertToOrdinal("\(denominator)")
                denominatorWord = numerator == 1 ? ordinal : "\(ordinal)s"
            }

            return "\(numerator) \(denominatorWord)"
        }

        return text
    }

    /// Parse time string to milliseconds
    private func parseTimeToMs(_ value: String) -> Int {
        let trimmed = value.trimmingCharacters(in: .whitespaces).lowercased()

        if trimmed.hasSuffix("ms") {
            if let ms = Int(trimmed.dropLast(2)) {
                return ms
            }
        } else if trimmed.hasSuffix("s") {
            if let s = Double(trimmed.dropLast()) {
                return Int(s * 1000)
            }
        }

        // Default
        return 250
    }

    /// Reconstruct DECtalk commands that were mangled by SSML processing
    /// Converts ':command]' back to '[:command]'
    private func reconstructDECtalkCommands(_ text: String) -> String {
        var result = text

        // Comprehensive list of DECtalk commands
        // Voice commands: np, nb, nh, nf, nd, nk, nu, nr, nw
        // Control commands: rate, volume, pitch, period, comma, punct, tone, log, error
        // Phoneme/pronunciation: phoneme, say, pronounce, name
        // Timing: sync, index, skip
        // Special modes: mode, dial, email, latin
        // Singing: play, note (for singing mode)
        // Voice parameters: dv (define voice parameters)
        let pattern = #"(^|\s)(:(?:rate|volume|pitch|np|nb|nh|nf|nd|nk|nu|nr|nw|dv|phoneme|punct|tone|comma|period|log|error|index|sync|play|dial|mode|say|skip|email|latin|name|note|pronounce|pp|cp|design|gender|breath|head|smooth|richness|lx|hs|f4|b4|f5|b5|lo|speed|pause)[^\]]*\])"#

        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range,
                                                      withTemplate: "$1[$2")
        }

        return result
    }

    /// Parse SSML rate value to multiplier (1.0 = normal)
    private func parseRate(_ value: String) -> Double {
        switch value.lowercased() {
        case "x-slow": return 0.5
        case "slow": return 0.75
        case "medium": return 1.0
        case "fast": return 1.5
        case "x-fast": return 2.0
        default:
            // Handle percentage like "150%" or relative like "+50%"
            if value.hasSuffix("%") {
                let numStr = value.dropLast()
                if let num = Double(numStr) {
                    return num / 100.0
                }
            }
            return 1.0
        }
    }

    /// Parse SSML pitch value to multiplier (1.0 = normal)
    /// macOS pitch slider appears to use: 50% = normal, 0% = low, 100% = high
    private func parsePitch(_ value: String) -> Double {
        switch value.lowercased() {
        case "x-low": return 0.5
        case "low": return 0.75
        case "medium": return 1.0
        case "high": return 1.25
        case "x-high": return 1.5
        default:
            // Handle percentage - macOS uses 0-100% where 50% = normal
            // 0% = lowest pitch, 50% = normal, 100% = highest
            if value.hasSuffix("%") {
                let numStr = value.dropLast()
                if let num = Double(numStr) {
                    // Map 0-100% to multiplier where 50% = 1.0
                    // 0% -> 0.0, 50% -> 1.0, 100% -> 2.0
                    return num / 50.0
                }
            }
            // Handle Hz values (rough conversion)
            if value.lowercased().hasSuffix("hz") {
                let numStr = value.dropLast(2)
                if let hz = Double(numStr) {
                    // Assume 150 Hz is "normal"
                    return hz / 150.0
                }
            }
            return 1.0
        }
    }

    /// Parse SSML volume value to multiplier (1.0 = normal)
    private func parseVolume(_ value: String) -> Double {
        switch value.lowercased() {
        case "silent": return 0.0
        case "x-soft": return 0.25
        case "soft": return 0.5
        case "medium": return 0.75
        case "loud": return 1.0
        case "x-loud": return 1.0
        default:
            // Handle percentage or dB
            if value.hasSuffix("%") {
                let numStr = value.dropLast()
                if let num = Double(numStr) {
                    return num / 100.0
                }
            }
            if value.lowercased().hasSuffix("db") {
                let numStr = value.dropLast(2)
                if let db = Double(numStr) {
                    // Convert dB to linear
                    return pow(10.0, db / 20.0)
                }
            }
            return 1.0
        }
    }

    // MARK: - Audio Resampling

    /// Fast resampling using vDSP - optimized for low latency
    /// Convert DECtalk 11025 Hz 16-bit audio to 22050 Hz 32-bit float
    private func resampleAudioFast(_ samples: [Int16], sampleCount: Int) -> [Float32] {
        guard sampleCount > 0 else { return [] }

        let outputCount = sampleCount * 2
        var upsampled = [Float32](repeating: 0, count: outputCount)

        // Convert and upsample in a single pass for better cache performance
        let scale: Float32 = 1.0 / 32768.0

        samples.withUnsafeBufferPointer { inputPtr in
            upsampled.withUnsafeMutableBufferPointer { outputPtr in
                // Process in chunks for better cache utilization
                for i in 0..<sampleCount {
                    let s1 = Float32(inputPtr[i]) * scale
                    let outputIndex = i * 2

                    // Original sample
                    outputPtr[outputIndex] = s1

                    // Linear interpolation for the midpoint (fast)
                    if i + 1 < sampleCount {
                        let s2 = Float32(inputPtr[i + 1]) * scale
                        outputPtr[outputIndex + 1] = (s1 + s2) * 0.5
                    } else {
                        outputPtr[outputIndex + 1] = s1
                    }
                }
            }
        }

        return upsampled
    }

    /// High-quality resampling using Catmull-Rom interpolation
    /// Convert DECtalk 11025 Hz 16-bit audio to 22050 Hz 32-bit float
    private func resampleAudio(_ samples: [Int16], sampleCount: Int) -> [Float32] {
        guard sampleCount > 0 else { return [] }

        // Convert Int16 to Float32 (normalized to -1.0 to 1.0)
        let floatSamples = vDSP.integerToFloatingPoint(
            Array(samples.prefix(sampleCount)),
            floatingPointType: Float.self
        )
        let normalized = vDSP.multiply(Float(1.0 / 32768.0), floatSamples)

        // Upsample 2x from 11025 Hz to 22050 Hz using polyphase FIR filter
        // This is a 4-tap Catmull-Rom spline interpolation for smooth results
        let outputCount = sampleCount * 2
        var upsampled = [Float32](repeating: 0, count: outputCount)

        for i in 0..<sampleCount {
            let outputIndex = i * 2

            // Get surrounding samples for interpolation (with boundary handling)
            let s0 = i > 0 ? normalized[i - 1] : normalized[0]
            let s1 = normalized[i]
            let s2 = i + 1 < sampleCount ? normalized[i + 1] : normalized[sampleCount - 1]
            let s3 = i + 2 < sampleCount ? normalized[i + 2] : normalized[sampleCount - 1]

            // Original sample
            upsampled[outputIndex] = s1

            // Catmull-Rom interpolation at t=0.5 (midpoint)
            // P(t) = 0.5 * ((2*s1) + (-s0 + s2)*t + (2*s0 - 5*s1 + 4*s2 - s3)*t^2 + (-s0 + 3*s1 - 3*s2 + s3)*t^3)
            // At t=0.5:
            let t: Float = 0.5
            let t2 = t * t
            let t3 = t2 * t

            let a0 = -s0 + 3.0 * s1 - 3.0 * s2 + s3
            let a1 = 2.0 * s0 - 5.0 * s1 + 4.0 * s2 - s3
            let a2 = -s0 + s2
            let a3 = 2.0 * s1

            let interpolated = 0.5 * (a3 + a2 * t + a1 * t2 + a0 * t3)
            upsampled[outputIndex + 1] = interpolated
        }

        // Apply a gentle low-pass filter to remove any interpolation artifacts
        // Simple 3-tap moving average on the interpolated samples only
        for i in stride(from: 1, to: outputCount - 1, by: 2) {
            let prev = upsampled[i - 1]
            let curr = upsampled[i]
            let next = upsampled[i + 1]
            upsampled[i] = 0.25 * prev + 0.5 * curr + 0.25 * next
        }

        return upsampled
    }
}
