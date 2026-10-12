// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HomeWidgets",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "HomeWidgets",
            path: "Sources/HomeWidgets",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("EventKit"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("UserNotifications"),
            ]
        )
    ]
)
