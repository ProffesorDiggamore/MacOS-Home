import CoreGraphics

/// Pen-and-brush scenes: telephone poles in scratchy ink. The plum tree is in PlumScene.swift.
enum SketchScenes {
    // MARK: - Power lines

    private struct Pole {
        var x: CGFloat
        var top: CGFloat
        var scale: CGFloat
        var lean: CGFloat
        /// Where wires attach, one list per crossarm, left to right.
        var arms: [[CGPoint]] = []
    }

    static func powerLines(_ canvas: InkCanvas, _ dice: Dice) {
        let (w, h, u) = (canvas.width, canvas.height, canvas.unit)
        let noise = Noise1D(dice)

        // A soft grey haze behind the main pole.
        if let haze = canvas.layer() {
            for _ in 0..<6 {
                haze.dot(CGPoint(x: w * dice.range(0.25, 0.75), y: h * dice.range(0.1, 0.6)),
                         radius: dice.range(120, 300) * u, alpha: dice.range(0.04, 0.09))
            }
            canvas.paste(haze, blur: 60 * u)
        }

        let count = dice.int(3, 5)
        let main = dice.int(1, count - 2 > 1 ? count - 2 : 1)
        var poles: [Pole] = (0..<count).map { i in
            let scale: CGFloat = i == main ? 1.25 : dice.range(0.42, 0.78)
            let x: CGFloat = w * (-0.04 + 1.08 * (CGFloat(i) + 0.5) / CGFloat(count) + dice.range(-0.05, 0.05))
            let top: CGFloat = h * (0.04 + max(0, 1 - scale) * 0.32 + dice.range(0, 0.04))
            return Pole(x: x, top: top, scale: scale, lean: dice.range(-18, 18) * u * scale)
        }

        // Construction lines first, so everything else sits on top.
        for _ in 0..<dice.int(16, 28) {
            let center = CGPoint(x: poles[main].x + dice.gauss() * w * 0.25, y: h * dice.range(0.1, 0.8))
            let angle = dice.chance(0.4) ? dice.range(-0.12, 0.12) : dice.range(0, .pi)
            let length = w * dice.range(0.4, 1.4)
            let a = CGPoint(x: center.x - cos(angle) * length / 2, y: center.y - sin(angle) * length / 2)
            let b = CGPoint(x: center.x + cos(angle) * length / 2, y: center.y + sin(angle) * length / 2)
            canvas.pen(SketchRenderer.line(a, b, steps: 2), width: dice.range(0.5, 1.0) * u, alpha: dice.range(0.08, 0.26))
        }

        // Steel pylons along the horizon, strung together.
        let horizon = h * dice.range(0.6, 0.7)
        var previous: CGPoint?
        var px = dice.range(-0.05, 0.1) * w
        while px < w * 1.05 {
            let tall = dice.range(55, 100) * u
            let top = CGPoint(x: px, y: horizon - tall)
            let foot = tall * 0.28
            canvas.pen([CGPoint(x: px - foot, y: horizon), top, CGPoint(x: px + foot, y: horizon)], width: 1 * u, alpha: 0.4)
            var level: CGFloat = 0.2
            while level < 0.95 {
                let half = foot * (1 - level)
                let y = horizon - tall * level
                canvas.pen([CGPoint(x: px - half, y: y), CGPoint(x: px + half * 0.8, y: y - tall * 0.12)], width: 0.7 * u, alpha: 0.32)
                level += 0.15
            }
            canvas.pen([CGPoint(x: px - tall * 0.3, y: top.y + tall * 0.18), CGPoint(x: px + tall * 0.3, y: top.y + tall * 0.18)], width: 1 * u, alpha: 0.4)
            if let previous {
                for k in [-0.3, 0.3] as [CGFloat] {
                    let a = CGPoint(x: previous.x + tall * k, y: previous.y + tall * 0.18)
                    let b = CGPoint(x: top.x + tall * k, y: top.y + tall * 0.18)
                    canvas.pen(SketchRenderer.catenary(a, b, sag: 14 * u, steps: 16), width: 0.7 * u, alpha: 0.3)
                }
            }
            previous = top
            px += dice.range(0.14, 0.24) * w
        }

        // Far poles first, lighter, like they're further into the haze.
        let order = poles.indices.sorted { poles[$0].scale < poles[$1].scale }
        for index in order where index != main {
            drawPole(&poles[index], canvas: canvas, dice: dice, noise: noise, transformer: dice.chance(0.3))
        }
        // Ground haze swallows the feet of the far poles; the main one stands in front of it.
        canvas.mist(from: h * 0.62, to: h * 1.0, strength: 0.75)
        drawPole(&poles[main], canvas: canvas, dice: dice, noise: noise, transformer: true)

        // Wires between neighbours, arm to arm.
        var attachments: [CGPoint] = []
        for i in 0..<(poles.count - 1) {
            let a = poles[i], b = poles[i + 1]
            for arm in 0..<min(a.arms.count, b.arms.count) {
                let from = a.arms[arm], to = b.arms[arm]
                for (j, start) in from.enumerated() {
                    let end = to[min(to.count - 1, j * to.count / max(1, from.count))]
                    let depth = min(a.scale, b.scale)
                    wire(canvas, start, end, sag: dice.range(20, 60) * u * depth + abs(end.x - start.x) * 0.035,
                         width: dice.range(1.1, 1.9) * u * (0.6 + 0.4 * depth), dice: dice, noise: noise)
                }
            }
            attachments += a.arms.flatMap { $0 }
        }
        attachments += poles.last?.arms.flatMap { $0 } ?? []

        // Wires running out of the picture on both sides.
        for (pole, outward) in [(poles.first, -1 as CGFloat), (poles.last, 1 as CGFloat)] {
            guard let pole else { continue }
            for point in pole.arms.flatMap({ $0 }) where dice.chance(0.75) {
                let end = CGPoint(x: outward < 0 ? -w * 0.05 : w * 1.05, y: point.y + dice.range(-0.05, 0.18) * h)
                wire(canvas, point, end, sag: dice.range(30, 90) * u, width: dice.range(1.0, 1.7) * u, dice: dice, noise: noise)
            }
        }

        // The tangle: wires crossing between random poles and service drops falling out of frame.
        for _ in 0..<dice.int(8, 16) where attachments.count > 1 {
            let a = attachments[dice.int(0, attachments.count - 1)]
            let b: CGPoint = dice.chance(0.6)
                ? attachments[dice.int(0, attachments.count - 1)]
                : CGPoint(x: dice.range(-0.1, 1.1) * w, y: h * dice.range(0.75, 1.1))
            guard abs(a.x - b.x) > 20 * u else { continue }
            wire(canvas, a, b, sag: dice.range(15, 120) * u, width: dice.range(0.8, 1.5) * u, dice: dice, noise: noise, alpha: dice.range(0.45, 0.85))
        }

        // Birds perched along the wires between poles.
        for _ in 0..<dice.int(5, 14) where poles.count > 1 {
            let i = dice.int(0, poles.count - 2)
            let (a, b) = (poles[i], poles[i + 1])
            guard let armA = a.arms.first, let armB = b.arms.first, !armA.isEmpty, !armB.isEmpty else { continue }
            let j = dice.int(0, min(armA.count, armB.count) - 1)
            let start = armA[j], end = armB[min(armB.count - 1, j)]
            let sag = abs(end.x - start.x) * 0.035 + 30 * u
            let t = dice.range(0.15, 0.85)
            let perch = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t + sag * 4 * t * (1 - t))
            let size = dice.range(5, 8) * u * min(a.scale, b.scale)
            let facing = dice.sign()
            canvas.context.setFillColor(canvas.color(canvas.palette.ink, 0.92))
            canvas.context.fillEllipse(in: CGRect(x: perch.x - size, y: perch.y - size * 1.5, width: size * 2, height: size * 1.3))
            canvas.dot(CGPoint(x: perch.x + facing * size * 0.9, y: perch.y - size * 1.6), radius: size * 0.5, alpha: 0.92)
            canvas.pen([CGPoint(x: perch.x - facing * size * 0.8, y: perch.y - size * 0.9), CGPoint(x: perch.x - facing * size * 1.9, y: perch.y - size * 0.3)],
                       width: size * 0.45, alpha: 0.92)
        }

