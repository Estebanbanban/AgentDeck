import AudioToolbox
import CoreAudio
import Foundation

/// Fades music out while the mic is in use (FluidVoice dictation, calls) and back
/// in when it's released. Mechanism: CoreAudio listener on the default input's
/// isRunningSomewhere -> ramp the system output volume. Gated on music actually
/// playing, so dictating with no music does nothing.
final class MusicDucker {
    static let shared = MusicDucker()
    private let q = DispatchQueue(label: "agentdeck.ducker")
    private var inputDev: AudioDeviceID = 0
    private var savedVolume: Float32?
    private var fadeGen = 0 // bumping cancels an in-flight ramp

    private var runningAddr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    private var volAddr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private lazy var micListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.micChanged()
    }

    func start() {
        var defAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        // Follow default-input changes (AirPods in/out) by re-hooking the listener.
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defAddr, q) { [weak self] _, _ in
            self?.rehook()
        }
        q.async { self.rehook() }
    }

    private func rehook() {
        if inputDev != 0 { AudioObjectRemovePropertyListenerBlock(inputDev, &runningAddr, q, micListener) }
        inputDev = Self.defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        guard inputDev != 0 else { return }
        AudioObjectAddPropertyListenerBlock(inputDev, &runningAddr, q, micListener)
    }

    private var restoreTask: DispatchWorkItem?
    private var cycle = 0 // bumped by each duck; stale restore-completions no-op

    private func micChanged() {
        var run: UInt32 = 0
        var sz = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(inputDev, &runningAddr, 0, nil, &sz, &run) == noErr else { return }
        Notifier.log("ducker: mic \(run != 0 ? "OPEN" : "closed") dev=\(inputDev) vol=\(getVolume() ?? -1) saved=\(savedVolume ?? -1)")
        run != 0 ? duck() : unduck()
    }

    private func duck() {
        restoreTask?.cancel(); restoreTask = nil
        cycle += 1
        guard !Config.duckOff, MusicWatcher.shared.now?.playing == true else { return }
        // savedVolume is the TRUE pre-duck volume: set once per cycle, never
        // overwritten while ducked/restoring — a mic flap mid-fade must not
        // capture the ducked level as "original" (that left volume stuck low).
        if savedVolume == nil {
            guard let vol = getVolume(), vol > 0.02 else { return }
            savedVolume = vol
        }
        guard let base = savedVolume else { return }
        fade(from: getVolume() ?? base, to: base * 0.12)
    }

    private func unduck() {
        guard let base = savedVolume else { return }
        let c = cycle
        // Debounce: FluidVoice can flap the mic; only restore if it stays closed.
        let task = DispatchWorkItem { [self] in
            fade(from: getVolume() ?? 0, to: base)
            q.asyncAfter(deadline: .now() + .milliseconds(500)) { [self] in
                if cycle == c { savedVolume = nil } // ramp landed, cycle over
            }
        }
        restoreTask = task
        q.asyncAfter(deadline: .now() + .milliseconds(250), execute: task)
    }

    private func fade(from: Float32, to: Float32) {
        fadeGen += 1
        let gen = fadeGen
        for i in 1...8 {
            q.asyncAfter(deadline: .now() + .milliseconds(i * 50)) { [self] in
                guard gen == fadeGen else { return }
                setVolume(from + (to - from) * Float32(i) / 8)
            }
        }
    }

    private func getVolume() -> Float32? {
        let dev = Self.defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        guard dev != 0 else { return nil }
        var v: Float32 = 0
        var sz = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(dev, &volAddr, 0, nil, &sz, &v) == noErr else { return nil }
        return v
    }

    private func setVolume(_ v: Float32) {
        let dev = Self.defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        guard dev != 0 else { return }
        var vol = max(0, min(1, v))
        AudioObjectSetPropertyData(dev, &volAddr, 0, nil, UInt32(MemoryLayout<Float32>.size), &vol)
    }

    private static func defaultDevice(_ sel: AudioObjectPropertySelector) -> AudioDeviceID {
        var addr = AudioObjectPropertyAddress(
            mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dev = AudioDeviceID(0)
        var sz = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &sz, &dev)
        return dev
    }
}
