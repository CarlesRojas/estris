/** The features shown on the site, in order: each with its spot (an animation of `seconds`). */
export interface Feature {
  id: string;
  title: string;
  /** One line that sells it. */
  tagline: string;
  /** At most three short lines on how it works. */
  details: string;
  seconds: number;
}

export const features: Feature[] = [
  {
    id: "window-snapping",
    title: "Window Snapping",
    tagline: "Every window, exactly where you want it.",
    details: "Drag a window to an edge or a corner, or use ⌃⌥ shortcuts for halves, thirds and corners. One shortcut lines up every window on the screen.",
    seconds: 9,
  },
  {
    id: "clipboard",
    title: "Clipboard",
    tagline: "Everything you copy, one shortcut away.",
    details: "Hold ⌘⇧ and tap V to step back through what you copied, then let go to paste it. Text, images and files, with passwords left out.",
    seconds: 9,
  },
  {
    id: "volume-mixer",
    title: "Volume Mixer",
    tagline: "A volume knob for every app.",
    details: "Turn the music up and the browser down, mute one app, or send a call to your headphones. Right from the menu bar.",
    seconds: 8,
  },
  {
    id: "dock-preview",
    title: "Dock Preview",
    tagline: "See an app's windows before you click.",
    details: "Rest the pointer on an app in the Dock to see every window it has open, even on other desktops. Click one to go straight to it.",
    seconds: 8,
  },
  {
    id: "color-picker",
    title: "Color Picker",
    tagline: "Any color on your screen, copied in a click.",
    details: "Press ⌘⇧C, point and click. The color is copied as Hex, RGB, HSL or SwiftUI, and your recent colors stay a click away.",
    seconds: 7,
  },
  {
    id: "focus-follows-mouse",
    title: "Focus Follows Mouse",
    tagline: "Point at a window. It's ready.",
    details: "The window under the pointer comes forward, no click needed. Sweep quickly across others and they stay where they are.",
    seconds: 8,
  },
  {
    id: "keep-awake",
    title: "Keep Awake",
    tagline: "Your Mac stays awake for as long as you need.",
    details: "Keep the screen on for a set time or indefinitely, with separate choices on power and on battery.",
    seconds: 7,
  },
  {
    id: "remap",
    title: "Remap",
    tagline: "Make every key and button do what you want.",
    details: "Turn Caps Lock into Escape, or a mouse button into Mission Control. Each keyboard and mouse keeps its own mappings.",
    seconds: 7,
  },
  {
    id: "middle-click",
    title: "Middle Click",
    tagline: "The middle click, now on your trackpad.",
    details: "Tap with three fingers to open a link in a new tab or close one, just like clicking a mouse wheel.",
    seconds: 6,
  },
  {
    id: "auto-quit",
    title: "Auto Quit",
    tagline: "Close the last window, and the app goes too.",
    details: "Apps you're done with stop running in the background. Keep the ones you want open running with a simple list.",
    seconds: 7,
  },
];
