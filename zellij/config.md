



Example config with custom `SmartCopy` patch. Just replace the whole default config with this
```
tychart@SOPCS-G0X7RT3(fedora44) ~ $ cat .config/zellij/config.kdl
keybinds {
    normal {
        bind "Ctrl c" { SmartCopy; }
    }

    scroll {
        bind "Ctrl c" { SmartCopy; }
    }
}

copy_on_select false
```
