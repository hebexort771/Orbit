import Foundation
import CoreAudio
import AudioToolbox

struct OutputDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let name: String
    let kind: OutputKind
}

/// Volumen y salida de audio del sistema (CoreAudio).
@MainActor
final class AudioService: ObservableObject {
    @Published private(set) var volume: Float = 0.5
    @Published private(set) var muted = false
    @Published private(set) var deviceName = ""
    @Published private(set) var output: OutputKind = .speaker
    @Published private(set) var canSetVolume = true

    /// Se llama cuando el volumen cambia (teclas, Centro de control, otra app…).
    var onChange: ((Float, Bool) -> Void)?

    private var deviceID = AudioObjectID(0)
    private var deviceBlock: AudioObjectPropertyListenerBlock?
    private var volumeBlock: AudioObjectPropertyListenerBlock?
    private var muteBlock: AudioObjectPropertyListenerBlock?
    private var quietUntil = Date.distantPast
    private let isDemo: Bool

    init(demo: Bool = false) {
        isDemo = demo
        if demo {
            volume = 0.56
            deviceName = "MacBook Air"
        }
    }

    func start() {
        guard !isDemo else { return }
        attachDefaultDevice()
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attachDefaultDevice() }
        }
        deviceBlock = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
    }

    // MARK: Lectura

    private func attachDefaultDevice() {
        detachListeners()
        deviceID = Self.defaultOutputDevice()
        deviceName = Self.name(of: deviceID) ?? ""
        output = OutputKind.guess(name: deviceName, bluetooth: Self.isBluetooth(deviceID))
        quietUntil = Date().addingTimeInterval(0.6)
        refresh(notify: false)

        var volumeAddress = Self.volumeAddress
        if AudioObjectHasProperty(deviceID, &volumeAddress) {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refresh(notify: true) }
            }
            volumeBlock = block
            AudioObjectAddPropertyListenerBlock(deviceID, &volumeAddress, DispatchQueue.main, block)
        }
        var muteAddress = Self.muteAddress
        if AudioObjectHasProperty(deviceID, &muteAddress) {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refresh(notify: true) }
            }
            muteBlock = block
            AudioObjectAddPropertyListenerBlock(deviceID, &muteAddress, DispatchQueue.main, block)
        }
    }

    private func detachListeners() {
        guard deviceID != 0 else { return }
        if let block = volumeBlock {
            var address = Self.volumeAddress
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)
        }
        if let block = muteBlock {
            var address = Self.muteAddress
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)
        }
        volumeBlock = nil
        muteBlock = nil
    }

    private func refresh(notify: Bool) {
        let newVolume = Self.readVolume(deviceID)
        let newMuted = Self.readMute(deviceID)
        canSetVolume = newVolume != nil
        let changed = (newVolume ?? volume) != volume || newMuted != muted
        volume = newVolume ?? volume
        muted = newMuted
        if notify && changed && Date() > quietUntil {
            onChange?(volume, muted)
        }
    }

    // MARK: Escritura

    func setVolume(_ value: Float) {
        let clamped = max(0, min(1, value))
        if isDemo { volume = clamped; return }
        var address = Self.volumeAddress
        var v = Float32(clamped)
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &v)
        if muted && clamped > 0 { setMuted(false) }
        volume = clamped
    }

    func setMuted(_ value: Bool) {
        if isDemo { muted = value; return }
        var address = Self.muteAddress
        guard AudioObjectHasProperty(deviceID, &address) else { return }
        var m = UInt32(value ? 1 : 0)
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m)
        muted = value
    }

    func toggleMute() { setMuted(!muted) }

    // MARK: Dispositivos de salida

    func outputDevices() -> [OutputDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard Self.hasOutputStreams(id), let name = Self.name(of: id) else { return nil }
            return OutputDevice(id: id, name: name, kind: OutputKind.guess(name: name, bluetooth: Self.isBluetooth(id)))
        }
    }

    var currentDeviceID: AudioObjectID { deviceID }

    func selectOutput(_ id: AudioObjectID) {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value = id
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                   UInt32(MemoryLayout<AudioObjectID>.size), &value)
    }

    // MARK: Utilidades CoreAudio

    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultOutputDevice() -> AudioObjectID {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    private static func readVolume(_ id: AudioObjectID) -> Float? {
        var address = volumeAddress
        guard id != 0, AudioObjectHasProperty(id, &address) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return Float(value)
    }

    private static func readMute(_ id: AudioObjectID) -> Bool {
        var address = muteAddress
        guard id != 0, AudioObjectHasProperty(id, &address) else { return false }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    private static func name(of id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value = name?.takeRetainedValue() else { return nil }
        return value as String
    }

    private static func isBluetooth(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return false }
        return value == kAudioDeviceTransportTypeBluetooth || value == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func hasOutputStreams(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return false }
        return size > 0
    }
}
