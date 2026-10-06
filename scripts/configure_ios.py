#!/usr/bin/env python3
"""Configure the generated Flutter iOS project for DIGNI SCANNER."""

from pathlib import Path
import plistlib
import re

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "ios"
PLIST = IOS / "Runner" / "Info.plist"
PODFILE = IOS / "Podfile"
PROJECT = IOS / "Runner.xcodeproj" / "project.pbxproj"

for required in (PLIST, PODFILE, PROJECT):
    if not required.is_file():
        raise SystemExit(f"Missing {required}; run flutter create --platforms=ios first")

with PLIST.open("rb") as handle:
    info = plistlib.load(handle)
info["CFBundleDisplayName"] = "DIGNI SCANNER"
info["NSCameraUsageDescription"] = (
    "DIGNI SCANNER necesita la cámara para leer entradas y cédulas en eventos autorizados."
)
with PLIST.open("wb") as handle:
    plistlib.dump(info, handle, sort_keys=False)

podfile = PODFILE.read_text()
platform_line = "platform :ios, '15.5'"
updated, count = re.subn(
    r"(?m)^\s*#?\s*platform\s+:ios,\s*['\"][^'\"]+['\"].*$",
    platform_line,
    podfile,
    count=1,
)
PODFILE.write_text(updated if count else platform_line + "\n" + podfile)

project = PROJECT.read_text()
project, target_count = re.subn(
    r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;",
    "IPHONEOS_DEPLOYMENT_TARGET = 15.5;",
    project,
)
if target_count == 0:
    raise SystemExit("Could not set the iOS deployment target")
project = project.replace("cl.digni.digniScanner", "cl.digni.scanner")
PROJECT.write_text(project)
print("Configured DIGNI SCANNER for iOS 15.5+, camera scanning, and app identity")
