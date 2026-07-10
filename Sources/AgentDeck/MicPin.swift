import CoreAudio
import Foundation

/// Keeps the SYSTEM default input on the built-in mic. macOS re-selects AirPods
/// as default input on every connect; any app recording from them (FluidVoice
/// follows — and persists — the system default) flips Bluetooth into HFP, which
/// degrades and stalls music playback system-wide. Pinning the default to the
/// built-in mic prevents the whole class of problem; AirPods stay output-only.
/// Settings toggle: "micPinOff". Apps can still pick the AirPods mic explicitly.
final class MicPin {
    static let shared = MicPin()
    private let q = DispatchQueue(label: "agentdeck.micpin")

    func start() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, q) { [weak self] _, _ in
            self?.enforce()
        }
        q.async { self.enforce() }
    }

    private func enforce() {
        guard !Config.micPinOff else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var current = AudioDeviceID(0)
        var sz = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &sz, &current) == noErr,
              current != 0, isBluetooth(current), var builtIn = builtInMic()
        else { return }
        let ok = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                            UInt32(MemoryLayout<AudioDeviceID>.size), &builtIn)
        Notifier.log("micpin: default input was BT dev \(current) -> built-in \(builtIn) (\(ok == noErr ? "ok" : "err \(ok)"))")
    }

    private func isBluetooth(_ dev: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var t: UInt32 = 0
        var sz = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &sz, &t) == noErr else { return false }
        return t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE
    }

    private func builtInMic() -> AudioDeviceID? {
        for dev in inputDevices() {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var t: UInt32 = 0
            var sz = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(dev, &addr, 0, nil, &sz, &t) == noErr,
               t == kAudioDeviceTransportTypeBuiltIn { return dev }
        }
        return nil
    }

    private func inputDevices() -> [AudioDeviceID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var sz: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &sz) == noErr
        else { return [] }
        var devs = [AudioDeviceID](repeating: 0, count: Int(sz) / MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &sz, &devs)
        return devs.filter { d in
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var s: UInt32 = 0
            return AudioObjectGetPropertyDataSize(d, &a, 0, nil, &s) == noErr && s > 8
        }
    }
}
