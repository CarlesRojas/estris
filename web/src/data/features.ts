/** The features shown on the site, in order: each with its spot (an animation of `seconds`). */
export interface Feature {
  id: string;
  title: string;
  /** One line that sells it. */
  tagline: string;
  /** At most three short lines on how it works. */
  details: string;
  seconds: number;
  /** The colour of its glow on the page. */
  accent: string;
  /** Its icon in the list: SVG drawing on a 24 grid, in the current colour. */
  icon: string;
}

export const features: Feature[] = [
  {
    id: "window-snapping",
    title: "Window Snapping",
    tagline: "Every window, exactly where you want it.",
    details: "Drag a window to an edge or a corner, or use ⌃⌥ shortcuts for halves, thirds and corners. One shortcut lines up every window on the screen.",
    seconds: 10,
    accent: "#6ea8fe",
    icon: '<rect x="3" y="5" width="18" height="14" rx="2.5" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M12 5v14" stroke="currentColor" stroke-width="1.8"/>',
  },
  {
    id: "clipboard",
    title: "Clipboard",
    tagline: "Everything you copy, one shortcut away.",
    details: "Hold ⌘⇧ and tap V to step back through what you copied, then let go to paste it. Text, images and files, with passwords left out.",
    seconds: 12,
    accent: "#ffb867",
    icon: '<rect x="5.5" y="4.5" width="13" height="16" rx="2.5" fill="none" stroke="currentColor" stroke-width="1.8"/><rect x="9" y="2.8" width="6" height="3.4" rx="1.2" fill="currentColor"/>',
  },
  {
    id: "volume-mixer",
    title: "Volume Mixer",
    tagline: "A volume knob for every app.",
    details: "Turn the music up and the browser down, mute one app, or send a call to your headphones. Right from the menu bar.",
    seconds: 12,
    accent: "#f589a3",
    icon: '<path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4z" fill="currentColor"/><path d="M15.5 9a4.5 4.5 0 0 1 0 6M18 6.5a8 8 0 0 1 0 11" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
  },
  {
    id: "dock-preview",
    title: "Dock Preview",
    tagline: "See an app's windows before you click.",
    details: "Rest the pointer on an app in the Dock to see every window it has open, even on other desktops. Click one to go straight to it.",
    seconds: 10,
    accent: "#b794f6",
    icon: '<rect x="3" y="3.5" width="18" height="12" rx="2.5" fill="none" stroke="currentColor" stroke-width="1.8"/><rect x="6" y="18" width="12" height="3" rx="1.5" fill="currentColor"/>',
  },
  {
    id: "color-picker",
    title: "Color Picker",
    tagline: "Any color on your screen, copied in a click.",
    details: "Press ⌘⇧C, point and click. The color is copied as Hex, RGB, HSL or SwiftUI, and your recent colors stay a click away.",
    seconds: 8,
    accent: "#ff8a5c",
    icon: '<path d="M12 3.5c3 4 5.5 6.8 5.5 10a5.5 5.5 0 0 1-11 0c0-3.2 2.5-6 5.5-10z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>',
  },
  {
    id: "focus-follows-mouse",
    title: "Focus Follows Mouse",
    tagline: "Point at a window. It's ready.",
    details: "The window under the pointer comes forward, no click needed. Sweep quickly across others and they stay where they are.",
    seconds: 9,
    accent: "#6fd39a",
    icon: '<path d="M6 3.5v14.3l3.9-3.7 2.6 5.8 2.4-1.1-2.6-5.6h5.5z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>',
  },
  {
    id: "keep-awake",
    title: "Keep Awake",
    tagline: "Your Mac stays awake for as long as you need.",
    details: "Keep the screen on for a set time or indefinitely, with separate choices on power and on battery.",
    seconds: 6,
    accent: "#f5c451",
    icon: '<path d="M4.5 9h11v4.5a5 5 0 0 1-5 5h-1a5 5 0 0 1-5-5zM15.5 10.5h1.5a2.5 2.5 0 0 1 0 5h-1.5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M8 3.5c-.8 1 .8 1.6 0 2.8M12 3.5c-.8 1 .8 1.6 0 2.8" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>',
  },
  {
    id: "rounded-corners",
    title: "Rounded Corners",
    tagline: "Rounded corners for any screen.",
    details: "Turn it on and the corners of every screen round off, as round as your windows. A slider makes them rounder or subtler.",
    seconds: 8,
    accent: "#4fd1c5",
    icon: '<path d="M3.5 9.5V7.5a4 4 0 0 1 4-4h2M14.5 3.5h2a4 4 0 0 1 4 4v2M20.5 14.5v2a4 4 0 0 1-4 4h-2M9.5 20.5h-2a4 4 0 0 1-4-4v-2" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
  },
  {
    id: "remap",
    title: "Remap",
    tagline: "Make every key and button do what you want.",
    details: "Turn Caps Lock into Escape, or a mouse button into Mission Control. Each keyboard and mouse keeps its own mappings.",
    seconds: 6,
    accent: "#7cc8f0",
    icon: '<rect x="2.5" y="6" width="19" height="12" rx="2.5" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M6.5 10h1M10.5 10h1M14.5 10h1M8 14h8" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
  },
  {
    id: "middle-click",
    title: "Middle Click",
    tagline: "The middle click, now on your trackpad.",
    details: "Tap with three fingers to open a link in a new tab or close one, just like clicking a mouse wheel.",
    seconds: 8,
    accent: "#9d9bf0",
    icon: '<circle cx="6.5" cy="13" r="2" fill="currentColor"/><circle cx="12" cy="10" r="2" fill="currentColor"/><circle cx="17.5" cy="13" r="2" fill="currentColor"/>',
  },
  {
    id: "auto-quit",
    title: "Auto Quit",
    tagline: "Close the last window, and the app goes too.",
    details: "Apps you're done with stop running in the background. Keep the ones you want open running with a simple list.",
    seconds: 10,
    accent: "#ff7b72",
    icon: '<rect x="4" y="4" width="16" height="16" rx="3.5" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M9.5 9.5l5 5M14.5 9.5l-5 5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
  },
];

/** How many tools, as a word ("eleven"), for copy that names the count. */
export const toolCount =
  ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen"][features.length] ??
  String(features.length);

/** The same, capitalized to start a sentence. */
export const ToolCount = toolCount[0].toUpperCase() + toolCount.slice(1);
