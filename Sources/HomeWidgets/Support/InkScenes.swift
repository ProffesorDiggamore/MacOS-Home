import CoreGraphics

/// Sumi-e ink paintings: lotus in a pond and peaks fading into mist.
enum InkScenes {
    // MARK: - Lotus

    static func lotus(_ canvas: InkCanvas, _ dice: Dice) {
        let (w, h, u) = (canvas.width, canvas.height, canvas.unit)
        let noise = Noise1D(dice)

        // Ripples along the bottom.
        for _ in 0..<dice.int(6, 12) {
            let y = h * dice.range(0.86, 0.98)
            let x = w * dice.range(0, 1)
            let length = dice.range(40, 220) * u
            let points = SketchRenderer.line(CGPoint(x: x, y: y), CGPoint(x: x + length, y: y + dice.range(-3, 3) * u), steps: 20)
            canvas.pen(SketchRenderer.wobble(points, amount: 1.5 * u, frequency: 0.3, noise: noise, phase: dice.range(0, 99)),
                       width: dice.range(0.8, 1.6) * u, alpha: dice.range(0.15, 0.35))
        }

        // Leaves further back in the pond: soft and pale.
        if let ghost = canvas.layer() {
            for _ in 0..<dice.int(4, 7) {
                let rx = dice.range(120, 260) * u
                let center = CGPoint(x: w * dice.range(0.02, 0.98), y: h * dice.range(0.25, 0.75))
                for layer in 0..<4 {
                    let scale = 1 - 0.15 * CGFloat(layer)
                    ghost.polygon(leafOutline(center, rx: rx * scale, ry: rx * 0.35 * scale, turn: dice.range(-0.3, 0.3), noise: noise,
                                              phase: dice.range(0, 400)), alpha: 0.2)
                }
                ghost.brush(SketchRenderer.line(CGPoint(x: center.x, y: center.y), CGPoint(x: center.x + dice.range(-40, 40) * u, y: h * 1.05), steps: 12),
                            width: { _ in 3.5 * u }, alpha: 0.6)
            }
            canvas.paste(ghost, blur: 7 * u, alpha: 0.35)
        }

        // Stems, each ending in a leaf, a bud, a flower or a seed pod, leaving room for the poem.
        let right = dice.chance(0.6)
        let (from, span): (CGFloat, CGFloat) = right ? (0.04, 0.76) : (0.2, 0.76)
        let count = dice.int(8, 12)
        var tops: [(point: CGPoint, kind: Int, lean: CGFloat)] = []
        for i in 0..<count {
            let x0 = w * (from + span * (CGFloat(i) + 0.5) / CGFloat(count) + dice.range(-0.04, 0.04))
            let topX = min(w * (from + span), max(w * from, x0 + dice.range(-0.1, 0.1) * w))
            let top = CGPoint(x: topX, y: h * dice.range(0.2, 0.7))
            let bend = dice.range(-60, 60) * u
            let points = SketchRenderer.smooth([
                CGPoint(x: x0, y: h * 1.04),
                CGPoint(x: x0 + (top.x - x0) * 0.35 + bend, y: h * 1.04 + (top.y - h * 1.04) * 0.35),
                CGPoint(x: x0 + (top.x - x0) * 0.75 - bend * 0.5, y: h * 1.04 + (top.y - h * 1.04) * 0.75),
                top,
            ], steps: 14)
            let thick = dice.range(3.2, 5) * u
            canvas.brush(points, width: { t in thick * (1 - 0.3 * t) }, alpha: 0.88)
            // Little prickles along the stem.
            var k = dice.int(4, 10)
            while k < points.count - 2 {
                let p = points[k]
                canvas.dot(CGPoint(x: p.x + (k % 2 == 0 ? 1 : -1) * thick * 0.7, y: p.y), radius: dice.range(0.8, 1.6) * u, alpha: 0.8)
                k += dice.int(5, 9)
            }
            let roll = dice.next()
            let kind = roll < 0.55 ? 0 : roll < 0.72 ? 1 : roll < 0.88 ? 2 : 3
            tops.append((top, kind, (top.x - x0) / max(1, h)))
        }

        // Leaves: layered washes that bleed a little, with pale veins and a dry rim.
        if let wash = canvas.layer() {
            var leaves: [(center: CGPoint, rx: CGFloat, ry: CGFloat, turn: CGFloat, phase: CGFloat)] = []
            for top in tops where top.kind == 0 {
                let rx = dice.range(110, 230) * u
                let leaf = (center: CGPoint(x: top.point.x, y: top.point.y - rx * 0.06), rx: rx, ry: rx * dice.range(0.22, 0.5),
                            turn: dice.range(-0.3, 0.3) + top.lean * 0.5, phase: dice.range(0, 400))
                leaves.append(leaf)
                for layer in 0..<5 {
                    let scale = 1 - 0.13 * CGFloat(layer)
                    let outline = leafOutline(leaf.center, rx: leaf.rx * scale, ry: leaf.ry * scale, turn: leaf.turn,
                                              noise: noise, phase: leaf.phase + CGFloat(layer) * 7)
                    wash.polygon(outline, alpha: dice.range(0.14, 0.22))
                }
                wash.polygon(leafOutline(CGPoint(x: leaf.center.x + leaf.rx * 0.1, y: leaf.center.y + leaf.ry * 0.1), rx: leaf.rx * 0.45,
                                         ry: leaf.ry * 0.5, turn: leaf.turn, noise: noise, phase: leaf.phase + 50), alpha: 0.2)
            }
            canvas.paste(wash, blur: 2.5 * u)
            for leaf in leaves {
                let hub = CGPoint(x: leaf.center.x, y: leaf.center.y + leaf.ry * 0.12)
                let edge = leafOutline(leaf.center, rx: leaf.rx * 0.9, ry: leaf.ry * 0.9, turn: leaf.turn, noise: noise, phase: leaf.phase)
                let veins = dice.int(10, 15)
                for v in 0..<veins {
                    let tip = edge[(v * edge.count / veins + dice.int(0, 3)) % edge.count]
                    let mid = CGPoint(x: (hub.x + tip.x) / 2 + dice.range(-4, 4) * u, y: (hub.y + tip.y) / 2 + dice.range(-3, 3) * u)
                    canvas.pen(SketchRenderer.smooth([hub, mid, tip], steps: 8), width: dice.range(1.2, 2.2) * u, alpha: 0.4, color: canvas.palette.paper)
                }
                // A dark, broken rim on part of the edge.
                let rim = leafOutline(leaf.center, rx: leaf.rx * 1.01, ry: leaf.ry * 1.01, turn: leaf.turn, noise: noise, phase: leaf.phase)
                let start = dice.int(0, rim.count - 1)
                let span = dice.int(rim.count / 5, rim.count / 2)
                let arc = (0..<span).map { rim[(start + $0) % rim.count] }
                canvas.brush(arc, width: { t in 3.2 * u * sin(.pi * t) + 0.4 * u }, alpha: 0.6)
            }
        }

        // Buds, open flowers and seed pods.
        for top in tops where top.kind != 0 {
            switch top.kind {
            case 1: flower(canvas, at: top.point, petals: 3, spread: 0.35, length: dice.range(55, 80) * u, dice: dice)
            case 2: flower(canvas, at: top.point, petals: dice.int(7, 9), spread: 1.25, length: dice.range(60, 90) * u, dice: dice)
            default:
                let s = dice.range(16, 24) * u
                let pod = [CGPoint(x: top.point.x - s * 0.5, y: top.point.y + s * 0.35), CGPoint(x: top.point.x - s, y: top.point.y - s * 0.45),
                           CGPoint(x: top.point.x + s, y: top.point.y - s * 0.45), CGPoint(x: top.point.x + s * 0.5, y: top.point.y + s * 0.35)]
                canvas.polygon(pod, alpha: 0.85)
                for _ in 0..<6 {
                    canvas.dot(CGPoint(x: top.point.x + dice.range(-0.7, 0.7) * s, y: top.point.y - s * 0.38 + dice.range(-1, 1) * u),
                               radius: 1.4 * u, alpha: 0.9, color: canvas.palette.paper)
                }
            }
        }

        // Reeds and grass blades crowding the water's edge.
        for _ in 0..<dice.int(22, 40) {
            let x = w * (from + span * dice.range(-0.05, 1.05))
            let tall = h * dice.range(0.12, 0.45)
            let lean = dice.range(-0.25, 0.25) * tall
            let blade = SketchRenderer.smooth([CGPoint(x: x, y: h * 1.02), CGPoint(x: x + lean * 0.3, y: h * 1.02 - tall * 0.5),
                                               CGPoint(x: x + lean, y: h * 1.02 - tall)], steps: 10)
            canvas.brush(blade, width: { t in (3.2 * (1 - t) + 0.3) * u }, alpha: dice.range(0.45, 0.85))
        }

        let column = right ? w * dice.range(0.9, 0.94) : w * dice.range(0.06, 0.1)
        let size = 28 * u
        canvas.calligraphy(x: column, top: h * 0.08, characters: dice.int(5, 8), size: size, dice: dice)
        if dice.chance(0.5) {
            canvas.calligraphy(x: column + (right ? -1.5 : 1.5) * size, top: h * 0.12, characters: dice.int(3, 6), size: size, dice: dice, alpha: 0.7)
        }
        canvas.seal(at: CGPoint(x: column - size * 0.4, y: h * dice.range(0.58, 0.7)), size: size * 0.85, dice: dice)
    }

