import Foundation

enum BuildDistribution {
  #if NOBADGE_SOURCE_BUILD
    static let isSourceBuild = true
  #else
    static let isSourceBuild = false
  #endif

  static let sourceURL = URL(string: "https://github.com/asdftq/NoBadge")!
  static let websiteURL = URL(string: "https://www.asdftq.com/nobadge/")!
}
