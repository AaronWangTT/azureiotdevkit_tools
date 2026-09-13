# AZ3166 Arduino Board Package Index

This fork maintains the Arduino Board Manager index used by
[AaronWangTT/HomeTemperature](https://github.com/AaronWangTT/HomeTemperature).
It retains the archived Microsoft releases and adds maintained AZ3166 Core
releases whose artifacts are published from
[AaronWangTT/devkit-sdk](https://github.com/AaronWangTT/devkit-sdk).

## Validation

Run the structural check after editing the index:

```powershell
& .\tools\Test-PackageIndex.ps1
```

Before publishing a release entry, also download and verify the newest platform
archive and all tool dependencies for the target host:

```powershell
& .\tools\Test-PackageIndex.ps1 -VerifyArtifacts -ToolHost i686-mingw32
```

The validator requires every platform and tool-system archive to declare an
HTTPS URL, archive filename, checksum, and positive size. It also confirms that
each platform tool dependency resolves to exactly one definition. The GitHub
Actions workflow performs a clean Arduino IDE 1.8.19 Board Manager installation
of the newest platform on Windows and compiles a smoke sketch, preventing a
platform-only install from passing when its compiler or uploader is absent.

The legacy Windows GCC 5.4 toolchain cannot reliably resolve C++ headers from a
deep installation path. Keep portable IDE and CI extraction roots short; the
validation workflow rejects an unexpectedly long runner path before compiling.

Consumers should pin a raw index URL to a reviewed commit rather than tracking
the mutable branch head.