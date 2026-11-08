import QtQuick
import QtQuick.Effects

// A soft dark halo for text drawn straight on the backdrop, so it stays
// readable over a bright wallpaper or desktop. Use as a layer effect.
MultiEffect {
    shadowEnabled: true
    shadowColor: "black"
    // A tight, dense halo reads better behind small text than a wide one.
    blurMax: 16
    shadowBlur: 0.5
    shadowHorizontalOffset: 0
    shadowVerticalOffset: 1
    autoPaddingEnabled: true
}
