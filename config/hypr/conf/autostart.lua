-- https://wiki.hypr.land/Configuring/Basics/Autostart/

hl.on("hyprland.start", function()
    hl.exec_cmd("quickshell")
    hl.exec_cmd("command -v hypridle >/dev/null 2>&1 && hypridle")
end)
