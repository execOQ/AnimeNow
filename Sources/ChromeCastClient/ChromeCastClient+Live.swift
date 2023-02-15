//
//  ChromeCastClient+Live.swift
//
//
//  Created by ErrorErrorError on 1/2/23.
//
//

import Foundation
import OpenCastSwift

public extension ChromeCastClient {
    static let liveValue: Self = {
        .init { scan in
            if scan {
                await CastActor.shared.scan()
            } else {
                await CastActor.shared.stopScan()
            }
        } scannedDevices: {
            .never
        }
    }()
}

@globalActor
private final actor CastActor {
    static let shared = CastActor()

    private let scanner = CastDeviceScanner()

    init() { }

    func scan() {
        scanner.startScanning()
    }

    func stopScan() {
        scanner.stopScanning()
    }
}

extension CastActor {
    final class Delegate: NSObject, CastDeviceScannerDelegate {
        var continuation: AsyncStream<ChromeCastClient.Action>.Continuation?

        func deviceDidComeOnline(_ device: CastDevice) {
            continuation?.yield(.deviceNowOnline(device.device))
        }

        func deviceDidChange(_ device: CastDevice) {
            continuation?.yield(.deviceDidChange(device.device))
        }

        func deviceDidGoOffline(_ device: CastDevice) {
            continuation?.yield(.deviceNowOffline(device.device))
        }
    }
}

private extension CastDevice {
    var device: ChromeCastClient.Device {
        .init(
            id: id,
            name: name
        )
    }
}
