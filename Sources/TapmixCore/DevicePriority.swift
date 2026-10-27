import Foundation

/// Decides when a preferred output device should become the system default.
public enum DevicePriority {
    public static func outputDeviceToActivate(
        preferredUID: String?,
        currentUID: String?,
        availableUIDs: Set<String>,
        newlyAvailable: Set<String>
    ) -> String? {
        guard let preferredUID,
              availableUIDs.contains(preferredUID),
              preferredUID != currentUID,
              newlyAvailable.contains(preferredUID)
        else { return nil }
        return preferredUID
    }
}
