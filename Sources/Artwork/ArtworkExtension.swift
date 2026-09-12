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
        
        // 1. Fix Dark Colors: If the color is too close to black, lift the brightness significantly.
        if brightness < 0.3 {
            brightness = 0.45 // Minimum brightness floor
            
            // If it's dark AND gray (low saturation), inject some color so it doesn't just look muddy gray
            if saturation < 0.2 {
                saturation = 0.3
            }
        }
        // 2. Optional: If the color is extremely bright, you might want to slightly dim it so white text remains readable.
        else if brightness > 0.85 {
            brightness = 0.75
        }
        
        // 3. Boost vibrancy slightly for better background aesthetics
        saturation = min(saturation + 0.15, 1.0)
        
        return NSColor(deviceHue: hue, saturation: saturation, brightness: brightness, alpha: 1.0)
    }
}