    private static func leafOutline(_ center: CGPoint, rx: CGFloat, ry: CGFloat, turn: CGFloat, noise: Noise1D, phase: CGFloat) -> [CGPoint] {
        let steps = 90
        let (c, s) = (cos(turn), sin(turn))
        return (0..<steps).map { i in
            let angle = CGFloat(i) / CGFloat(steps) * 2 * .pi
            let ragged: CGFloat = 1 + 0.11 * noise.fbm(angle * 1.6 + phase) + 0.035 * noise(angle * 14 + phase)
            let x = cos(angle) * rx * ragged
            let y = sin(angle) * ry * ragged
            return CGPoint(x: center.x + x * c - y * s, y: center.y + x * s + y * c)
        }
    }

    private static func flower(_ canvas: InkCanvas, at base: CGPoint, petals: Int, spread: CGFloat, length: CGFloat, dice: Dice) {
        let u = canvas.unit
        let order = (0..<petals).sorted { abs(CGFloat($0) - CGFloat(petals - 1) / 2) > abs(CGFloat($1) - CGFloat(petals - 1) / 2) }
        for k in order {
            let t = petals == 1 ? 0 : CGFloat(k) / CGFloat(petals - 1) - 0.5
            let angle = -.pi / 2 + t * 2 * spread + dice.range(-0.08, 0.08)
            let size = length * (1 - abs(t) * 0.35) * dice.range(0.9, 1.05)
            let width = size * dice.range(0.32, 0.42)
            let (c, s) = (cos(angle), sin(angle))
            let side: [CGPoint] = (0...16).map { i in
                let along = CGFloat(i) / 16
                let swell: CGFloat = width * pow(sin(.pi * min(1, along * 1.1)), 0.8) * (1 - along * 0.4)
                return CGPoint(x: along * size, y: swell)
            }
            let outline = side + side.reversed().map { CGPoint(x: $0.x, y: -$0.y) }
            let placed = outline.map { CGPoint(x: base.x + $0.x * c - $0.y * s, y: base.y + $0.x * s + $0.y * c) }
            canvas.polygon(placed, alpha: canvas.palette.isDark ? 0.55 : 0.9, color: canvas.palette.bloom)
            canvas.pen(placed + [placed[0]], width: 1.1 * u, alpha: 0.7)
            // A darker tip, the way the brush lingers.
            let tip = CGPoint(x: base.x + size * c, y: base.y + size * s)
            let back = CGPoint(x: base.x + size * 0.8 * c, y: base.y + size * 0.8 * s)
            canvas.brush([back, tip], width: { t in 2.4 * u * (1 - t) + 0.4 * u }, alpha: 0.75)
        }
        canvas.dot(base, radius: 4 * u, alpha: 0.85)
    }

