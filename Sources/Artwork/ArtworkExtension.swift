//
//  ArtworkExtension.swift
//  MusicExplorer
//
//  Created by Juhyeon Nam on 9/8/26.
//

import AppKit

extension NSColor {
    /// Returns a color mathematically adjusted to serve as an effective background,
    /// rather than relying on transparency over a gray background.
    func adaptiveBackgroundColor() -> NSColor {
        // Convert to standard RGB color space to safely read HSB values
        guard let rgbColor = self.usingColorSpace(.deviceRGB) else { return self }
        
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        
        rgbColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        
        // If saturation is extremely low, treat it as a grayscale color (black/white/gray)
        let isGrayscale = saturation < 0.05
        
        // 1. Fix Dark Colors
        if brightness < 0.3 {
            brightness = 0.35 // Minimum brightness floor
            
            // Only inject color if it already had a hue (prevents black from turning red)
            if !isGrayscale && saturation < 0.2 {
                saturation = 0.3
            }
        }
        // 2. Prevent bright colors from becoming pure white (dims to gray)
        else if brightness > 0.85 {
            brightness = 0.55
        }
        
        // 3. Boost vibrancy slightly for better background aesthetics,
        // BUT only if it actually has a color. Otherwise, keep it strictly gray.
        if !isGrayscale {
            saturation = min(saturation + 0.15, 1.0)
        } else {
            saturation = 0 // Force it to stay perfectly gray
        }
        
        return NSColor(deviceHue: hue, saturation: saturation, brightness: brightness, alpha: 1.0)
    }
}
