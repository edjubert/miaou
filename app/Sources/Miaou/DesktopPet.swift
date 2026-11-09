import AppKit
import Combine

enum DesktopPetScreenMode: String, CaseIterable {
    case primary
    case builtIn = "built-in"
    case both

    var label: String {
        switch self {
        case .primary: return L10n.t("desktopPet.screen.primary")
        case .builtIn: return L10n.t("desktopPet.screen.builtIn")
        case .both: return L10n.t("desktopPet.screen.both")
        }
    }

    func displays(from available: [DesktopPetDisplay],
                  primaryID: CGDirectDisplayID) -> [DesktopPetDisplay] {
        guard let primary = available.first(where: { $0.id == primaryID }) ?? available.first else {
            return []
        }
        let builtIn = available.first(where: \.isBuiltIn) ?? primary
        switch self {
        case .primary: return [primary]
        case .builtIn: return [builtIn]
        case .both: return primary.id == builtIn.id ? [primary] : [primary, builtIn]
        }
    }
}

/// Snapshot screen geometry so each companion keeps its own coordinate space.
struct DesktopPetDisplay {
    let id: CGDirectDisplayID
    let isBuiltIn: Bool
    /// Physical screen frame: the cat walks along its bottom edge, so its
    /// position is identical on every screen regardless of Dock or DPI.
    let frame: CGRect
    /// Visible frame (excludes menu bar and Dock): used for the speech bubble.
    let visibleFrame: CGRect
    let backingScaleFactor: CGFloat

    /// The strip along the physical bottom edge the cat walks on. Uses the
    /// physical frame, not the visible one, so the cat sits at the same
    /// edge on every screen regardless of Dock or DPI.
    var walkArea: CGRect { frame.insetBy(dx: 8, dy: 0) }

    static var available: [Self] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else { return nil }
            let id = number.uint32Value
            return Self(id: id, isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                        frame: screen.frame,
                        visibleFrame: screen.visibleFrame,
                        backingScaleFactor: screen.backingScaleFactor)
        }
    }
}

enum DesktopPetSize: String, CaseIterable {
    case small = "S"
    case medium = "M"
    case large = "L"

    var width: CGFloat {
        switch self {
        case .small: return 140
        case .medium: return 200
        case .large: return 280
        }
    }

    func dimensions(for pet: BarPet) -> CGSize {
        CGSize(width: width, height: width * pet.barWindow.height / pet.barWindow.width)
    }
}

/// Movement uses a monotonic clock, independently of drawing and mouse events.
struct DesktopPetMotion {
    /// Default walking speed, in points per second.
    static let walkingSpeed: CGFloat = 42
    static let hopDuration: TimeInterval = 0.3

    /// Current walking speed, in points per second; set from the user
    /// setting before each advance.
    var speed: CGFloat = Self.walkingSpeed

    private struct Hop {
        let startedAt: TimeInterval
        let startX: CGFloat
        let endX: CGFloat
        let height: CGFloat
    }

    private(set) var x: CGFloat = 0
    private(set) var direction: CGFloat = 1
    private(set) var verticalOffset: CGFloat = 0
    private(set) var isResting = true
    private var hop: Hop?
    private var wasHovered = false

    var isHopping: Bool { hop != nil }

    mutating func place(at x: CGFloat, direction: CGFloat = 1) {
        self.x = x
        self.direction = direction
        hop = nil
        verticalOffset = 0
        isResting = true
        wasHovered = false
    }

    mutating func translate(by offset: CGFloat) {
        x += offset
        if let hop {
            self.hop = Hop(startedAt: hop.startedAt, startX: hop.startX + offset,
                           endX: hop.endX + offset, height: hop.height)
        }
    }

