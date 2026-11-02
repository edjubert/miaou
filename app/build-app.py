#!/usr/bin/env python3
"""Build and install Miaou with its native WidgetKit extension."""
import os
import plistlib
import re
import shutil
import signal
import subprocess
import sys
from pathlib import Path

APP = Path(__file__).resolve().parent
BUILD = APP / ".build/native-app"
BUNDLE_ID = "com.edjubert.Miaou"
WIDGET_ID = BUNDLE_ID + ".widget"
LSREGISTER = ("/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/"
              "LaunchServices.framework/Versions/Current/Support/lsregister")


def run(*arguments, **kwargs):
    return subprocess.run(arguments, check=True, **kwargs)


def signing():
    identity = os.environ.get("SIGN_IDENTITY", "")
    team = os.environ.get("TEAM_ID", "")
    if not identity:
        identities = run("security", "find-identity", "-v", "-p", "codesigning",
                         capture_output=True, text=True).stdout
        match = re.search(r'"(Apple Development:[^"]+)"', identities)
        identity = match[1] if match else "-"
    if identity != "-" and not team:
        certificate = run("security", "find-certificate", "-c", identity, "-p",
                          capture_output=True).stdout
        subject = run("openssl", "x509", "-noout", "-subject", input=certificate,
                      capture_output=True).stdout.decode()
        match = re.search(r"(?:/|,\s*)OU\s*=\s*([A-Z0-9]+)", subject)
        if not match:
            raise SystemExit("Set TEAM_ID for the selected signing identity.")
        team = match[1]
    group = os.environ.get("APP_GROUP", f"{team}.com.edjubert.miaou" if team else
                           "group.com.edjubert.miaou")
    return identity, team, group


