"""Expose the installed WidgetKit host-background preference to this local build.

Apple's Batteries widget imports preferredBackgroundStyle(.blur). The symbols
are exported by WidgetKit and its SDK linker stub, but omitted from the public
Swift interface. Extend a build-local copy; never change the installed SDK.
This internal API can change with macOS releases.
"""
from pathlib import Path
import platform
import subprocess

sdk = Path(subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip())
architecture = platform.machine()
sdk_architecture = "arm64e" if architecture == "arm64" else architecture
source = sdk / f"System/Library/Frameworks/WidgetKit.framework/Versions/A/Modules/WidgetKit.swiftmodule/{sdk_architecture}-apple-macos.swiftinterface"
interface = source.read_text()
if "public enum WidgetBackgroundStyle" not in interface:
    interface += """
@available(macOS 14.0, *)
public enum WidgetBackgroundStyle {
  case opaque
  case blur
  case transparent
}
@available(macOS 14.0, *)
extension SwiftUI.WidgetConfiguration {
  public func preferredBackgroundStyle(_ style: WidgetKit.WidgetBackgroundStyle) -> some SwiftUI.WidgetConfiguration
}
"""
destination = Path("build/background-api/WidgetKit.swiftmodule")
destination.mkdir(parents=True, exist_ok=True)
(destination / f"{architecture}-apple-macos.swiftinterface").write_text(interface)
