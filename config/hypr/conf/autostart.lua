-- ── Autostart ───────────────────────────────────────────────
-- https://wiki.hypr.land/Configuring/Basics/Autostart/
-- Procesos a lanzar al iniciar Hyprland (barra, daemons, etc.).

hl.on("hyprland.start", function()
    -- Barra / shell.
    hl.exec_cmd("quickshell")

    -- Agente PolicyKit: diálogos gráficos de contraseña de admin.
    -- Requiere el paquete 'hyprpolkitagent' (2>/dev/null calla si falta).
    hl.exec_cmd("systemctl --user start hyprpolkitagent.service 2>/dev/null")

    -- Gestión de inactividad (apagar pantalla, bloquear, suspender).
    -- Requiere 'hypridle' + 'hyprlock'. Se autoarranca cuando lo instales.
    hl.exec_cmd("command -v hypridle >/dev/null 2>&1 && hypridle")

    -- swww-daemon lo lanza solo el servicio Wallpaper de Quickshell;
    -- solo falta instalar el paquete 'swww'.
end)
