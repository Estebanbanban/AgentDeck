import AudioToolbox
import CoreAudio
import Foundation

/// Fades music out while the mic is in use (FluidVoice dictation, calls) and back
/// in when it's released. Mechanism: CoreAudio listener on the default input's
/// isRunningSomewhere -> ramp the system output volume. Gated on music actually
/// playing, so dictating with no music does nothing.
final class MusicDucker {
    static let shared = MusicDucker()
    private let q = DispatchQueue(label: "agentdeck.ducker")          // state + volume ramps
    private let hookQ = DispatchQueue(label: "agentdeck.ducker.hook") // listener add/remove ONLY
    private var hooked: [AudioDeviceID] = [] // ALL input devices, not just the default:
    // dictation can record from a non-default mic (FluidVoice picks its own device)
    private var savedVolume: Float32?
    private var micWasOpen = false
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
        var listAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        // Re-hook when the device list changes (AirPods in/out). On hookQ, NEVER q:
        // RemovePropertyListenerBlock waits for in-flight listener blocks on the
        // listener's queue — calling it from that same queue deadlocks it, which
        // silently killed every scheduled restore (fade-out worked, no fade-in).
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &listAddr, hookQ) { [weak self] _, _ in
            self?.rehook()
        }
        hookQ.async { self.rehook() }
    }

    private func rehook() { // runs on hookQ; `hooked` itself is q-confined
        let old = q.sync { hooked }
        for d in old { AudioObjectRemovePropertyListenerBlock(d, &runningAddr, q, micListener) }
        let fresh = Self.inputDevices()
        for d in fresh { AudioObjectAddPropertyListenerBlock(d, &runningAddr, q, micListener) }
        q.async { self.hooked = fresh; self.micChanged() }
    }

    private var restoreTask: DispatchWorkItem?
    private var cycle = 0 // bumped by each duck; stale restore-completions no-op

    private func micChanged() {
        var open = false
        for d in hooked {
            var run: UInt32 = 0
            var sz = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(d, &runningAddr, 0, nil, &sz, &run) == noErr, run != 0 {
                open = true
                break
            }
        }
        guard open != micWasOpen else { return } // CoreAudio fires repeats; act on edges
        micWasOpen = open
        Notifier.log("ducker: mic \(open ? "OPEN" : "closed") vol=\(getVolume() ?? -1) saved=\(savedVolume ?? -1) playing=\(MusicWatcher.shared.playingNow)")
        open ? duck() : unduck()
    }

    private func duck() {
        restoreTask?.cancel(); restoreTask = nil
        cycle += 1
        guard !Config.duckOff, MusicWatcher.shared.playingNow else { return }
        // savedVolume is the TRUE pre-duck volume: set once per cycle, never
        // overwritten while ducked/restoring — a mic flap mid-fade must not
        // capture the ducked level as "original" (that left volume stuck low).
        if savedVolume == nil {
            guard let vol = getVolume(), vol > 0.02 else { return }
            savedVolume = vol
        }
        guard let base = savedVolume else { return }
        fade(from: getVolume() ?? base, to: 0) // full fade-out: silence while dictating
    }

    private func unduck() {
        guard let base = savedVolume else { return }
        let c = cycle
        // Debounce: FluidVoice can flap the mic; only restore if it stays closed.
        let task = DispatchWorkItem { [self] in
            Notifier.log("ducker: restoring to \(base)")
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

    private static func inputDevices() -> [AudioDeviceID] {
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