    // MARK: - Misty peaks

    static func mountains(_ canvas: InkCanvas, _ dice: Dice) {
        let (w, h, u) = (canvas.width, canvas.height, canvas.unit)
        let noise = Noise1D(dice)
        let cliffOnLeft = dice.chance(0.5)

        let sun = CGPoint(x: w * (cliffOnLeft ? dice.range(0.6, 0.82) : dice.range(0.18, 0.4)), y: h * dice.range(0.12, 0.24))
        canvas.dot(sun, radius: h * dice.range(0.035, 0.05), alpha: canvas.palette.isDark ? 0.55 : 0.72, color: canvas.palette.accent)
        for _ in 0..<dice.int(3, 7) {
            let p = CGPoint(x: sun.x + dice.range(-0.12, 0.12) * w, y: sun.y + dice.range(0.02, 0.12) * h)
            let span = dice.range(5, 10) * u
            canvas.pen(SketchRenderer.smooth([CGPoint(x: p.x - span, y: p.y - span * 0.3), CGPoint(x: p.x - span * 0.4, y: p.y - span * 0.45), p], steps: 4),
                       width: 1.1 * u, alpha: 0.8)
            canvas.pen(SketchRenderer.smooth([p, CGPoint(x: p.x + span * 0.4, y: p.y - span * 0.5), CGPoint(x: p.x + span, y: p.y - span * 0.35)], steps: 4),
                       width: 1.1 * u, alpha: 0.8)
        }

        let layers = 6
        for i in 0..<layers {
            let depth = CGFloat(i) / CGFloat(layers - 1)
            let baseline = h * (0.38 + 0.072 * CGFloat(i))
            let peaks: [(x: CGFloat, width: CGFloat, height: CGFloat)] = (0..<dice.int(3, 6)).map { _ in
                (dice.range(-0.1, 1.1) * w, w * dice.range(0.035, 0.11) * (1 + 0.8 * depth), h * dice.range(0.08, 0.3) * (1 - 0.35 * depth))
            }
            let phase = dice.range(0, 500)
            var ridge: [CGPoint] = []
            var x = -10 * u
            while x <= w + 10 * u {
                var lift: CGFloat = 0
                for peak in peaks {
                    let q = (x - peak.x) / peak.width
                    if abs(q) < 1 { lift = max(lift, peak.height * pow(1 - q * q, 0.55)) }
                }
                let hills: CGFloat = h * 0.035 * (noise.fbm(x / w * 5 + phase) + 0.6)
                let jag: CGFloat = h * 0.006 * noise(x / u * 0.08 + phase)
                ridge.append(CGPoint(x: x, y: baseline - max(lift, hills) - jag))
                x += 3 * u
            }
            guard let layer = canvas.layer() else { continue }
            layer.polygon(ridge + [CGPoint(x: w + 10 * u, y: h + 10 * u), CGPoint(x: -10 * u, y: h + 10 * u)], alpha: 0.1 + 0.2 * depth)
            // Short texture strokes hanging off the ridge, following the slope.
            var k = 2
            while k < ridge.count - 2 {
                let p = ridge[k]
                let slope = (ridge[k + 2].y - ridge[k - 2].y) / (ridge[k + 2].x - ridge[k - 2].x)
                let length = dice.range(5, 24) * u * (1 + depth)
                let top = CGPoint(x: p.x, y: p.y + dice.range(0, 14) * u)
                let bottom = CGPoint(x: p.x + max(-1.2, min(1.2, slope)) * length * 0.8, y: top.y + length)
                layer.pen([top, bottom], width: dice.range(0.8, 2) * u, alpha: dice.range(0.15, 0.4) * (0.6 + 0.4 * depth))
                k += dice.int(3, 6)
            }
            // Little trees along the nearer ridges.
            if depth > 0.5 {
                var t = dice.int(0, 12)
                while t < ridge.count {
                    let p = ridge[t]
                    let tall = dice.range(10, 24) * u * depth
                    layer.pen([p, CGPoint(x: p.x, y: p.y - tall)], width: 1.2 * u, alpha: 0.85)
                    for tier in 0..<3 {
                        let y = p.y - tall * (0.35 + 0.25 * CGFloat(tier))
                        let spread = tall * (0.45 - 0.12 * CGFloat(tier))
                        layer.pen([CGPoint(x: p.x - spread, y: y + 2 * u), CGPoint(x: p.x, y: y - 2 * u), CGPoint(x: p.x + spread, y: y + 2 * u)],
                                  width: 1.6 * u, alpha: 0.85)
                    }
                    t += dice.int(6, 22)
                }
            }
            // The ridge itself in broken, dry strokes.
            var start = 0
            while start < ridge.count - 4 {
                let end = min(ridge.count, start + dice.int(20, 80))
                layer.pen(Array(ridge[start..<end]), width: dice.range(1.2, 2.6) * u * (0.6 + 0.6 * depth), alpha: dice.range(0.5, 0.85))
                start = end + dice.int(0, 6)
            }
            canvas.paste(layer, blur: (1 - depth) * 3 * u)
            canvas.mist(from: baseline - h * 0.09, to: baseline + h * 0.06)
        }
        // Still water below the last range.
        for _ in 0..<dice.int(8, 14) {
            let y = h * dice.range(0.8, 0.97)
            let x = w * dice.range(-0.05, 0.95)
            let points = SketchRenderer.line(CGPoint(x: x, y: y), CGPoint(x: x + dice.range(40, 260) * u, y: y), steps: 16)
            canvas.pen(SketchRenderer.wobble(points, amount: 1.2 * u, frequency: 0.3, noise: noise, phase: dice.range(0, 99)),
                       width: dice.range(0.7, 1.4) * u, alpha: dice.range(0.12, 0.3))
        }

        cliff(canvas, onLeft: cliffOnLeft, dice: dice, noise: noise)

        // A boat on the open water.
        let boat = CGPoint(x: w * (cliffOnLeft ? dice.range(0.55, 0.75) : dice.range(0.25, 0.45)), y: h * dice.range(0.85, 0.9))
        let hull = SketchRenderer.smooth([CGPoint(x: boat.x - 26 * u, y: boat.y - 5 * u), CGPoint(x: boat.x, y: boat.y + 4 * u),
                                          CGPoint(x: boat.x + 28 * u, y: boat.y - 6 * u)], steps: 8)
        canvas.brush(hull, width: { t in 5 * u * sin(.pi * t) + 0.5 * u }, alpha: 0.85)
        canvas.pen([CGPoint(x: boat.x + 4 * u, y: boat.y - 2 * u), CGPoint(x: boat.x + 4 * u, y: boat.y - 15 * u)], width: 2.2 * u, alpha: 0.85)
        canvas.dot(CGPoint(x: boat.x + 4 * u, y: boat.y - 17 * u), radius: 2.4 * u, alpha: 0.85)
        canvas.pen([CGPoint(x: boat.x - 12 * u, y: boat.y + 14 * u), CGPoint(x: boat.x + 14 * u, y: boat.y - 26 * u)], width: 0.9 * u, alpha: 0.7)
        for _ in 0..<5 {
            let y = boat.y + dice.range(6, 22) * u
            let x = boat.x + dice.range(-40, 30) * u
            canvas.pen([CGPoint(x: x, y: y), CGPoint(x: x + dice.range(15, 40) * u, y: y)], width: 0.8 * u, alpha: 0.35)
        }

        let column = cliffOnLeft ? w * dice.range(0.9, 0.94) : w * dice.range(0.06, 0.1)
        let size = 26 * u
        canvas.calligraphy(x: column, top: h * 0.08, characters: dice.int(4, 7), size: size, dice: dice)
        canvas.seal(at: CGPoint(x: column - size * 0.4, y: h * dice.range(0.42, 0.5)), size: size * 0.85, dice: dice)
    }

