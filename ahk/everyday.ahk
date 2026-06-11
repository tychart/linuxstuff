#Requires AutoHotkey v2.0
#SingleInstance Force

ScreenSizeX := 1920
NumScreens := 2

^+z:: ExitApp

^!l:: DllCall("user32.dll\LockWorkStation")

^!Up:: WinMaximize("A")
^!Down:: WinRestore("A")

; Reverse Scrolling Direction
; WheelDown::WheelUp
; WheelUp::WheelDown

^+!v:: Send("{Raw}" A_Clipboard) ; Type the clipboard

^!Right:: {
    WinGetPos(&X, &Y, , , "A")
    if (X + ScreenSizeX < ScreenSizeX * NumScreens) {
        WinMove(X + ScreenSizeX, , , , "A")
    }
}

^!Left:: {
    WinGetPos(&X, &Y, , , "A")
    if (X - ScreenSizeX > 0) {
        WinMove(X - ScreenSizeX, , , , "A")
    }
}

typeYoda() {
    SendInput("@")
    Sleep(50)
    Send("yoda")
}

typeTarkin() {
    SendInput("@")
    Sleep(50)
    Send("tarkin")
}

^+y:: typeYoda()
; ^+t::typeTarkin()

^!t:: Run("wt")

^!u:: Send("ty.chart")

Pause::Media_Play_Pause

; Maybe have shift scroll on chrome scroll between tabs

+WheelUp:: activate_scroll_tab("+")
+WheelDown:: activate_scroll_tab("-")

scroll_tab(direction) {
    if (direction == "+") {
        Send("^{Tab}")
    } else {
        Send("^+{Tab}")
    }
}

activate_scroll_tab(direction) {
    MouseGetPos(, , &currMouseHoveringWindow)
    ; MsgBox(WinGetProcessName(currMouseHoveringWindow))
    if ("chrome.exe" == WinGetProcessName(currMouseHoveringWindow)) {
        ; MsgBox("It was chrome!!!")
        if (currMouseHoveringWindow != WinActive()) { ; The window currently being hovered over is also active
            WinActivate(currMouseHoveringWindow)
        }
        scroll_tab(direction)

        ; MsgBox(currMouseHoveringWindow)
    }
}

^+!o:: Send("Password")
^+o:: Send("Password")

^space::
{
    WinSetAlwaysOnTop -1, "A"
}
