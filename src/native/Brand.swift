// The look of the approved design in SwiftUI: its colour tokens for
// light and dark (the .pen variables), its three typefaces (Cinzel for the wordmark and the big
// buttons, Marcellus for headings, Alegreya Sans for text; all SIL OFL 1.1, in Resources/Fonts),
// the artwork (the ink stroke behind the header, one per theme, and the painting) and the small
// pieces built from them: the ink-tick headings, status pips, panels, the big crimson button,
// the toggle and the popup.
//
// Fonts and artwork are loaded from Brand.resources: the app's Resources, or GW2OM_RESOURCES
// (the headless renders, scripts/ui-render.swift).

import AppKit
import CoreText
import SwiftUI

enum Brand {
  // MARK: Colours (light, dark), the .pen variables

  static let bg = dynamic(0xF3EDE1, 0x14110E)
  static let bgRaised = dynamic(0xFBF8F1, 0x1C1814)
  static let surface = dynamic(0xE9E1D1, 0x241F19)
  static let border = dynamic(0xD4C8B2, 0x3A3229)
  static let borderStrong = dynamic(0xB4A68C, 0x55493B)
  static let fg = dynamic(0x1E1813, 0xF1E9DA)
  static let fg2 = dynamic(0x4E4337, 0xC2B6A0)
  static let fg3 = dynamic(0x776A58, 0x91856F)
  static let accent = dynamic(0x9E1F18, 0xD2402F)
  static let accentSoft = dynamic(0x9E1F18, 0xD2402F, alpha: (0x14, 0x24))
  static let accentDeep = dynamic(0x6E140F, 0x9E1F18)
  static let onAccent = Color(hex: 0xFFF8EE)
  static let gold = dynamic(0xA87A22, 0xE0B24E)
  static let goldSoft = dynamic(0xA87A22, 0xE0B24E, alpha: (0x18, 0x22))
  static let good = dynamic(0x3F7D3A, 0x6CC468)
  static let warning = dynamic(0x9A5900, 0xF0A040)
  static let jade = dynamic(0x1E7F6C, 0x47C2A8)

  // The header's fixed colours (on the ink, in both themes)
  static let headerText = Color(hex: 0xFFF8EE)
  static let headerShadow = Color(hex: 0x3A0805)
  static let goldRule = Color(hex: 0xF2D27A)
  static let badgeText = Color(hex: 0xF6E6C4)

  static func isDark(_ appearance: NSAppearance) -> Bool {
    let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
    return match == .darkAqua || match == .accessibilityHighContrastDarkAqua
  }

  private static func dynamic(_ light: UInt32, _ dark: UInt32, alpha: (UInt32, UInt32) = (0xFF, 0xFF)) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
      isDark(appearance)
        ? NSColor(hex: dark, alpha: Double(alpha.1) / 255)
        : NSColor(hex: light, alpha: Double(alpha.0) / 255)
    })
  }

  // MARK: Resources

  // Where Fonts/ and Art/ are: the app's Resources, or GW2OM_RESOURCES for the renders
  static let resources: URL = {
    if let dir = ProcessInfo.processInfo.environment["GW2OM_RESOURCES"], !dir.isEmpty {
      return URL(fileURLWithPath: dir)
    }
    return Bundle.main.resourceURL ?? URL(fileURLWithPath: ".")
  }()

  // The bundled typefaces, for this process only (no install, nothing systemwide). Once, before
  // the first window.
  @MainActor static func registerFonts() {
    guard !fontsRegistered else { return }
    fontsRegistered = true
    let dir = resources.appendingPathComponent("Fonts")
    let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    for url in urls where url.pathExtension == "ttf" {
      CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
  }
  @MainActor private static var fontsRegistered = false

  // The artwork (Resources/Art), decoded once
  @MainActor static func art(_ name: String) -> NSImage? {
    if let image = artCache[name] { return image }
    let image = NSImage(contentsOf: resources.appendingPathComponent("Art").appendingPathComponent(name))
    artCache[name] = image
    return image
  }
  @MainActor private static var artCache: [String: NSImage] = [:]
}

extension NSColor {
  convenience init(hex: UInt32, alpha: Double = 1) {
    self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
              blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
  }
}