    private static func cliff(_ canvas: InkCanvas, onLeft: Bool, dice: Dice, noise: Noise1D) {
        let (w, h, u) = (canvas.width, canvas.height, canvas.unit)
        func place(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: onLeft ? x : w - x, y: y) }
        let top = h * dice.range(0.44, 0.58)
        let width = w * dice.range(0.2, 0.32)
        let phase = dice.range(0, 300)

        var face: [CGPoint] = []
        for k in 0...24 {
            let t = CGFloat(k) / 24
            let jut: CGFloat = width * 0.12 * noise.fbm(t * 3 + phase) + width * 0.1 * sin(t * .pi)
            face.append(place(width * (0.92 - 0.28 * t) + jut, top + t * (h * 1.02 - top)))
        }
        var ledge: [CGPoint] = []
        for k in 0...12 {
            let t = CGFloat(k) / 12
            ledge.append(place(-10 * u + t * (width * 0.92 + 10 * u), top + 8 * u * noise(t * 6 + phase)))
        }
        let shape = ledge + face + [place(-10 * u, h + 10 * u)]
        // Solid rock: paper first so the hills behind don't show through.
        canvas.polygon(shape, alpha: 1, color: canvas.palette.paper)
        if let rock = canvas.layer() {
            rock.polygon(shape, alpha: 0.2)
            // Axe-cut texture: short slanted strokes, thicker toward the face.
            for _ in 0..<dice.int(160, 260) {
                let t = dice.range(0.02, 1)
                let inward = pow(dice.next(), 0.6)
                let p = place(width * (0.92 - 0.28 * t) * inward, top + t * (h - top) + dice.range(4, 12) * u)
                let length = dice.range(6, 22) * u
                rock.pen([p, CGPoint(x: p.x + (onLeft ? -1 : 1) * length * 0.7, y: p.y + length)],
                         width: dice.range(1, 2.6) * u, alpha: dice.range(0.2, 0.55) * (0.5 + 0.5 * inward))
            }
            canvas.paste(rock, blur: 0.8 * u)
        }
        canvas.mist(from: h * 0.82, to: h * 1.0, strength: 0.7)
        // A waterfall spilling off the ledge down the cliff face.
        let fall = place(width * dice.range(0.55, 0.8), top)
        for _ in 0..<dice.int(5, 9) {
            let x = fall.x + dice.range(-9, 9) * u
            let points = SketchRenderer.line(CGPoint(x: x, y: top + 4 * u), CGPoint(x: x + dice.range(-6, 6) * u, y: h * dice.range(0.75, 0.95)), steps: 30)
            canvas.pen(SketchRenderer.wobble(points, amount: 1.5 * u, frequency: 0.25, noise: noise, phase: dice.range(0, 99)),
                       width: dice.range(1.5, 4) * u, alpha: dice.range(0.5, 0.9), color: canvas.palette.light)
        }
        if let spray = canvas.layer() {
            spray.dot(CGPoint(x: fall.x, y: h * 0.9), radius: 50 * u, alpha: canvas.palette.isDark ? 0.35 : 0.9, color: canvas.palette.light)
            canvas.paste(spray, blur: 18 * u)
        }
        let edge = SketchRenderer.smooth(face, steps: 4)
        canvas.brush(edge, width: { t in (4 + 4 * sin(.pi * t)) * u }, alpha: 0.88)
        canvas.dryBrush(edge, width: 7 * u, streaks: 3, dice: dice)
        let rim = SketchRenderer.smooth(ledge, steps: 4)
        canvas.brush(rim, width: { t in (2 + 2.5 * sin(.pi * t)) * u }, alpha: 0.85)
        canvas.dryBrush(rim, width: 3 * u, streaks: 2, dice: dice, broken: true)

