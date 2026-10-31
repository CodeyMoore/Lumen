import Foundation
import CoreMedia
import VideoToolbox

/// What this device's video hardware can handle.
enum DeviceCaps {
    /// False on A8 and older chips (iPhone 6, iPad mini 2/3/4, iPad Air 1/2).
    static let hevcHardwareDecode: Bool = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)

    static let modelIdentifier: String = {
        var info = utsname()
        uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        return mirror.children.reduce(into: "") { result, element in
            if let v = element.value as? Int8, v != 0 { result.append(Character(UnicodeScalar(UInt8(v)))) }
        }
    }()
}