        // A knot of loose wire around the main pole's crossarms.
        let hub = CGPoint(x: poles[main].x, y: poles[main].top + 60 * u)
        for _ in 0..<dice.int(30, 60) {
            let a = CGPoint(x: hub.x + dice.gauss() * 120 * u, y: hub.y + dice.gauss() * 70 * u)
            let b = CGPoint(x: a.x + dice.range(-160, 160) * u, y: a.y + dice.range(-50, 50) * u)
            canvas.pen(SketchRenderer.catenary(a, b, sag: dice.range(-20, 50) * u, steps: 16), width: dice.range(0.6, 1.4) * u, alpha: dice.range(0.35, 0.8))
        }

        // Scribbles near the top of the main pole.
        for _ in 0..<dice.int(5, 10) {
            let center = CGPoint(x: hub.x + dice.gauss() * 160 * u, y: hub.y + dice.gauss() * 140 * u)
            let radius = dice.range(25, 80) * u
            let angle = dice.range(0, .pi)
            let points: [CGPoint] = (0..<dice.int(18, 50)).map { k in
                let along = dice.range(-1, 1) * radius
                let across = (k % 2 == 0 ? 1 : -1) * dice.range(0.2, 0.6) * radius
                return CGPoint(x: center.x + cos(angle) * along - sin(angle) * across,
                               y: center.y + sin(angle) * along + cos(angle) * across)
            }
            canvas.pen(points, width: dice.range(0.6, 1.1) * u, alpha: dice.range(0.2, 0.45))
        }