    mutating func advance(at time: TimeInterval, elapsed: TimeInterval,
                          within limits: ClosedRange<CGFloat>, pointerOnLeft: Bool?,
                          petSize: CGSize, autonomous: Bool = false) {
        x = min(max(x, limits.lowerBound), limits.upperBound)
        let hovered = pointerOnLeft != nil
        let entered = hovered && !wasHovered
        defer { wasHovered = hovered }
        if entered, hop == nil, let pointerOnLeft {
            direction = pointerOnLeft ? 1 : -1
            let room = direction > 0 ? limits.upperBound - x : x - limits.lowerBound
            let otherRoom = limits.upperBound - limits.lowerBound - room
            // Near an edge, land inward instead of attempting a hop off-screen.
            if room < petSize.width && otherRoom > room { direction *= -1 }
            let target = min(max(x + direction * petSize.width, limits.lowerBound),
                             limits.upperBound)
            isResting = false
            hop = Hop(startedAt: time, startX: x, endX: target, height: petSize.height * 0.5)
        }
        if let hop {
            let progress = CGFloat(min(max((time - hop.startedAt) / Self.hopDuration, 0), 1))
            x = min(max(hop.startX + (hop.endX - hop.startX) * progress,
                        limits.lowerBound), limits.upperBound)
            verticalOffset = 4 * hop.height * progress * (1 - progress)
            guard time >= hop.startedAt + Self.hopDuration else { return }
            self.hop = nil
            verticalOffset = 0
            // Finish at the landing position, then resume walking on the next tick.
            return
        }
        if isResting && autonomous {
            isResting = false
        }
        guard !isResting else { return }
        guard limits.lowerBound < limits.upperBound else {
            isResting = true
            return
        }
        let next = x + direction * speed * min(max(elapsed, 0), 0.1)
        x = min(max(next, limits.lowerBound), limits.upperBound)
        if (direction < 0 && next <= limits.lowerBound) ||
            (direction > 0 && next >= limits.upperBound) {
            direction *= -1
            // Sleep at an edge only when no task is in progress; otherwise
            // turn around and keep walking.
            isResting = !autonomous
        }
    }
}

/// A separate, non-activating window lets the pet cross the desktop
/// without a widget background or an invisible rectangle eating clicks.
final class DesktopPetController {
    private let defaults = UserDefaults.standard
    private var observations: Set<AnyCancellable> = []
    private var companions: [CGDirectDisplayID: DesktopPetCompanion] = [:]
    private let speechSource = DesktopPetSpeechSource()
    private var speechPresentation = DesktopPetSpeechPresentation()
    private var speechSessions = DesktopPetSpeechSessions()
    private var nextSpeechPoll: TimeInterval = 0
    private var timer: Timer?
    private var previousTime: TimeInterval = 0

