# Layout of Estris.dmg's window, for dmgbuild (scripts/make-dmg.sh passes app and background).
# Positions are icon centres, in points from the window's top left, matching the arrow in
# Resources/DMG/background.svg.
app = defines["app"]

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extensions = ["Estris.app"]
icon = "Resources/AppIcon.icns"

background = defines["background"]
window_rect = ((200, 160), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 13
icon_locations = {
    "Estris.app": (180, 190),
    "Applications": (480, 190),
}
