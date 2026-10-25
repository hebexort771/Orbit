// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Orbit",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Orbit",
            path: "Sources/Orbit",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("EventKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("QuickLookThumbnailing")
            ]
        )
    ]
)