def project(identity, team):
    objects = {}

    def obj(kind, **fields):
        identifier = f"{len(objects) + 1:024X}"
        objects[identifier] = {"isa": kind, **fields}
        return identifier

    def configuration(settings):
        value = obj("XCBuildConfiguration", name="Release", buildSettings=settings)
        return obj("XCConfigurationList", buildConfigurations=[value],
                   defaultConfigurationIsVisible="0", defaultConfigurationName="Release")

    shared = sorted((APP / "Shared").glob("*.swift"))
    app_sources = sorted((APP / "Sources/Miaou").glob("*.swift")) + shared
    widget_sources = [APP / "Widget/MiaouWidget.swift"] + shared + [
        APP / "Sources/Miaou" / name for name in ["L10n.swift", "MistralLogo.swift", "Chaton.swift"]]
    references = {
        path: obj("PBXFileReference", lastKnownFileType="sourcecode.swift",
                  path=str(path), sourceTree="<absolute>")
        for path in dict.fromkeys(app_sources + widget_sources)
    }
    languages = [
        obj("PBXFileReference", lastKnownFileType="text.plist.strings", name=language,
            path=str(APP / f"Sources/Miaou/Resources/{language}.lproj/Localizable.strings"),
            sourceTree="<absolute>")
        for language in ["en", "fr"]
    ]
    strings = obj("PBXVariantGroup", name="Localizable.strings", children=languages, sourceTree="<group>")
    products, targets = [], []
    for name, sources, suffix, product_type in [
        ("Miaou", app_sources, "app", "com.apple.product-type.application"),
        ("MiaouWidget", widget_sources, "appex", "com.apple.product-type.app-extension"),
    ]:
        extension = suffix == "appex"
        product = obj("PBXFileReference",
                      explicitFileType="wrapper.app-extension" if extension else "wrapper.application",
                      path=f"{name}.{suffix}", sourceTree="BUILT_PRODUCTS_DIR")
        products.append(product)
        sources_phase = obj("PBXSourcesBuildPhase", buildActionMask="2147483647",
                            files=[obj("PBXBuildFile", fileRef=references[path]) for path in sources],
                            runOnlyForDeploymentPostprocessing="0")
        resources_phase = obj("PBXResourcesBuildPhase", buildActionMask="2147483647",
                              files=[obj("PBXBuildFile", fileRef=strings)],
                              runOnlyForDeploymentPostprocessing="0")
        settings = {
            "PRODUCT_NAME": name,
            "PRODUCT_BUNDLE_IDENTIFIER": WIDGET_ID if extension else BUNDLE_ID,
            "INFOPLIST_FILE": str(APP / ("Widget/Info.plist" if extension else "Info.plist")),
            "CODE_SIGNING_ALLOWED": "NO",
            "SWIFT_VERSION": "5.0",
            "MACOSX_DEPLOYMENT_TARGET": "14.0" if extension else "13.0",
            "SDKROOT": "macosx",
            "ARCHS": "arm64",
            "SWIFT_OPTIMIZATION_LEVEL": "-O",
            "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks",
            "GENERATE_INFOPLIST_FILE": "NO",
            "ALWAYS_SEARCH_USER_PATHS": "NO",
            "REGISTER_APP_WITH_LAUNCH_SERVICES": "NO",
        }
        if extension:
            settings.update(APPLICATION_EXTENSION_API_ONLY="YES", SKIP_INSTALL="YES",
                            SWIFT_ACTIVE_COMPILATION_CONDITIONS="MIAOU_WIDGET")
        if identity != "-":
            settings.update(CODE_SIGNING_ALLOWED="YES", CODE_SIGN_STYLE="Automatic",
                            DEVELOPMENT_TEAM=team, CODE_SIGN_IDENTITY=identity.split(":")[0],
                            ENABLE_HARDENED_RUNTIME="YES",
                            CODE_SIGN_ENTITLEMENTS=str(APP / (
                                "Widget/MiaouWidget.entitlements" if extension else "Miaou.entitlements")))
        targets.append(obj("PBXNativeTarget", name=name, productName=name, productReference=product,
                           productType=product_type, buildConfigurationList=configuration(settings),
                           buildPhases=[sources_phase, resources_phase], buildRules=[], dependencies=[]))
    proxy = obj("PBXContainerItemProxy", proxyType="1", remoteGlobalIDString=targets[1],
                remoteInfo="MiaouWidget")
    dependency = obj("PBXTargetDependency", target=targets[1], targetProxy=proxy)
    embed = obj("PBXCopyFilesBuildPhase", buildActionMask="2147483647", dstPath="", dstSubfolderSpec="13",
                name="Embed App Extensions", runOnlyForDeploymentPostprocessing="0",
                files=[obj("PBXBuildFile", fileRef=products[1],
                           settings={"ATTRIBUTES": ["RemoveHeadersOnCopy", "CodeSignOnCopy"]})])
    objects[targets[0]]["dependencies"].append(dependency)
    objects[targets[0]]["buildPhases"].append(embed)
    products_group = obj("PBXGroup", name="Products", children=products, sourceTree="<group>")
    main_group = obj("PBXGroup", children=list(references.values()) + [strings, products_group],
                     sourceTree="<group>")
    root = obj("PBXProject", attributes={"LastUpgradeCheck": "2600"},
               buildConfigurationList=configuration({}), compatibilityVersion="Xcode 14.0",
               developmentRegion="en", knownRegions=["en", "fr", "Base"], mainGroup=main_group,
               productRefGroup=products_group, projectDirPath="", projectRoot="", targets=targets)
    objects[proxy]["containerPortal"] = root
    directory = BUILD / "Miaou.xcodeproj"
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "project.pbxproj").write_bytes(plistlib.dumps(
        {"archiveVersion": "1", "classes": {}, "objectVersion": "56",
         "objects": objects, "rootObject": root}))
    return directory


def install_directory():
    return Path(os.environ.get("INSTALL_DIR", str(Path.home() / "Applications"))).expanduser()


def build_number():
    counter = BUILD / "build-number"
    previous = int(counter.read_text()) if counter.exists() else 1
    installed_info = install_directory() / "Miaou.app/Contents/Info.plist"
    if installed_info.exists():
        info = plistlib.loads(installed_info.read_bytes())
        installed = str(info.get("CFBundleVersion", ""))
        if info.get("CFBundleIdentifier") == BUNDLE_ID and installed.isdigit() and len(installed) <= 4:
            previous = max(previous, int(installed))
    number = os.environ.get("BUILD_NUMBER", str(previous + 1))
    if not re.fullmatch(r"[1-9][0-9]{0,3}", number):
        raise SystemExit("BUILD_NUMBER must be a positive integer with at most four digits.")
    counter.write_text(str(max(previous, int(number))))
    return number