extension Color {
  init(hex: UInt32, alpha: Double = 1) { self.init(nsColor: NSColor(hex: hex, alpha: alpha)) }
}

// MARK: - Type

extension Font {
  // Cinzel: the wordmark and the big buttons (caps)
  static func display(_ size: CGFloat) -> Font {
    .custom("CinzelRoman-Bold", fixedSize: size)
  }

  // Marcellus: headings
  static func head(_ size: CGFloat) -> Font {
    .custom("Marcellus-Regular", fixedSize: size)
  }

  // Alegreya Sans: everything else. It has no semibold: 600 in the design draws as Bold, as a
  // browser picks the next heavier face.
  enum BodyWeight { case regular, medium, semibold, bold }
  static func body(_ size: CGFloat, _ weight: BodyWeight = .regular) -> Font {
    switch weight {
    case .regular: .custom("AlegreyaSans-Regular", fixedSize: size)
    case .medium: .custom("AlegreyaSans-Medium", fixedSize: size)
    case .semibold, .bold: .custom("AlegreyaSans-Bold", fixedSize: size)
    }
  }
}

// Alegreya Sans's line box as the design draws it. The design tool sets it by the font's typo
// metrics (ascender 0.8, descender 0.2: a 1.0 em line, or the given line height with the extra
// split above and below); CoreText by its hhea metrics (0.9 + 0.3 = 1.2 em). This pads the
// difference away (negative padding shrinks the box), so heights and baselines match the design.
struct AlegreyaLineBox: ViewModifier {
  let size: CGFloat
  let lineHeight: CGFloat
  func body(content: Content) -> some View {
    content
      .lineSpacing(max(0, (lineHeight - 1.2) * size))
      .padding(.vertical, ((lineHeight - 1) / 2 - 0.1) * size)
  }
}

extension View {
  // after .font(.body(size, …)): the design's line box (1 = the font size, 1.3 for running text)
  func bodyBox(_ size: CGFloat, _ lineHeight: CGFloat = 1) -> some View {
    modifier(AlegreyaLineBox(size: size, lineHeight: lineHeight))
  }
}

// MARK: - Pieces

// The ink tick and a Marcellus title ("— This Mac"), with something optional on the right.
struct InkHeading<Trailing: View>: View {
  let title: String
  var size: CGFloat = 19
  var alignment: VerticalAlignment = .bottom
  @ViewBuilder var trailing: Trailing

  var body: some View {
    HStack(alignment: alignment) {
      HStack(spacing: 8) {
        RoundedRectangle(cornerRadius: 1.5).fill(Brand.accent).frame(width: 14, height: 3)
        Text(title)
          .font(.head(size))
          .foregroundStyle(Brand.fg)
          .lineLimit(1)
          .accessibilityAddTraits(.isHeader)
      }
      Spacer(minLength: 8)
      trailing
    }
  }
}

extension InkHeading where Trailing == EmptyView {
  init(_ title: String, size: CGFloat = 19) { self.init(title: title, size: size) { EmptyView() } }
}

// A small round pip in a state's colour
struct Pip: View {
  let color: Color
  var body: some View {
    Circle().fill(color).frame(width: 6, height: 6).accessibilityHidden(true)
  }
}

// A raised panel with a hairline border (r-panel 10)
extension View {
  func brandPanel(cornerRadius: CGFloat = 10) -> some View {
    self
      .background(Brand.bgRaised, in: .rect(cornerRadius: cornerRadius))
      .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Brand.border, lineWidth: 1))
  }
}

// The big crimson action: a red gradient, a dark rim and a soft shadow, Cinzel caps. Disabled:
// the surface colour with a hairline frame.
struct CrimsonButtonStyle: ButtonStyle {
  var height: CGFloat = 46
  var fontSize: CGFloat = 15
  var tracking: CGFloat = 1.5
  var top: UInt32 = 0xB0261D

  func makeBody(configuration: Configuration) -> some View {
    Face(configuration: configuration, style: self)
  }

