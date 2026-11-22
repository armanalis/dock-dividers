<p align="center">
  <img src="icon-preview.png" width="128" alt="Dock Dividers icon">
</p>

<h1 align="center">Dock Dividers</h1>

<p align="center">
  Native-looking divider lines anywhere in the macOS Dock, so you can group your apps.<br>
  macOS Dock'un istediğin yerine native görünümlü ayraç çizgileri koyar, uygulamalarını gruplarsın.
</p>

<p align="center">
  <img src="docs/screenshot-dock.png" alt="Dock with a thin divider line between Calculator and Weather, next to the built-in separator before the Trash">
</p>

<table>
  <tr>
    <td width="40%"><img src="docs/screenshot-editor.png" alt="Editor window: Dock apps in a list with a divider row between Calculator and Weather, Add Divider and Apply buttons"></td>
    <td>
      <b>Drag to arrange</b><br>
      Every Dock app and divider in one list. Drag a divider between any two apps, or drag an app between two dividers, then press <b>Dock'a Uygula</b> (Apply).<br><br>
      <b>Sürükle, sırala</b><br>
      Dock'taki tüm uygulamalar ve ayraçlar tek listede. Ayracı istediğin iki uygulamanın arasına, uygulamayı iki ayracın arasına sürükle, sonra <b>Dock'a Uygula</b>'ya bas.
    </td>
  </tr>
</table>

## Install / Kurulum

Requires macOS 13+ and Xcode Command Line Tools.

```bash
git clone https://github.com/armanalis/dock-dividers.git
cd dock-dividers
./build.sh
open "/Applications/Dock Dividers.app"
```

Then allow it in **System Settings → Privacy & Security → Accessibility**. It needs this to read where the Dock's icons are.

Kurulumdan sonra **Sistem Ayarları → Gizlilik ve Güvenlik → Erişilebilirlik**'te izin ver. Dock ikonlarının yerini okumak için gerekli.

## How it works

1. **Ayraç Ekle** (Add Divider) inserts Apple's own `small-spacer-tile` into the Dock: a half-icon-wide gap.
2. The app reads each spacer's position through the Accessibility API (`AXSpacerDockItem`).
3. A transparent, click-through window draws a thin line over each spacer, styled like the built-in separator and matching light/dark mode.

It runs from the menu bar (vertical line icon): **Düzenle…** opens the editor, **Girişte Başlat** starts it at login.

## Limits

- Bottom Dock only; left/right Dock is not supported.
- Lines follow the Dock 3× per second, so they lag behind **Dock magnification**. Turn magnification off for a clean look.
- Rebuilding with an ad-hoc signature resets the Accessibility permission. `build.sh` uses a local code signing identity named `Dock Dividers Local Signing` if your keychain has one.

## License

MIT
