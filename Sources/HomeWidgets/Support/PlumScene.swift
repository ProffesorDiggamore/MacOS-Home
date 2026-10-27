import CoreGraphics

/// A plum tree in full bloom, painted the way ink painters do it: a gnarled trunk in fast, dry
/// strokes, angular limbs, straight young shoots, and hundreds of grey blossoms and dark buds.
extension SketchScenes {
    private struct Bloom {
        var point: CGPoint
        var size: CGFloat
        var faint: Bool
    }

    static func inkBranch(_ canvas: InkCanvas, _ dice: Dice) {
        let (w, h, u) = (canvas.width, canvas.height, canvas.unit)
        let noise = Noise1D(dice)
        let trunkX = w * dice.range(0.3, 0.6)

        // Sometimes a pale moon behind the branches.
        if dice.chance(0.45), let wash = canvas.layer() {
            let moon = CGPoint(x: trunkX + w * dice.sign() * dice.range(0.18, 0.3), y: h * dice.range(0.2, 0.35))
            let radius = h * dice.range(0.12, 0.18)
            if canvas.palette.isDark {
                wash.dot(moon, radius: radius, alpha: 0.16)
            } else {
                wash.context.setFillColor(wash.color(canvas.palette.ink, 0.06))
                wash.context.fill(CGRect(x: 0, y: 0, width: w, height: h))
                wash.context.setBlendMode(.clear)
                wash.dot(moon, radius: radius, alpha: 1)
                wash.context.setBlendMode(.normal)
            }
            canvas.paste(wash, blur: 4 * u)
        }

        // A second tree further back: smaller, softer and paler.
        if let ghost = canvas.layer() {
            var blooms: [Bloom] = []
            let x = trunkX + w * dice.sign() * dice.range(0.2, 0.35)
            limb(ghost, from: CGPoint(x: x, y: h * 1.03), angle: -.pi / 2 + dice.range(-0.25, 0.25), length: h * 0.3, thick: 46 * u,
                 depth: 4, dice: dice, noise: noise, blooms: &blooms)
            for bloom in sample(blooms, 120, dice) { blossom(ghost, bloom, dice: dice) }
            canvas.paste(ghost, blur: 3.5 * u, alpha: 0.32)
        }

        var blooms: [Bloom] = []
        limb(canvas, from: CGPoint(x: trunkX, y: h * 1.04), angle: -.pi / 2 + dice.range(-0.3, 0.3), length: h * dice.range(0.3, 0.38),
             thick: 96 * u, depth: 5, dice: dice, noise: noise, blooms: &blooms)
        // A second trunk from the same root, as old plum trees often have.
        if dice.chance(0.5) {
            limb(canvas, from: CGPoint(x: trunkX + dice.range(-40, 40) * u, y: h * 1.04), angle: -.pi / 2 + dice.sign() * dice.range(0.45, 0.8),
                 length: h * dice.range(0.2, 0.28), thick: 56 * u, depth: 4, dice: dice, noise: noise, blooms: &blooms)
        }
        for bloom in sample(blooms, 560, dice) { blossom(canvas, bloom, dice: dice) }

        // Two columns of brush writing with seals, on whichever side has more room.
        let right = trunkX < w * 0.5
        let column = right ? w * dice.range(0.82, 0.88) : w * dice.range(0.12, 0.18)
        let size = 30 * u
        let top = h * dice.range(0.3, 0.45)
        canvas.calligraphy(x: column, top: top, characters: dice.int(6, 9), size: size, dice: dice)
        canvas.calligraphy(x: column + (right ? -1.6 : 1.6) * size, top: top + size * 1.3, characters: dice.int(5, 8), size: size, dice: dice, alpha: 0.75)
        canvas.seal(at: CGPoint(x: column - size * 0.35, y: top + size * 11), size: size * 0.7, dice: dice)
        canvas.seal(at: CGPoint(x: column - size * 0.35, y: top + size * 12.2), size: size * 0.7, dice: dice)
    }

    /// At most `limit` blossoms, picked evenly at random, so big trees keep their open spaces.
    private static func sample(_ blooms: [Bloom], _ limit: Int, _ dice: Dice) -> [Bloom] {
        guard blooms.count > limit else { return blooms }
        let keep = CGFloat(limit) / CGFloat(blooms.count)
        return blooms.filter { _ in dice.chance(keep) }
    }

