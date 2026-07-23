# PLCrashReporter

WCLiquidGlass vendors the iOS device static library from Microsoft PLCrashReporter 1.12.0 under its MIT license.

The archive is rebuilt from the official `1.12.0` source with:

```sh
GCC_PREPROCESSOR_DEFINITIONS='$(inherited) PLCRASHREPORTER_PREFIX=WCLG_'
```

All exported Objective-C and C symbols therefore use the `WCLG_` prefix. Do not replace `CrashReporter` with the unprefixed release binary: WeChat or another injected plugin may already contain PLCrashReporter, and duplicate Objective-C class names can make the diagnostic component itself unsafe.

Only the `arm64` iOS device slice is stored because this project emits an `iphoneos-arm64` tweak.