        // Pines on the ledge.
        for _ in 0..<dice.int(1, 3) {
            pine(canvas, base: place(width * dice.range(0.12, 0.6), top + 2 * u), height: dice.range(90, 170) * u,
                 lean: dice.range(-0.35, 0.35), dice: dice, noise: noise)
        }
        // A pavilion near the edge.
        let s = 30 * u
        let center = place(width * 0.74, top)
        canvas.polygon([CGPoint(x: center.x - 1.1 * s, y: center.y - 0.12 * s), CGPoint(x: center.x + 1.1 * s, y: center.y - 0.12 * s),
                        CGPoint(x: center.x + 1.1 * s, y: center.y), CGPoint(x: center.x - 1.1 * s, y: center.y)], alpha: 0.9)
        for post in [-0.8, 0, 0.8] as [CGFloat] {
            canvas.pen([CGPoint(x: center.x + post * s, y: center.y - 0.12 * s), CGPoint(x: center.x + post * s, y: center.y - 0.82 * s)],
                       width: 1.8 * u, alpha: 0.9)
        }
        let eave = center.y - 0.82 * s
        let roof = SketchRenderer.smooth([CGPoint(x: center.x - 1.5 * s, y: eave - 0.22 * s), CGPoint(x: center.x - 1.05 * s, y: eave),
                                          CGPoint(x: center.x + 1.05 * s, y: eave), CGPoint(x: center.x + 1.5 * s, y: eave - 0.22 * s)], steps: 6)
            + [CGPoint(x: center.x + 0.55 * s, y: eave - 0.55 * s), CGPoint(x: center.x - 0.55 * s, y: eave - 0.55 * s)]
        canvas.polygon(roof, alpha: 0.9)
        canvas.pen([CGPoint(x: center.x, y: eave - 0.55 * s), CGPoint(x: center.x, y: eave - 0.8 * s)], width: 1.6 * u, alpha: 0.9)
    }

    private static func pine(_ canvas: InkCanvas, base: CGPoint, height: CGFloat, lean: CGFloat, dice: Dice, noise: Noise1D) {
        let u = canvas.unit
        let trunk = SketchRenderer.wobble(SketchRenderer.smooth([
            base,
            CGPoint(x: base.x + lean * height * 0.2 + dice.range(-10, 10) * u, y: base.y - height * 0.4),
            CGPoint(x: base.x + lean * height * 0.7, y: base.y - height * 0.75),
            CGPoint(x: base.x + lean * height, y: base.y - height),
        ], steps: 10), amount: 2 * u, frequency: 0.5, noise: noise, phase: dice.range(0, 99))
        canvas.brush(trunk, width: { t in (8 - 5.5 * t) * u }, alpha: 0.9)
        canvas.dryBrush(trunk, width: 6 * u, streaks: 2, dice: dice)

        var clusters = [trunk[trunk.count - 1]]
        for _ in 0..<dice.int(3, 5) {
            let at = trunk[Int(CGFloat(trunk.count - 1) * dice.range(0.35, 0.92))]
            let reach = dice.range(30, 80) * u * dice.sign()
            let end = CGPoint(x: at.x + reach, y: at.y - dice.range(-6, 18) * u)
            canvas.brush(SketchRenderer.smooth([at, CGPoint(x: at.x + reach * 0.5, y: at.y + 4 * u), end], steps: 6),
                         width: { t in (3.2 - 2.2 * t) * u }, alpha: 0.88)
            clusters.append(end)
        }
        // Flat fans of needles.
        for center in clusters {
            let width = dice.range(40, 72) * u
            let tall = width * dice.range(0.28, 0.4)
            canvas.polygon(InkScenes.ellipse(center: CGPoint(x: center.x, y: center.y - tall * 0.2), rx: width * 0.5, ry: tall * 0.5), alpha: 0.3)
            for j in 0..<dice.int(14, 22) {
                let f = CGFloat(j) / 20 - 0.5
                let from = CGPoint(x: center.x + f * width * 0.5, y: center.y + tall * 0.15)
                let to = CGPoint(x: center.x + f * width * 1.05 + dice.range(-3, 3) * u, y: center.y - tall * dice.range(0.5, 0.8))
                canvas.pen([from, to], width: dice.range(0.8, 1.3) * u, alpha: 0.85)
            }
        }
    }

    static func ellipse(center: CGPoint, rx: CGFloat, ry: CGFloat) -> [CGPoint] {
        (0..<36).map { i in
            let a = CGFloat(i) / 36 * 2 * .pi
            return CGPoint(x: center.x + cos(a) * rx, y: center.y + sin(a) * ry)
        }
    }
}