    /// One limb: a gnarled stroke that carries on as a thinner limb, throws off side limbs, and
    /// once thin enough sprouts straight young shoots lined with blossoms.
    private static func limb(_ canvas: InkCanvas, from start: CGPoint, angle: CGFloat, length: CGFloat, thick: CGFloat, depth: Int,
                             dice: Dice, noise: Noise1D, blooms: inout [Bloom]) {
        let u = canvas.unit
        var points = [start]
        var heading = angle
        let segments = dice.int(4, 6)
        let wiggle: CGFloat = thick > 30 * u ? 0.32 : 0.45
        for _ in 0..<segments {
            heading += dice.range(-wiggle, wiggle)
            // Plum limbs keep reaching up and out, never back down into the trunk.
            heading = min(max(heading, -.pi * 0.98), -.pi * 0.02)
            let step = length / CGFloat(segments)
            let last = points[points.count - 1]
            points.append(CGPoint(x: last.x + cos(heading) * step, y: last.y + sin(heading) * step))
        }
        let phase = dice.range(0, 400)
        let path = SketchRenderer.wobble(SketchRenderer.smooth(points, steps: 7), amount: thick * 0.12, frequency: 0.35, noise: noise, phase: phase)
        let endWidth = thick * 0.58 + 1.2 * u
        canvas.brush(path, width: { t in (thick + (endWidth - thick) * t) * (1 + 0.16 * noise(t * 9 + phase)) }, alpha: 0.93)
        canvas.dot(start, radius: thick / 2, alpha: 0.93)
        canvas.dot(path[path.count - 1], radius: endWidth / 2, alpha: 0.93)
        if thick > 8 * u {
            canvas.dryBrush(path, width: thick * 0.75, streaks: min(10, Int(thick / u / 7) + 1), dice: dice, alpha: 0.5, broken: true)
        }
        // Knots and moss dots on the old wood.
        if thick > 16 * u {
            for _ in 0..<dice.int(3, 8) {
                let p = path[dice.int(0, path.count - 1)]
                canvas.dot(CGPoint(x: p.x + dice.gauss() * thick * 0.6, y: p.y + dice.gauss() * thick * 0.4),
                           radius: dice.range(1.5, 4.5) * u, alpha: 0.95)
            }
        }

        if thick < 14 * u { shoots(canvas, along: path, thick: thick, dice: dice, blooms: &blooms) }
        guard depth > 0, thick > 2.2 * u else { return }
        limb(canvas, from: path[path.count - 1], angle: heading + dice.range(-0.4, 0.4), length: length * dice.range(0.62, 0.82),
             thick: endWidth * 0.92, depth: depth - 1, dice: dice, noise: noise, blooms: &blooms)
        for _ in 0..<dice.int(depth > 3 ? 1 : 0, depth > 2 ? 2 : 1) {
            let index = min(path.count - 1, Int(CGFloat(path.count) * dice.range(0.2, 0.9)))
            let t = CGFloat(index) / CGFloat(path.count)
            limb(canvas, from: path[index], angle: heading + dice.sign() * dice.range(0.5, 1.1),
                 length: length * dice.range(0.5, 0.75), thick: (thick + (endWidth - thick) * t) * dice.range(0.35, 0.55),
                 depth: depth - 1, dice: dice, noise: noise, blooms: &blooms)
        }
    }

    /// Straight young shoots off a thin limb, studded with blossoms and buds on alternating sides.
    private static func shoots(_ canvas: InkCanvas, along path: [CGPoint], thick: CGFloat, dice: Dice, blooms: inout [Bloom]) {
        let u = canvas.unit
        for _ in 0..<dice.int(2, 4) {
            let base = path[dice.int(path.count / 4, path.count - 1)]
            let angle = -.pi / 2 + dice.range(-0.85, 0.85)
            let length = dice.range(40, 120) * u
            let bend = dice.range(-0.12, 0.12)
            let tip = CGPoint(x: base.x + cos(angle) * length, y: base.y + sin(angle) * length)
            let mid = CGPoint(x: (base.x + tip.x) / 2 + cos(angle + .pi / 2) * length * bend, y: (base.y + tip.y) / 2 + sin(angle + .pi / 2) * length * bend)
            let stroke = SketchRenderer.smooth([base, mid, tip], steps: 10)
            let start = max(1.6 * u, thick * 0.45)
            canvas.brush(stroke, width: { t in start * (1 - t) + 0.7 * u }, alpha: 0.92)
            var along = dice.range(8, 16) * u
            var side: CGFloat = 1
            while along < length {
                let t = along / length
                let p = stroke[min(stroke.count - 1, Int(t * CGFloat(stroke.count - 1)))]
                let offset = CGPoint(x: cos(angle + .pi / 2) * side * 4 * u, y: sin(angle + .pi / 2) * side * 4 * u)
                blooms.append(Bloom(point: CGPoint(x: p.x + offset.x, y: p.y + offset.y),
                                    size: dice.chance(0.35) ? 0 : dice.range(0.75, 1.25) * (1 - t * 0.3), faint: dice.chance(0.2)))
                along += dice.range(9, 20) * u
                side = -side
            }
            blooms.append(Bloom(point: tip, size: 0, faint: false))
        }
    }

    /// A grey five-petal blossom with dark stamens, or (size 0) a dark bud.
    private static func blossom(_ canvas: InkCanvas, _ bloom: Bloom, dice: Dice) {
        let u = canvas.unit
        let c = bloom.point
        guard bloom.size > 0 else {
            canvas.dot(c, radius: dice.range(2.2, 3.8) * u, alpha: 0.95)
            return
        }
        let petal = 7.5 * u * bloom.size
        let turn = dice.range(0, 1.3)
        let wash: CGFloat = bloom.faint ? dice.range(0.14, 0.22) : dice.range(0.26, 0.42)
        // Some blossoms are seen side-on: three petals instead of five.
        let count = dice.chance(0.25) ? 3 : 5
        for k in 0..<count {
            let a = turn + CGFloat(k) * 2 * .pi / CGFloat(count)
            let reach = petal * dice.range(0.75, 0.95)
            canvas.dot(CGPoint(x: c.x + cos(a) * reach, y: c.y + sin(a) * reach), radius: petal * dice.range(0.8, 1.05), alpha: wash)
        }
        canvas.dot(c, radius: petal * 0.5, alpha: wash * 0.6)
        for _ in 0..<dice.int(4, 7) {
            let a = dice.range(0, 2 * .pi), r = petal * dice.range(0.55, 1.05)
            let tip = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            canvas.pen([c, tip], width: 0.6 * u, alpha: 0.75)
            canvas.dot(tip, radius: 1.1 * u, alpha: 0.95)
        }
        canvas.dot(c, radius: 1.4 * u, alpha: 0.9)
    }
}
