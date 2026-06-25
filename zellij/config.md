



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


Link to patched zellij binary:
https://drive.google.com/file/d/1zDVZ42TuboRkjGTFV2ytEh8ljOl8C5RV/view?usp=drive_link
