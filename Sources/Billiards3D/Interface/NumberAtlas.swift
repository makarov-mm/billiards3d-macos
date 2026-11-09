/// The numbers 1 to 15 for the balls, as coverage in a grid of 4 x 4 square cells of `cell` pixels, row by row from
/// the top: bold figures, two of them a little narrower to fit the circle, and a bar under the six and the nine so that
/// they are told apart.
@MainActor
enum NumberAtlas {
    static func render(cell: Int) -> [UInt8] {
        let size = cell * 4
        var coverage = [UInt8](repeating: 0, count: size * size)
        let fontSize = Int(Float(cell) * 0.62)
        let font = GlyphRasterizer.numberFont(size: Float(fontSize))
        let narrow = GlyphRasterizer.numberFont(size: Float(Int(Float(cell) * 0.56)))
        // The figures' height as Windows measures it: the em less the descent.
        let capHeight = Int((Float(fontSize) - GlyphRasterizer.descent(font)).rounded())

        for number in 1...15 {
            let x = (number - 1) % 4 * cell
            let y = (number - 1) / 4 * cell
            let text = String(number)
            let face = text.count > 1 ? narrow : font
            let baseline = y + (cell + capHeight) / 2
            let glyphs = text.unicodeScalars.compactMap { GlyphRasterizer.glyph(for: $0, in: face) }
            let bitmaps = glyphs.map { GlyphRasterizer.render($0.glyph, in: $0.font) }
            // Centered on the cell by the advances, as Windows centers text.
            var pen = x + cell / 2 - bitmaps.reduce(0) { $0 + $1.advance } / 2
            for bitmap in bitmaps {
                let left = pen + bitmap.left
                let top = baseline - bitmap.top
                for row in 0..<bitmap.height {
                    for column in 0..<bitmap.width {
                        let px = left + column
                        let py = top + row
                        guard (0..<size).contains(px), (0..<size).contains(py) else { continue }
                        let index = py * size + px
                        coverage[index] = max(coverage[index], bitmap.coverage[row * bitmap.width + column])
                    }
                }
                pen += bitmap.advance
            }
            if number == 6 || number == 9 {
                for py in (baseline + cell * 6 / 100)..<(baseline + cell * 12 / 100) {
                    for px in (x + cell * 36 / 100)..<(x + cell * 64 / 100) where (0..<size).contains(py) {
                        coverage[py * size + px] = 255
                    }
                }
            }
        }
        return coverage
    }
}
