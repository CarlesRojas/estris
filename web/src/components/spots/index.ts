import WindowSnapping from "./WindowSnapping.astro";
import Clipboard from "./Clipboard.astro";
import VolumeMixer from "./VolumeMixer.astro";
import DockPreview from "./DockPreview.astro";
import ColorPicker from "./ColorPicker.astro";
import FocusFollowsMouse from "./FocusFollowsMouse.astro";
import KeepAwake from "./KeepAwake.astro";
import RoundedCorners from "./RoundedCorners.astro";
import Remap from "./Remap.astro";
import MiddleClick from "./MiddleClick.astro";
import AutoQuit from "./AutoQuit.astro";
import DeleteToTrash from "./DeleteToTrash.astro";

/** Each feature's spot, by feature id. */
export const spots: Record<string, any> = {
  "window-snapping": WindowSnapping,
  clipboard: Clipboard,
  "volume-mixer": VolumeMixer,
  "dock-preview": DockPreview,
  "color-picker": ColorPicker,
  "focus-follows-mouse": FocusFollowsMouse,
  "keep-awake": KeepAwake,
  "rounded-corners": RoundedCorners,
  remap: Remap,
  "middle-click": MiddleClick,
  "auto-quit": AutoQuit,
  "delete-to-trash": DeleteToTrash,
};