    func start() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateSettings() }
            .store(in: &observations)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateSettings() }
            .store(in: &observations)
        AppModel.shared.$dashboard
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateSettings() }
            .store(in: &observations)
        updateSettings()
    }

    func stop() {
        removeCompanions()
        observations.removeAll()
    }

    private func removeCompanions() {
        timer?.invalidate()
        timer = nil
        companions.values.forEach { $0.close() }
        companions.removeAll()
        speechPresentation.hide()
        speechSessions.reset()
        nextSpeechPoll = 0
    }

    /// The desktop pet has its own chaton/chonk choice, independent of the
    /// menu bar icon.
    static func pet(_ defaults: UserDefaults) -> BarPet {
        BarPet(rawValue: defaults.string(forKey: "desktopPetPet") ?? "") ?? .chaton
    }

    private var selectedPet: BarPet { Self.pet(defaults) }

    private func updateSettings() {
        guard defaults.bool(forKey: "desktopPetEnabled") else {
            removeCompanions()
            return
        }
        let selection = selectedPet
        let selectedSize = DesktopPetSize(
            rawValue: defaults.string(forKey: "desktopPetSize") ?? ""
        ) ?? .medium
        let mode = DesktopPetScreenMode(
            rawValue: defaults.string(forKey: "desktopPetScreens") ?? ""
        ) ?? .primary
        // NSScreen.main follows keyboard focus; CGMainDisplayID identifies
        // the primary display chosen in macOS display settings.
        let displays = mode.displays(from: DesktopPetDisplay.available, primaryID: CGMainDisplayID())
        guard !displays.isEmpty else {
            removeCompanions()
            return
        }
        let selectedIDs = Set(displays.map(\.id))
        for id in Array(companions.keys) where !selectedIDs.contains(id) {
            companions.removeValue(forKey: id)?.close()
        }
        for display in displays {
            if let companion = companions[display.id] {
                companion.configure(display: display, pet: selection, size: selectedSize)
            } else {
                companions[display.id] = DesktopPetCompanion(
                    display: display, pet: selection, size: selectedSize,
                    startingFraction: displays.count > 1 ? .random(in: 0.2...0.8) : 0.2,
                    direction: displays.count > 1 && Bool.random() ? -1 : 1
                )
            }
        }
        if timer == nil { previousTime = ProcessInfo.processInfo.systemUptime }
        tick()
        guard timer == nil else { return }
        let animation = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in self?.tick() }
        timer = animation
        RunLoop.main.add(animation, forMode: .common)
    }

    private func tick() {
        guard !companions.isEmpty else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = min(max(now - previousTime, 0), 0.1)
        previousTime = now
        // Poll the pointer without capturing mouse events: clicks continue
        // to pass through the companion to the desktop or window below.
        let pointer = NSEvent.mouseLocation
        let animationMode = ChatonAnimationMode(
            rawValue: defaults.string(forKey: "desktopPetAnimation") ?? ""
        ) ?? .session
        let autonomous = Self.autonomous(animationMode: animationMode,
                                          live: AppModel.shared.hasLiveSessions)
        let colorMode = Self.colorMode(defaults)
        let live = AppModel.shared.hasLiveSessions
        let speed = Self.speed(defaults)
        let glassTransparency = defaults.object(forKey: "desktopPetGlassTransparency") as? Double ?? 0
        // The speech bubble has its own glass intensity, full glass by default.
        let speechGlassTransparency = defaults.object(forKey: "desktopPetSpeechGlassTransparency") as? Double ?? 0
        let message = updateSpeech(at: now)
        for companion in companions.values {
            let bottomOffset = Self.bottomOffset(defaults, isBuiltIn: companion.isBuiltIn)
            companion.tick(at: now, elapsed: elapsed, pointer: pointer,
                           autonomous: autonomous, colorMode: colorMode, live: live,
                           bottomOffset: bottomOffset, speed: speed,
                           glassTransparency: glassTransparency)
            companion.showSpeech(message, glassTransparency: speechGlassTransparency)
        }
    }

    /// Whether the cat walks on its own: in "always" animation mode, or
    /// while a session is live.
    static func autonomous(animationMode: ChatonAnimationMode, live: Bool) -> Bool {
        animationMode == .always || live
    }

    /// Vertical offset of the cat from the screen's bottom edge, in points,
    /// per screen kind: the built-in and external displays can need
    /// different corrections. Negative values sink the cat below the edge.
    /// Falls back to the legacy global key when the per-kind key is absent.
    static func bottomOffset(_ defaults: UserDefaults, isBuiltIn: Bool) -> CGFloat {
        let key = isBuiltIn ? "desktopPetBottomOffsetBuiltIn" : "desktopPetBottomOffsetExternal"
        return CGFloat(defaults.object(forKey: key) as? Double
                       ?? defaults.object(forKey: "desktopPetBottomOffset") as? Double
                       ?? 0)
    }

    /// Walking speed in points per second, clamped to a sane range.
    static func speed(_ defaults: UserDefaults) -> CGFloat {
        let raw = defaults.object(forKey: "desktopPetSpeed") as? Double
            ?? Double(DesktopPetMotion.walkingSpeed)
        return CGFloat(min(max(raw, 1), 500))
    }

    /// The cat's color mode, migrating the legacy "color while moving"
    /// boolean: true meant brand colors, false meant grayscale.
    static func colorMode(_ defaults: UserDefaults) -> ChatonColorMode {
        if let raw = defaults.string(forKey: "desktopPetColorMode") {
            return ChatonColorMode(rawValue: raw) ?? .session
        }
        if let legacy = defaults.object(forKey: "desktopPetColorDuringSession") as? Bool {
            return legacy ? .color : .grayscale
        }
        return .session
    }

    /// Whether the cat renders in brand colors for this mode. In session
    /// mode the cat is colored while a session is live, and also while it
    /// moves (a hover-triggered hop and walk) even without a session.
    static func colored(mode: ChatonColorMode, live: Bool, resting: Bool) -> Bool {
        switch mode {
        case .color: return true
        case .grayscale: return false
        case .session: return live || !resting
        }
    }

    private func updateSpeech(at now: TimeInterval) -> DesktopPetMessage? {
        guard defaults.bool(forKey: "desktopPetSpeechEnabled") else {
            speechPresentation.hide()
            speechSessions.reset()
            nextSpeechPoll = 0
            return nil
        }
        let sessions = speechSessions.sessionsToRead(
            active: AppModel.shared.dashboard?.liveSessions ?? [], at: now
        )
        if now >= nextSpeechPoll {
            nextSpeechPoll = now + 2
            speechSource.refresh(sessions: sessions) { [weak self] messages in
                guard let self, !self.companions.isEmpty,
                      self.defaults.bool(forKey: "desktopPetSpeechEnabled") else { return }
                let time = ProcessInfo.processInfo.systemUptime
                let eligible = messages.filter { self.speechSessions.contains($0.sessionID, at: time) }
                self.speechPresentation.receive(eligible, at: time)
            }
        }
        return speechPresentation.visibleMessage(at: now)
    }
}

