# Mouse Pad

Use your Android phone as a laptop-style **touchpad and keyboard** for your
Windows PC, over a **USB cable** or **Bluetooth**. Built with Flutter.

- Landscape touchpad with Left/Right click buttons, tap to click, two-finger
  scroll, pinch to zoom and Windows-style three/four-finger swipes
- Keyboard: type with your phone's keyboard, plus Esc, Tab, Ctrl, Alt, Win,
  arrows and F1–F12
- Over USB the phone keyboard pops up by itself when you click into a text box
  on the PC
- Pointer and scroll speed sliders

The PC side for USB is a separate app:
**[Mouse Pad Receiver](https://github.com/SHiT7776/Mouse-Pad-Reciever)**.
Bluetooth needs nothing on the PC.

## Install

With [Flutter](https://docs.flutter.dev/get-started/install) installed and the
phone plugged in (USB debugging on):

```
flutter build apk --release
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

## Connect with a USB cable

1. On the phone, turn on **USB debugging**: Settings › About phone › tap
   "Build number" (Xiaomi: "OS version") 7 times, then Developer options ›
   USB debugging.
2. On the PC, install and open
   [Mouse Pad Receiver](https://github.com/SHiT7776/Mouse-Pad-Reciever).
3. Plug the phone in and tap **Allow** on the phone.
4. In the app choose **USB cable**, then tap **Touchpad**.

## Connect with Bluetooth (no PC app needed)

1. In the app choose **Bluetooth** › **Choose PC** › **Make phone visible**.
2. On the PC: Settings › Bluetooth & devices › Add device › Bluetooth, pick the
   phone and confirm the code.
3. After that the phone reconnects by itself whenever you open the app.

The phone then works like a Bluetooth mouse and keyboard. Needs Android 9 or
newer, and a phone that allows apps to act as one. Over Bluetooth the keyboard
types US-layout characters only (no ñ or emoji), and it doesn't pop up by
itself.

If Bluetooth lags or drops:

- On the PC: Device Manager › Bluetooth › your Bluetooth adapter › Properties ›
  Power Management › untick "Allow the computer to turn off this device to save
  power".
- On the phone (Xiaomi/Redmi): Settings › Apps › Mouse Pad › Battery saver ›
  No restrictions.
- If the PC's Wi-Fi uses 2.4 GHz, switching to 5 GHz frees up the radio that
  Bluetooth shares.

## Touchpad

| Do this | To |
| --- | --- |
| Move one finger | Move the pointer |
| Left click / Right click buttons | Click (hold Left and move with another finger to drag) |
| Tap | Click |
| Double-tap | Double-click (open) |
| Tap, then touch again and drag | Drag |
| Two-finger tap | Right-click |
| Three-finger tap | Middle-click |
| Two-finger drag | Scroll |
| Pinch | Zoom |
| Three fingers up / down | Task View / show the desktop |
| Three fingers left or right | Switch to the previous app |
| Four fingers left or right | Switch virtual desktops |

## Keyboard

- Tap **Keyboard** on the home screen, or on the touchpad's top bar.
- Ctrl / Shift / Alt / Win apply to the next key you press. Long-press one to
  press it alone (Win alone opens Start).

## Development

```
flutter analyze
flutter test
```

`lib/protocol.dart` is the message format shared with Mouse Pad Receiver. If
you change it, change it in both repos.
