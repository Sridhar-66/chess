// SPDX-License-Identifier: GPL-3.0-or-later
.pragma library

// One colour walked towards another, so nothing in the app ever writes a colour: both come from the
// palette and the mix carries it too.
function mix(a, b, t) {
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1.0);
}