/// Each selected display has independent movement, hover detection and windows.
private final class DesktopPetCompanion {
    private var display: DesktopPetDisplay
    var isBuiltIn: Bool { display.isBuiltIn }
    private var pet: BarPet
    private var sizeClass: DesktopPetSize
    private let panel: DesktopPetPanel
    private var artwork: DesktopPetView
    private var motion = DesktopPetMotion()
    private var speechPanel: DesktopPetPanel?
    private var speechView: DesktopPetSpeechView?

    init(display: DesktopPetDisplay, pet: BarPet, size: DesktopPetSize,
         startingFraction: CGFloat, direction: CGFloat) {
        self.display = display
        self.pet = pet
        sizeClass = size
        let dimensions = size.dimensions(for: pet)
        artwork = DesktopPetView(pet: pet, size: dimensions,
                                 backingScaleFactor: display.backingScaleFactor)
        panel = DesktopPetPanel(contentRect: CGRect(origin: .zero, size: dimensions),
                                identifier: "miaou-desktop-pet-\(display.id)",
                                title: L10n.t("desktopPet.headline"))
        panel.contentView = artwork
        let area = display.walkArea
        let maxX = max(area.minX, area.maxX - dimensions.width)
        motion.place(at: area.minX + (maxX - area.minX) * startingFraction, direction: direction)
        panel.setFrameOrigin(CGPoint(x: motion.x,
                                     y: area.minY + DesktopPetController.bottomOffset(
                                         UserDefaults.standard, isBuiltIn: display.isBuiltIn)))
        panel.orderFrontRegardless()
    }

    func configure(display: DesktopPetDisplay, pet: BarPet, size: DesktopPetSize) {
        // A display can move in global coordinates when another is connected.
        // Preserve the current hop/walk on that display.
        motion.translate(by: display.frame.minX - self.display.frame.minX)
        self.display = display
        guard self.pet != pet || sizeClass != size else { return }
        self.pet = pet
        sizeClass = size
        let dimensions = size.dimensions(for: pet)
        artwork = DesktopPetView(pet: pet, size: dimensions,
                                 backingScaleFactor: display.backingScaleFactor)
        panel.contentView = artwork
        panel.setContentSize(dimensions)
    }

    func close() {
        panel.close()
        speechPanel?.close()
    }

