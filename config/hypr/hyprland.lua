-- ╔══════════════════════════════════════════════════════════╗
-- ║   HYPRLAND · Configuración modular (API Lua)               ║
-- ║   https://wiki.hypr.land/Configuring/Start/                ║
-- ║                                                            ║
-- ║   Este archivo solo orquesta. La configuración real vive   ║
-- ║   en conf/*.lua para mantenerla ordenada y optimizada.     ║
-- ╚══════════════════════════════════════════════════════════╝

-- Permite require("conf.<modulo>") buscando en ~/.config/hypr/
local base = (os.getenv("HOME") or "") .. "/.config/hypr/"
package.path = base .. "?.lua;" .. base .. "conf/?.lua;" .. package.path

-- Orden de carga (las dependencias van primero).
require("monitors")      -- salidas / pantallas
require("environment")   -- variables de entorno
require("looknfeel")     -- general, decoración, layouts, misc
require("animations")    -- curvas y animaciones
require("input")         -- teclado, ratón, gestos
require("keybinds")      -- atajos
require("windowrules")   -- reglas de ventana
require("autostart")     -- procesos al inicio
