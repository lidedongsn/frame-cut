import CoreGraphics
import FCCore

public enum RenderSize {
    /// 按画幅与短边计算输出像素尺寸（偶数）。
    public static func size(aspect: AspectRatio, shortSide: Int) -> CGSize {
        func even(_ v: Double) -> Int { Int((v / 2).rounded()) * 2 }
        let r = aspect.ratio
        if r >= 1 {
            return CGSize(width: even(Double(shortSide) * r), height: shortSide)
        }
        return CGSize(width: shortSide, height: even(Double(shortSide) / r))
    }
}