    func tick(at now: TimeInterval, elapsed: TimeInterval, pointer: CGPoint,
              autonomous: Bool, colorMode: ChatonColorMode, live: Bool,
              bottomOffset: CGFloat, speed: CGFloat, glassTransparency: Double) {
        let area = display.walkArea
        let maxX = max(area.minX, area.maxX - panel.frame.width)
        let localPointer = CGPoint(x: pointer.x - panel.frame.minX,
                                   y: pointer.y - panel.frame.minY)
        let hovered = panel.frame.contains(pointer) && artwork.containsPet(at: localPointer)
        motion.speed = speed
        motion.advance(at: now, elapsed: elapsed, within: area.minX...maxX,
                       pointerOnLeft: hovered ? localPointer.x < panel.frame.width / 2 : nil,
                       petSize: panel.frame.size, autonomous: autonomous)
        let frame: Int
        var elevation = motion.verticalOffset
        if motion.isResting {
            frame = pet.restFrame
        } else {
            frame = artwork.walkFrame(at: now)
            if !motion.isHopping {
                elevation += CGFloat(abs(sin(now * .pi / 0.48))) * 1.5
            }
        }
        let scale = display.backingScaleFactor
        panel.setFrameOrigin(CGPoint(x: (motion.x * scale).rounded() / scale,
                                     y: ((area.minY + bottomOffset + elevation) * scale).rounded() / scale))
        artwork.show(frame: frame, mirrored: motion.direction < 0,
                     colored: DesktopPetController.colored(mode: colorMode, live: live,
                                                           resting: motion.isResting),
                     glassTransparency: glassTransparency)
    }

    func showSpeech(_ message: DesktopPetMessage?, glassTransparency: Double) {
        guard let message else {
            speechPanel?.orderOut(nil)
            return
        }
        let frame = DesktopPetSpeechView.frame(above: panel.frame, within: display.visibleFrame)
        if speechPanel == nil {
            let bubble = DesktopPetPanel(contentRect: frame,
                                         identifier: "miaou-desktop-speech-\(display.id)",
                                         title: L10n.t("desktopPet.speech"))
            bubble.hasShadow = true
            let view = DesktopPetSpeechView()
            bubble.contentView = view
            speechPanel = bubble
            speechView = view
        }
        // The bubble's border dots match the cat's pixels.
        let metrics = pet.dotMetrics(size: sizeClass.dimensions(for: pet),
                                     scale: display.backingScaleFactor)
        if let view = speechView {
            view.dotPitch = metrics.cell
            view.dotGap = metrics.gap
            view.backingScaleFactor = display.backingScaleFactor
        }
        speechPanel?.setFrame(frame, display: false)
        speechView?.tailX = panel.frame.midX - frame.minX
        speechView?.show(message, glassTransparency: glassTransparency)
        if speechPanel?.isVisible == false { speechPanel?.orderFrontRegardless() }
    }
}

private final class DesktopPetPanel: NSPanel {
    init(contentRect: CGRect, identifier: String, title: String) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        self.identifier = NSUserInterfaceItemIdentifier(identifier)
        self.title = title
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The companion and its speech bubble use the same native backdrop.
enum DesktopPetGlass {
    static func makeView() -> NSView {
        if #available(macOS 26.0, *) {
            let effect = NSGlassEffectView()
            effect.style = .clear
            effect.cornerRadius = 0
            return effect
        } else {
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            return effect
        }
    }

    static func apply(transparency: Double, to view: NSView) {
        let value = transparency.isFinite ? min(max(transparency, 0), 1) : 0
        let alpha = CGFloat(1 - value)
        if view.alphaValue != alpha { view.alphaValue = alpha }
        view.isHidden = value == 1
    }
}

/// Cache every pose once. Only window position updates at 30 fps;
/// the colored dots and glass mask change at the pet's 0.16 s cadence.
final class DesktopPetView: NSView {
    private struct Pose {
        let dots: [(rect: CGRect, row: Int)]
        let glass: CGPath
    }

    private let pet: BarPet
    private let poses: [Pose]
    private let walking: [Int]
    private let dots: DesktopPetDots
    private let glass: NSView
    private let mask = CAShapeLayer()
    private var shownFrame = -1
    private var shownMirrored = false

