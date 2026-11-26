#!/usr/bin/env python3
"""Generate the Xcode project and audio resources with Python's standard library."""
from pathlib import Path
import hashlib
import json
import math
import struct
import wave
import zlib

ROOT = Path(__file__).resolve().parent.parent
objects = {}

def ident(key):
    return hashlib.sha1(key.encode()).hexdigest()[:24].upper()

def add(key, **values):
    token = ident(key)
    objects[token] = values
    return token

def config_list(key, settings):
    configs = []
    for name in ("Debug", "Release"):
        values = dict(settings)
        values["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone" if name == "Debug" else "-O"
        values["DEBUG_INFORMATION_FORMAT"] = "dwarf" if name == "Debug" else "dwarf-with-dsym"
        if name == "Debug":
            values["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
            values["ENABLE_TESTABILITY"] = "YES"
        configs.append(add(key + name, isa="XCBuildConfiguration", buildSettings=values, name=name))
    return add(key + "configs", isa="XCConfigurationList", buildConfigurations=configs,
               defaultConfigurationIsVisible=0, defaultConfigurationName="Release")

project_id = ident("project")
app_id = ident("Tempo-target")
targets = []
groups = []
products = []

for name, folder, is_test in [("Tempo", "Tempo", False), ("TempoActivity", "TempoActivity", False), ("TempoUITests", "TempoUITests", True)]:
    is_widget = name == "TempoActivity"
    sources = []
    resources = []
    references = []
    files = sorted((ROOT / folder).rglob("*.swift"))
    if not is_test:
        files += sorted((ROOT / "Shared").glob("*.swift"))
    if not is_test and not is_widget:
        files += [ROOT / "Tempo/Resources/Assets.xcassets"]
        files += [ROOT / f"Tempo/Resources/{tone}.wav" for tone in ("countdown", "transition", "complete")]
    for file in files:
        path = str(file.relative_to(ROOT))
        kind = "sourcecode.swift" if file.suffix == ".swift" else "folder.assetcatalog" if file.suffix == ".xcassets" else "audio.wav"
        key = name + path if path.startswith("Shared/") else path
        ref = add(key, isa="PBXFileReference", lastKnownFileType=kind, path=path, sourceTree="SOURCE_ROOT")
        references.append(ref)
        build = add(key + "build", isa="PBXBuildFile", fileRef=ref)
        (sources if file.suffix == ".swift" else resources).append(build)
    groups.append(add(name + "group", isa="PBXGroup", children=references, name=name, sourceTree="<group>"))
    product = add(name + "product", isa="PBXFileReference", explicitFileType="wrapper.cfbundle" if is_test else "wrapper.app-extension" if is_widget else "wrapper.application",
                  includeInIndex=0, path=name + (".xctest" if is_test else ".appex" if is_widget else ".app"), sourceTree="BUILT_PRODUCTS_DIR")
    products.append(product)
    phases = [add(name + "sources", isa="PBXSourcesBuildPhase", buildActionMask=2147483647, files=sources, runOnlyForDeploymentPostprocessing=0),
              add(name + "frameworks", isa="PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0),
              add(name + "resources", isa="PBXResourcesBuildPhase", buildActionMask=2147483647, files=resources, runOnlyForDeploymentPostprocessing=0)]
    settings = {
        "PRODUCT_BUNDLE_IDENTIFIER": "com.yograo.tempo.uitests" if is_test else "com.yograo.tempo.activity" if is_widget else "com.yograo.tempo",
        "PRODUCT_NAME": "$(TARGET_NAME)", "GENERATE_INFOPLIST_FILE": "YES", "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": "1,2", "CODE_SIGN_STYLE": "Automatic", "CURRENT_PROJECT_VERSION": "2",
        "MARKETING_VERSION": "1.1", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
    }
    dependencies = []
    if is_test:
        settings["TEST_TARGET_NAME"] = "Tempo"
        proxy = add("testProxy", isa="PBXContainerItemProxy", containerPortal=project_id, proxyType=1, remoteGlobalIDString=app_id, remoteInfo="Tempo")
        dependencies = [add("testDependency", isa="PBXTargetDependency", target=app_id, targetProxy=proxy)]
    elif is_widget:
        settings.update({"INFOPLIST_FILE": "TempoActivity/Info.plist", "SKIP_INSTALL": "YES",
                         "APPLICATION_EXTENSION_API_ONLY": "YES",
                         "INFOPLIST_KEY_CFBundleDisplayName": "Tempo workout"})
    else:
        settings.update({
            "INFOPLIST_FILE": "Tempo/Info.plist",
            "INFOPLIST_KEY_NSSupportsLiveActivities": "YES",
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "INFOPLIST_KEY_CFBundleDisplayName": "Tempo",
            "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "NO",
            "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
            "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
            "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
            "INFOPLIST_KEY_UIRequiresFullScreen": "YES",
            "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
        })
    if name == "Tempo":
        widget_id = ident("TempoActivity-target")
        proxy = add("widgetProxy", isa="PBXContainerItemProxy", containerPortal=project_id, proxyType=1, remoteGlobalIDString=widget_id, remoteInfo="TempoActivity")
        dependencies.append(add("widgetDependency", isa="PBXTargetDependency", target=widget_id, targetProxy=proxy))
        embed = add("embedWidget", isa="PBXBuildFile", fileRef=ident("TempoActivityproduct"), settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})
        phases.append(add("embedExtensions", isa="PBXCopyFilesBuildPhase", buildActionMask=2147483647, dstPath="", dstSubfolderSpec=13, files=[embed], name="Embed App Extensions", runOnlyForDeploymentPostprocessing=0))
    targets.append(add(name + "-target", isa="PBXNativeTarget", buildConfigurationList=config_list(name, settings), buildPhases=phases,
                       buildRules=[], dependencies=dependencies, name=name, productName=name, productReference=product,
                       productType="com.apple.product-type.bundle.ui-testing" if is_test else "com.apple.product-type.app-extension" if is_widget else "com.apple.product-type.application"))

products_group = add("products", isa="PBXGroup", children=products, name="Products", sourceTree="<group>")
main_group = add("main", isa="PBXGroup", children=groups + [products_group], sourceTree="<group>")
add("project", isa="PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "1600"},
    buildConfigurationList=config_list("project", {"SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES"}),
    compatibilityVersion="Xcode 14.0", developmentRegion="en", hasScannedForEncodings=0, knownRegions=["en", "Base"],
    mainGroup=main_group, productRefGroup=products_group, projectDirPath="", projectRoot="", targets=targets)

def encode(value, depth=0):
    if isinstance(value, dict):
        return "{\n" + "".join("\t" * (depth + 1) + json.dumps(k) + " = " + encode(v, depth + 1) + ";\n" for k, v in value.items()) + "\t" * depth + "}"
    if isinstance(value, list):
        return "(" + ", ".join(encode(v, depth) for v in value) + ")"
    return str(value) if isinstance(value, int) else json.dumps(value)

project = ROOT / "Tempo.xcodeproj"
project.mkdir(exist_ok=True)
(project / "project.pbxproj").write_text("// !$*UTF8*$!\n" + encode({"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": project_id}) + "\n")
schemes = project / "xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
def reference(name):
    product = name + (".app" if name == "Tempo" else ".xctest")
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident(name + "-target")}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:Tempo.xcodeproj"/>'
(schemes / "Tempo.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference("Tempo")}</BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{reference("TempoUITests")}</TestableReference></Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference("Tempo")}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release"><BuildableProductRunnable runnableDebuggingMode="0">{reference("Tempo")}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')

for name, duration, frequency in [("countdown", 0.10, 660), ("transition", 0.24, 880), ("complete", 1.35, 1046.5)]:
    rate = 44100
    frames = []
    for index in range(int(rate * duration)):
        t = index / rate
        envelope = min(1, t / 0.008, (duration - t) / 0.035)
        value = 0.42 * envelope * math.sin(2 * math.pi * frequency * t)
        frames.append(struct.pack("<h", int(value * 32767)))
    with wave.open(str(ROOT / f"Tempo/Resources/{name}.wav"), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes(b"".join(frames))

assets = ROOT / "Tempo/Resources/Assets.xcassets"
(assets / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))
icon = assets / "AppIcon.appiconset"
icon.mkdir(exist_ok=True)
(icon / "Contents.json").write_text(json.dumps({
    "images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
    "info": {"author": "xcode", "version": 1}
}, indent=2))

def segment_distance(x, y, ax, ay, bx, by):
    projection = max(0, min(1, ((x-ax)*(bx-ax)+(y-ay)*(by-ay))/((bx-ax)**2+(by-ay)**2)))
    return math.hypot(x - ax - projection*(bx-ax), y - ay - projection*(by-ay))

pixels = bytearray()
for y in range(1024):
    pixels.append(0)
    for x in range(1024):
        radius = math.hypot(x-512, y-538)
        angle = math.degrees(math.atan2(y-538, x-512))
        ring = abs(radius-267)-34 if not -85 < angle < -47 else 1000
        hand = segment_distance(x, y, 512, 538, 615, 373)-29
        crown = segment_distance(x, y, 468, 192, 550, 192)-25
        distance = min(ring, hand, crown)
        coverage = max(0, min(1, 0.5-distance))
        pixels.extend(round(background*(1-coverage)+foreground*coverage) for background, foreground in zip((210, 240, 107), (33, 43, 41)))

def png_chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind+data) & 0xffffffff)

(icon / "AppIcon.png").write_bytes(b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", struct.pack(">IIBBBBB", 1024, 1024, 8, 2, 0, 0, 0)) + png_chunk(b"IDAT", zlib.compress(pixels)) + png_chunk(b"IEND", b""))
print("Generated Tempo.xcodeproj, app icon, and three audio cues.")