  struct Face: View {
    let configuration: ButtonStyleConfiguration
    let style: CrimsonButtonStyle
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
      configuration.label
        .font(.display(style.fontSize))
        .tracking(style.tracking)
        .textCase(.uppercase)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .foregroundStyle(isEnabled ? Brand.onAccent : Brand.fg3)
        .frame(maxWidth: .infinity, minHeight: style.height, maxHeight: style.height)
        .background {
          RoundedRectangle(cornerRadius: 8)
            .fill(isEnabled
                  ? AnyShapeStyle(LinearGradient(colors: [Color(hex: style.top), Color(hex: 0x7A1510)],
                                                 startPoint: .top, endPoint: .bottom))
                  : AnyShapeStyle(Brand.surface))
            .shadow(color: isEnabled ? Color(hex: 0x6E140F, alpha: style.height > 50 ? 0x55 / 255 : 0x40 / 255) : .clear,
                    radius: style.height > 50 ? 4 : 3, y: style.height > 50 ? 3 : 2)
        }
        .overlay {
          RoundedRectangle(cornerRadius: 8)
            .strokeBorder(isEnabled ? Color(hex: 0x5A0E0A) : Brand.borderStrong, lineWidth: 1)
        }
        .brightness(isEnabled ? (configuration.isPressed ? -0.06 : hovered ? 0.04 : 0) : 0)
        .scaleEffect(configuration.isPressed ? 0.99 : 1)
        .animation(.snappy(duration: 0.15), value: configuration.isPressed)
        .onHover { hovered = $0 }
        .contentShape(.rect(cornerRadius: 8))
    }
  }
}

extension ButtonStyle where Self == CrimsonButtonStyle {
  static var crimson: CrimsonButtonStyle { CrimsonButtonStyle() }
  static var crimsonPlay: CrimsonButtonStyle { CrimsonButtonStyle(height: 54, fontSize: 17, tracking: 1.8, top: 0xB8291F) }
}

// A text-and-icon link button (Repair, Settings, Uninstall…, Cancel)
struct QuietButtonStyle: ButtonStyle {
  var color: Color = Brand.fg
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(color)
      .opacity(configuration.isPressed ? 0.6 : 1)
      .contentShape(.rect)
  }
}

// The design's switch: 38 x 22, the accent when on, a cream knob with a small shadow. (Not a
// ToggleStyle: a styled Toggle takes more width than its face on macOS.)
struct InkSwitch: View {
  @Binding var isOn: Bool
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    Button { isOn.toggle() } label: {
      ZStack(alignment: isOn ? .trailing : .leading) {
        Capsule().fill(isOn ? Brand.accent : Brand.borderStrong)
        Circle()
          .fill(Color(hex: 0xFFFDF8))
          .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
          .frame(width: 18, height: 18)
          .padding(2)
      }
      .frame(width: 38, height: 22)
      .opacity(isEnabled ? 1 : 0.45)
      .animation(.snappy(duration: 0.18), value: isOn)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(.isToggle)
    .accessibilityValue(isOn ? "On" : "Off")
  }
}

// The design's popup: the value in a small framed box with chevrons; a menu of the choices
struct InkPopup<Value: Hashable>: View {
  @Binding var selection: Value
  let options: [(Value, String)]
  @Environment(\.isEnabled) private var isEnabled

  private var title: String { options.first { $0.0 == selection }?.1 ?? "—" }

  var body: some View {
    Menu {
      ForEach(options, id: \.0) { value, label in
        Button { selection = value } label: {
          if value == selection { Label(label, systemImage: "checkmark") } else { Text(label) }
        }
      }
    } label: {
      PopupFace(title: title)
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .opacity(isEnabled ? 1 : 0.5)
  }
}

struct PopupFace: View {
  let title: String
  var body: some View {
    HStack(spacing: 8) {
      Text(title).font(.body(13, .semibold)).bodyBox(13).foregroundStyle(Brand.fg)
      LucideIcon(name: "chevrons-up-down", size: 13).foregroundStyle(Brand.fg3)
    }
    .padding(.leading, 10).padding(.trailing, 8).padding(.vertical, 4)
    .background(Brand.bg, in: .rect(cornerRadius: 6))
    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.borderStrong, lineWidth: 1))
  }
}

// The artwork as a view: an image cut to its frame like the design's "cover" fill
struct ArtImage: View {
  let name: String
  var body: some View {
    if let image = Brand.art(name) {
      Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
    } else {
      Color.clear
    }
  }
}