    init(pet: BarPet, size: CGSize, backingScaleFactor: CGFloat = 0) {
        self.pet = pet
        let frames = pet == .chonk ? Chonk.frames : Chaton.frames
        // Snap the vertical flip to the device grid so dot rows land on
        // whole device pixels like the columns do.
        let pixelHeight = backingScaleFactor > 0
            ? round(size.height * backingScaleFactor) / backingScaleFactor
            : size.height
        func native(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: pixelHeight - rect.maxY, width: rect.width, height: rect.height)
        }
        poses = frames.indices.map { index in
            let geometry = pet == .chonk
                ? Chonk.dotRects(frame: index, size: size, scale: backingScaleFactor)
                : Chaton.dotRects(frame: index, size: size, scale: backingScaleFactor)
            // Glass backdrop on the same snapped grid as the dots, clipped
            // to the dot outline so it never sticks out past the pet.
            let glass = pet == .chonk
                ? Chonk.glassRects(frame: index, size: size, scale: backingScaleFactor)
                : Chaton.glassRects(frame: index, size: size, scale: backingScaleFactor)
            let path = CGMutablePath()
            for rect in glass {
                path.addRect(native(rect))
            }
            return Pose(dots: geometry.map { (native($0.rect), $0.row) }, glass: path)
        }
        // Raised ears distinguish awake head poses in both recorded grids.
        let ears = pet == .chonk ? [Chonk.key((17, 0)), Chonk.key((21, 0))]
                                : [Chaton.key((15, 1)), Chaton.key((19, 1))]
        walking = frames.indices.filter { index in
            let keys = Set(frames[index].map { $0.col * 32 + $0.row })
            return index > 0 && Set(ears).isSubset(of: keys)
        }
        let dotView = DesktopPetDots()
        dots = dotView
        glass = DesktopPetGlass.makeView()
        super.init(frame: CGRect(origin: .zero, size: size))
        wantsLayer = true
        glass.frame = bounds
        glass.autoresizingMask = [.width, .height]
        glass.wantsLayer = true
        mask.frame = bounds
        glass.layer?.mask = mask
        dots.frame = bounds
        dots.autoresizingMask = [.width, .height]
        dots.gridHeight = pet.gridHeight
        addSubview(glass)
        // Keep colored dots outside the glass view so hiding the backdrop
        // never makes the outline disappear.
        addSubview(dots)
    }

    required init?(coder: NSCoder) { return nil }

    func walkFrame(at time: TimeInterval) -> Int {
        guard !walking.isEmpty else { return pet.restFrame }
        return walking[Int(time / PetAnimation.frameInterval) % walking.count]
    }

    func containsPet(at point: CGPoint) -> Bool {
        mask.path?.contains(point) ?? false
    }

    func show(frame: Int, mirrored: Bool, colored: Bool = false,
              glassTransparency: Double = 0) {
        DesktopPetGlass.apply(transparency: glassTransparency, to: glass)
        dots.colored = colored
        guard frame != shownFrame || mirrored != shownMirrored else { return }
        shownFrame = frame
        shownMirrored = mirrored
        let pose = poses[min(max(frame, 0), poses.count - 1)]
        var transform = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: bounds.width, ty: 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.path = mirrored ? pose.glass.copy(using: &transform) : pose.glass
        CATransaction.commit()
        dots.dots = pose.dots
        dots.mirrored = mirrored
        dots.needsDisplay = true
    }
}

private final class DesktopPetDots: NSView {
    var dots: [(rect: CGRect, row: Int)] = []
    var gridHeight = 10
    var mirrored = false
    var colored = false {
        didSet {
            if colored != oldValue { needsDisplay = true }
        }
    }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setShouldAntialias(false)
        if mirrored {
            context.translateBy(x: bounds.width, y: 0)
            context.scaleBy(x: -1, y: 1)
        }
        let palette = colored ? MistralLogo.brand : MistralLogo.grayscale
        for dot in dots {
            context.setFillColor(palette[min(4, dot.row * 5 / gridHeight)].cgColor)
            context.fill(dot.rect)
        }
    }
}