        // Ink drips hanging off the wires.
        for _ in 0..<dice.int(4, 9) where !attachments.isEmpty {
            let start = attachments[dice.int(0, attachments.count - 1)]
            let top = CGPoint(x: start.x + dice.range(-60, 60) * u, y: start.y + dice.range(10, 40) * u)
            let bottom = CGPoint(x: top.x + dice.range(-2, 2) * u, y: top.y + dice.range(25, 140) * u)
            canvas.pen([top, bottom], width: dice.range(0.8, 1.6) * u, alpha: 0.75)
            canvas.dot(bottom, radius: dice.range(1.6, 3.2) * u, alpha: 0.85)
        }

        // Splatter, thickest around the main pole.
        for _ in 0..<dice.int(260, 520) {
            let center = CGPoint(x: hub.x + dice.gauss() * w * 0.18, y: hub.y + dice.gauss() * h * 0.22)
            let big = dice.chance(0.05)
            canvas.dot(center, radius: (big ? dice.range(3, 7) : dice.range(0.5, 2.2)) * u, alpha: dice.range(0.4, 0.9))
        }
    }

    private static func drawPole(_ pole: inout Pole, canvas: InkCanvas, dice: Dice, noise: Noise1D, transformer: Bool) {
        let (h, u) = (canvas.height, canvas.unit)
        let s = pole.scale
        let tone: CGFloat = 0.5 + 0.5 * s
        let base = 28 * u * s, tip = 13 * u * s
        let bottom = h * 1.02
        let topX = pole.x + pole.lean
        let left = [CGPoint(x: pole.x - base / 2, y: bottom), CGPoint(x: topX - tip / 2, y: pole.top)]
        let right = [CGPoint(x: topX + tip / 2, y: pole.top), CGPoint(x: pole.x + base / 2, y: bottom)]
        canvas.polygon(left + right, alpha: 0.86 * tone)
        // Loose diagonal hatching that spills past the edges.
        var hatch = pole.top + dice.range(0, 20) * u * s
        while hatch < bottom {
            let t = (hatch - pole.top) / (bottom - pole.top)
            let cx = topX + (pole.x - topX) * t
            let reach = (tip + (base - tip) * t) * dice.range(0.9, 1.6)
            canvas.pen([CGPoint(x: cx - reach, y: hatch + reach * 0.6), CGPoint(x: cx + reach, y: hatch - reach * 0.6)],
                       width: 0.7 * u * s, alpha: dice.range(0.25, 0.55) * tone)
            hatch += dice.range(10, 40) * u * s
        }
        canvas.sketchLine(SketchRenderer.line(left[0], left[1], steps: 30), width: 1.6 * u * s, alpha: tone, dice: dice, noise: noise)
        canvas.sketchLine(SketchRenderer.line(right[0], right[1], steps: 30), width: 1.6 * u * s, alpha: tone, dice: dice, noise: noise)

        // Wood grain: pale streaks down the pole and short cross hatches.
        for _ in 0..<dice.int(2, 4) {
            let offset = dice.range(-0.3, 0.3)
            let a = CGPoint(x: pole.x + offset * base, y: bottom)
            let b = CGPoint(x: topX + offset * tip, y: pole.top + dice.range(0, 0.3) * (bottom - pole.top))
            canvas.pen(SketchRenderer.wobble(SketchRenderer.line(a, b, steps: 24), amount: 1.2 * u, frequency: 0.2, noise: noise, phase: dice.range(0, 99)),
                       width: dice.range(0.6, 1.3) * u * s, alpha: 0.35, color: canvas.palette.paper)
        }
        var y = pole.top + 8 * u * s
        while y < bottom {
            let t = (y - pole.top) / (bottom - pole.top)
            let cx = topX + (pole.x - topX) * t
            let half = (tip + (base - tip) * t) / 2
            canvas.pen([CGPoint(x: cx - half * 1.3, y: y + dice.range(-2, 2) * u), CGPoint(x: cx + half * 1.3, y: y + dice.range(-4, 4) * u)],
                       width: 0.7 * u * s, alpha: 0.4 * tone)
            y += dice.range(7, 16) * u * s
        }
        // Climbing pegs.
        var peg = pole.top + (bottom - pole.top) * 0.3
        var side: CGFloat = 1
        while peg < bottom {
            let t = (peg - pole.top) / (bottom - pole.top)
            let cx = topX + (pole.x - topX) * t
            canvas.pen([CGPoint(x: cx, y: peg), CGPoint(x: cx + side * 16 * u * s, y: peg - 1.5 * u * s)], width: 2.2 * u * s, alpha: 0.85 * tone)
            peg += 34 * u * s
            side = -side
        }

        // Crossarms with insulators.
        var armY = pole.top + 18 * u * s
        for arm in 0..<dice.int(2, 4) {
            let length = dice.range(150, 250) * u * s * (arm == 0 ? 1 : dice.range(0.7, 1.05))
            let center = topX + dice.range(-20, 20) * u * s
            let tilt = dice.range(-0.04, 0.04)
            let a = CGPoint(x: center - length / 2, y: armY - tilt * length / 2)
            let b = CGPoint(x: center + length / 2, y: armY + tilt * length / 2)
            let thick = 9 * u * s
            canvas.polygon([a, b, CGPoint(x: b.x, y: b.y + thick), CGPoint(x: a.x, y: a.y + thick)], alpha: 0.85 * tone)
            canvas.sketchLine(SketchRenderer.line(a, b, steps: 20), width: 1.4 * u * s, alpha: tone, dice: dice, noise: noise)
            for brace in [-1 as CGFloat, 1] {
                let from = CGPoint(x: center + brace * length * 0.22, y: armY + thick)
                let to = CGPoint(x: topX, y: armY + 34 * u * s)
                canvas.pen([from, to], width: 1.6 * u * s, alpha: 0.8 * tone)
            }
            var points: [CGPoint] = []
            let count = dice.int(2, 3)
            for k in 0..<(count * 2) {
                let fraction = CGFloat(k) / CGFloat(count * 2 - 1) - 0.5
                guard abs(fraction) > 0.08 else { continue }
                let foot = CGPoint(x: center + fraction * length * 0.92, y: armY + tilt * fraction * length)
                for bell in 0..<3 {
                    let by = foot.y - (3 + CGFloat(bell) * 4.5) * u * s
                    canvas.context.setStrokeColor(canvas.color(canvas.palette.ink, 0.9 * tone))
                    canvas.context.setLineWidth(1.1 * u * s)
                    canvas.context.strokeEllipse(in: CGRect(x: foot.x - 5.5 * u * s, y: by - 2.2 * u * s, width: 11 * u * s, height: 4.4 * u * s))
                }
                points.append(CGPoint(x: foot.x, y: foot.y - 16 * u * s))
            }
            pole.arms.append(points)
            armY += dice.range(38, 62) * u * s
        }

        guard transformer else { return }
        let hang: CGFloat = dice.sign()
        let can = CGRect(x: topX + hang * (tip / 2 + 24 * u * s) - 17 * u * s, y: armY + dice.range(20, 60) * u * s, width: 34 * u * s, height: 64 * u * s)
        canvas.fill(CGPath(roundedRect: can, cornerWidth: 6 * u * s, cornerHeight: 6 * u * s, transform: nil), alpha: 0.78 * tone)
        canvas.sketchLine([CGPoint(x: can.minX, y: can.minY), CGPoint(x: can.minX, y: can.maxY)], width: 1.3 * u * s, alpha: tone, dice: dice, noise: noise)
        canvas.sketchLine([CGPoint(x: can.maxX, y: can.minY), CGPoint(x: can.maxX, y: can.maxY)], width: 1.3 * u * s, alpha: tone, dice: dice, noise: noise)
        for k in 0..<5 {
            let x = can.minX + can.width * (0.2 + 0.15 * CGFloat(k))
            canvas.pen([CGPoint(x: x, y: can.minY + 4 * u * s), CGPoint(x: x, y: can.maxY - 4 * u * s)], width: 0.8 * u * s, alpha: 0.35, color: canvas.palette.paper)
        }
        for band in [0.18 as CGFloat, 0.82] {
            canvas.pen([CGPoint(x: can.minX - 2 * u * s, y: can.minY + can.height * band), CGPoint(x: can.maxX + 2 * u * s, y: can.minY + can.height * band)],
                       width: 2 * u * s, alpha: 0.9 * tone)
        }
        canvas.pen([CGPoint(x: can.midX, y: can.midY), CGPoint(x: topX, y: can.midY - 10 * u * s)], width: 3 * u * s, alpha: tone)
        // Leads from the transformer up to the lowest crossarm.
        if let arm = pole.arms.last {
            for k in 0..<2 {
                let bushing = CGPoint(x: can.minX + can.width * (0.3 + 0.4 * CGFloat(k)), y: can.minY - 6 * u * s)
                canvas.pen([CGPoint(x: bushing.x, y: can.minY), bushing], width: 3 * u * s, alpha: tone)
                if let target = arm.min(by: { abs($0.x - bushing.x) < abs($1.x - bushing.x) }) {
                    canvas.pen(SketchRenderer.catenary(bushing, target, sag: 8 * u * s, steps: 12), width: 1.1 * u * s, alpha: 0.85 * tone)
                }
            }
        }
    }

    private static func wire(_ canvas: InkCanvas, _ a: CGPoint, _ b: CGPoint, sag: CGFloat, width: CGFloat,
                             dice: Dice, noise: Noise1D, alpha: CGFloat = 0.9) {
        let points = SketchRenderer.catenary(a, b, sag: sag, steps: 48)
        canvas.sketchLine(points, width: width, alpha: alpha, dice: dice, noise: noise, passes: dice.chance(0.35) ? 2 : 1)
    }
}
