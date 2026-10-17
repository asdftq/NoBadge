import CoreGraphics
import Foundation

public enum WindowPlacement {
  public static func centered(size: CGSize, in visibleFrame: CGRect) -> CGRect {
    let usable = visibleFrame.insetBy(dx: 16, dy: 16)
    let size = CGSize(width: min(size.width, usable.width), height: min(size.height, usable.height))
    return CGRect(
      x: usable.midX - size.width / 2, y: usable.midY - size.height / 2, width: size.width,
      height: size.height)
  }
  public static func fits(_ frame: CGRect, in visibleFrame: CGRect) -> Bool {
    visibleFrame.insetBy(dx: 4, dy: 4).contains(frame)
  }
}
