-- Autostart: procesos al iniciar Hyprland (barra, daemons, etc.).
-- https://wiki.hypr.land/Configuring/Basics/Autostart/

hl.on("hyprland.start", function()
    -- Barra / shell.
    hl.exec_cmd("quickshell")
    hl.exec_cmd("systemctl --user start hyprpolkitagent.service 2>/dev/null")
    hl.exec_cmd("command -v hypridle >/dev/null 2>&1 && hypridle")
end)
