Example config with custom `ctrl + w` behavior instead of `ctrl + backspace` with the command and the keybinding 

```
{
    "$help": "https://aka.ms/terminal-documentation",
    "$schema": "https://aka.ms/terminal-profiles-schema",
    "actions": 
    [
        {
            "command": 
            {
                "action": "sendInput",
                "input": "\u0017"
            },
            "id": "User.sendInput.817164EE",
            "name": "Send Ctrl-W instead of ctrl + backspace to delete previous word"
        }
    ],
    "compatibility.enableUnfocusedAcrylic": true,
    "copyFormatting": "none",
    "copyOnSelect": false,
    "defaultProfile": "{913654f8-d08c-5340-9768-7bcc5cc5fabd}",
    "keybindings": 
    [
        {
            "id": "Terminal.CopyToClipboard",
            "keys": "ctrl+c"
        },
        {
            "id": "Terminal.FindText",
            "keys": "ctrl+shift+f"
        },
        {
            "id": "Terminal.PasteFromClipboard",
            "keys": "ctrl+v"
        },
        {
            "id": "Terminal.DuplicatePaneAuto",
            "keys": "alt+shift+d"
        },
        {
            "id": "User.sendInput.817164EE",
            "keys": "ctrl+backspace"
        }
    ],
```