def build():
    cli = Path(os.environ.get("CLI_BIN") or shutil.which("miaou") or Path.home() / ".cargo/bin/miaou")
    if not cli.is_file() or not os.access(cli, os.X_OK):
        raise SystemExit("miaou CLI not found; install it with cargo install --path cli.")
    identity, team, group = signing()
    BUILD.mkdir(parents=True, exist_ok=True)
    version = re.search(r'^version = "([^"]+)"', (APP.parent / "cli/Cargo.toml").read_text(), re.M)[1]
    output = BUILD / "products"
    run("xcodebuild", "-project", str(project(identity, team)), "-alltargets", "-parallelizeTargets",
        "-configuration", "Release", f"CONFIGURATION_BUILD_DIR={output}",
        f"MIAOU_APP_GROUP={group}", f"CURRENT_PROJECT_VERSION={build_number()}",
        f"MARKETING_VERSION={version}", "build")
    bundle = output / "Miaou.app"
    extension = bundle / "Contents/PlugIns/MiaouWidget.appex"
    helper = bundle / "Contents/MacOS/miaou-cli"
    shutil.copy2(cli, helper)
    run("codesign", "--force", "--sign", identity, str(helper))
    for target in [bundle, extension]:
        resources = target / "Contents/Resources"
        resources.mkdir(parents=True, exist_ok=True)
        shutil.copy2(APP / "Resources/AppIcon.icns", resources / "AppIcon.icns")
    for target, template in [(extension, APP / "Widget/MiaouWidget.entitlements"),
                             (bundle, APP / "Miaou.entitlements")]:
        if identity != "-":
            run("codesign", "--force", "--sign", identity,
                "--preserve-metadata=entitlements,flags,requirements,runtime", str(target))
        else:
            entitlements = BUILD / f"{target.stem}.entitlements"
            entitlements.write_text(template.read_text().replace("$(MIAOU_APP_GROUP)", group))
            run("codesign", "--force", "--sign", identity, "--entitlements", str(entitlements), str(target))
    run("codesign", "--verify", "--deep", "--strict", str(bundle))
    destination = APP / "Miaou.app"
    previous = BUILD / "Miaou.previous.app"
    if previous.exists():
        shutil.rmtree(previous)
    if destination.exists():
        destination.rename(previous)
    bundle.rename(destination)
    print(f"Built {destination} (App Group: {group})")
    if identity == "-":
        print("Widget activation requires an Apple signing identity; see app/README.md.")


def stop_old_widget():
    result = subprocess.run(["pgrep", "-x", "MiaouWidget"], capture_output=True, text=True)
    for pid in result.stdout.split():
        command = subprocess.run(["ps", "-p", pid, "-o", "comm="],
                                 capture_output=True, text=True).stdout.strip()
        executable = Path(command)
        extension = executable.parent.parent.parent
        info = extension / "Contents/Info.plist"
        if executable.name == "MiaouWidget" and info.exists() and (
                plistlib.loads(info.read_bytes()).get("CFBundleIdentifier") == WIDGET_ID):
            try:
                os.kill(int(pid), signal.SIGTERM)
            except ProcessLookupError:
                pass


def install():
    source = APP / "Miaou.app"
    destination = install_directory() / "Miaou.app"
    destination.parent.mkdir(parents=True, exist_ok=True)
    for bundle in [source, destination]:
        if bundle.exists():
            info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
            if info.get("CFBundleIdentifier") != BUNDLE_ID:
                raise SystemExit(f"{bundle} is not a Miaou bundle; it was not replaced.")
    temporary = destination.parent / ".Miaou.installing.app"
    previous = destination.parent / ".Miaou.previous.app"
    if temporary.exists():
        shutil.rmtree(temporary)
    shutil.copytree(source, temporary)
    try:
        run("codesign", "--verify", "--deep", "--strict", str(temporary))
        if previous.exists():
            shutil.rmtree(previous)
        stop_old_widget()
        if destination.exists():
            destination.rename(previous)
        try:
            temporary.rename(destination)
        except OSError:
            if previous.exists():
                previous.rename(destination)
            raise
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)
    # Only the installed extension should remain a WidgetKit candidate.
    copies = [source, previous, BUILD / "Miaou.previous.app"]
    registered = run("pluginkit", "-m", "-v", "-i", WIDGET_ID, capture_output=True, text=True).stdout
    for line in registered.splitlines():
        match = re.search(r"(/[^\t]+\.appex)\s*$", line)
        if match:
            copies.append(Path(match[1]).parent.parent.parent)
    for copy in dict.fromkeys(copies):
        if copy.exists() and copy != destination:
            subprocess.run([LSREGISTER, "-u", str(copy)], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL)
            subprocess.run(["pluginkit", "-r", str(copy / "Contents/PlugIns/MiaouWidget.appex")],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    run(LSREGISTER, "-f", "-R", str(destination))
    run("pluginkit", "-a", str(destination / "Contents/PlugIns/MiaouWidget.appex"))
    print(f"Installed {destination}. Reopen Miaou, then add its widget with macOS Edit Widgets.")


if __name__ == "__main__":
    if sys.argv[1:] == ["--install-only"]:
        install()
    elif not sys.argv[1:]:
        build()
    else:
        raise SystemExit("Usage: build-app.py [--install-only]")
