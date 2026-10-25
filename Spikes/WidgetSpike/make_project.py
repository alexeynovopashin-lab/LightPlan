#!/usr/bin/env python3
"""Writes WidgetSpike.xcodeproj (iteration 30b probe): app + WidgetKit extension.

No XcodeGen on this Mac, so the pbxproj is written here. Object ids are hashes of
names, so a rerun gives the same file (`python3 make_project.py --check` proves it).
Folders App/, Widget/, Shared/ are synchronized groups: a new .swift file there needs
no rerun. Shared/ belongs to both targets. Both targets link LightPlanCore, the widget
also LightPlanDomain (does an extension take our Foundation-only packages?).

Bundle id: LP_SPIKE_ID (default Novopashin.LightPlan.spike30b), widget = <id>.Widget,
App Group = group.<id>. Simulator builds register nothing; a device build registers
App IDs only with -allowProvisioningUpdates (probe.sh never passes it).
"""
import hashlib
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / "WidgetSpike.xcodeproj" / "project.pbxproj"


def oid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


objs = []


def add(name, isa, body):
    objs.append((isa, oid(name), name, body))
    return oid(name)


def settings(d):
    lines = []
    for k, v in d.items():
        if isinstance(v, list):
            inner = "".join(f'\t\t\t\t\t"{x}",\n' for x in v)
            lines.append(f"\t\t\t\t{k} = (\n{inner}\t\t\t\t);")
        else:
            lines.append(f'\t\t\t\t{k} = "{v}";')
    return "\n".join(lines)


def conf_list(owner, confs):
    ids = []
    for cname, sets in confs:
        ids.append(add(f"{owner}.conf.{cname}", "XCBuildConfiguration",
                       f"\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{settings(sets)}\n\t\t\t}};\n\t\t\tname = {cname};"))
    refs = "".join(f"\t\t\t\t{i},\n" for i in ids)
    return add(f"{owner}.conflist", "XCConfigurationList",
               f"\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n{refs}\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Debug;")


def lst(ids):
    return "(\n" + "".join(f"\t\t\t\t{i},\n" for i in ids) + "\t\t\t)"


# Folders
g_app = add("group.App", "PBXFileSystemSynchronizedRootGroup",
            "\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n\t\t\tpath = App;\n\t\t\tsourceTree = \"<group>\";")
g_widget = add("group.Widget", "PBXFileSystemSynchronizedRootGroup",
               "\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n\t\t\tpath = Widget;\n\t\t\tsourceTree = \"<group>\";")
g_shared = add("group.Shared", "PBXFileSystemSynchronizedRootGroup",
               "\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n\t\t\tpath = Shared;\n\t\t\tsourceTree = \"<group>\";")

# Products
p_app = add("product.app", "PBXFileReference",
            "\t\t\tisa = PBXFileReference;\n\t\t\texplicitFileType = wrapper.application;\n\t\t\tincludeInIndex = 0;\n\t\t\tpath = Spike30b.app;\n\t\t\tsourceTree = BUILT_PRODUCTS_DIR;")
p_ext = add("product.ext", "PBXFileReference",
            "\t\t\tisa = PBXFileReference;\n\t\t\texplicitFileType = \"wrapper.app-extension\";\n\t\t\tincludeInIndex = 0;\n\t\t\tpath = Spike30bWidget.appex;\n\t\t\tsourceTree = BUILT_PRODUCTS_DIR;")
g_products = add("group.Products", "PBXGroup",
                 f"\t\t\tisa = PBXGroup;\n\t\t\tchildren = {lst([p_app, p_ext])};\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";")
g_main = add("group.main", "PBXGroup",
             f"\t\t\tisa = PBXGroup;\n\t\t\tchildren = {lst([g_app, g_widget, g_shared, g_products])};\n\t\t\tsourceTree = \"<group>\";")

# Local packages
pkg = {}
for name in ("LightPlanCore", "LightPlanDomain"):
    pkg[name] = add(f"pkg.{name}", "XCLocalSwiftPackageReference",
                    f"\t\t\tisa = XCLocalSwiftPackageReference;\n\t\t\trelativePath = ../../Packages/{name};")


def product_dep(target, name):
    dep = add(f"{target}.dep.{name}", "XCSwiftPackageProductDependency",
              f"\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tpackage = {pkg[name]};\n\t\t\tproductName = {name};")
    bf = add(f"{target}.bf.{name}", "PBXBuildFile",
             f"\t\t\tisa = PBXBuildFile;\n\t\t\tproductRef = {dep};")
    return dep, bf


def phase(target, isa, files=()):
    return add(f"{target}.phase.{isa}", isa,
               f"\t\t\tisa = {isa};\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = {lst(files)};\n\t\t\trunOnlyForDeploymentPostprocessing = 0;")


BASE = {
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_VERSION": "6.0",
    "TARGETED_DEVICE_FAMILY": "1",
    "IPHONEOS_DEPLOYMENT_TARGET": "26.0",
    "LP_SPIKE_ID": "Novopashin.LightPlan.spike30b",
    "GENERATE_INFOPLIST_FILE": "YES",
    "MARKETING_VERSION": "0.1",
    "CURRENT_PROJECT_VERSION": "1",
}

# Widget extension target
ext_deps = [product_dep("ext", n) for n in ("LightPlanCore", "LightPlanDomain")]
ext_phases = [phase("ext", "PBXSourcesBuildPhase"),
              phase("ext", "PBXFrameworksBuildPhase", [bf for _, bf in ext_deps]),
              phase("ext", "PBXResourcesBuildPhase")]
ext_conf = conf_list("ext", [("Debug", {**BASE,
    "PRODUCT_NAME": "Spike30bWidget",
    "PRODUCT_BUNDLE_IDENTIFIER": "$(LP_SPIKE_ID).Widget",
    "INFOPLIST_FILE": "Support/Widget-Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "Spike30b",
    "CODE_SIGN_ENTITLEMENTS": "Support/Spike.entitlements",
    "SKIP_INSTALL": "YES",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"],
})])
ext_deps_ids = [d for d, _ in ext_deps]
t_ext = add("target.ext", "PBXNativeTarget",
            f"\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = {ext_conf};\n\t\t\tbuildPhases = {lst(ext_phases)};\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t);\n"
            f"\t\t\tfileSystemSynchronizedGroups = {lst([g_widget, g_shared])};\n\t\t\tname = Spike30bWidget;\n\t\t\tpackageProductDependencies = {lst(ext_deps_ids)};\n"
            f"\t\t\tproductName = Spike30bWidget;\n\t\t\tproductReference = {p_ext};\n\t\t\tproductType = \"com.apple.product-type.app-extension\";")

# App target
proxy = add("proxy.ext", "PBXContainerItemProxy",
            f"\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = {oid('project')};\n\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = {t_ext};\n\t\t\tremoteInfo = Spike30bWidget;")
tdep = add("tdep.ext", "PBXTargetDependency",
           f"\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = {t_ext};\n\t\t\ttargetProxy = {proxy};")
embed_bf = add("app.bf.embed", "PBXBuildFile",
               f"\t\t\tisa = PBXBuildFile;\n\t\t\tfileRef = {p_ext};\n\t\t\tsettings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }};")
embed = add("app.phase.embed", "PBXCopyFilesBuildPhase",
            f"\t\t\tisa = PBXCopyFilesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tdstPath = \"\";\n\t\t\tdstSubfolderSpec = 13;\n\t\t\tfiles = {lst([embed_bf])};\n\t\t\tname = \"Embed Foundation Extensions\";\n\t\t\trunOnlyForDeploymentPostprocessing = 0;")
app_deps = [product_dep("app", "LightPlanCore")]
app_phases = [phase("app", "PBXSourcesBuildPhase"),
              phase("app", "PBXFrameworksBuildPhase", [bf for _, bf in app_deps]),
              phase("app", "PBXResourcesBuildPhase"), embed]
app_conf = conf_list("app", [("Debug", {**BASE,
    "PRODUCT_NAME": "Spike30b",
    "PRODUCT_BUNDLE_IDENTIFIER": "$(LP_SPIKE_ID)",
    "INFOPLIST_KEY_CFBundleDisplayName": "LP 30b-3a",
    "INFOPLIST_KEY_NSSupportsLiveActivities": "YES",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "CODE_SIGN_ENTITLEMENTS": "Support/Spike.entitlements",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
})])
t_app = add("target.app", "PBXNativeTarget",
            f"\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = {app_conf};\n\t\t\tbuildPhases = {lst(app_phases)};\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = {lst([tdep])};\n"
            f"\t\t\tfileSystemSynchronizedGroups = {lst([g_app, g_shared])};\n\t\t\tname = Spike30b;\n\t\t\tpackageProductDependencies = {lst([d for d, _ in app_deps])};\n"
            f"\t\t\tproductName = Spike30b;\n\t\t\tproductReference = {p_app};\n\t\t\tproductType = \"com.apple.product-type.application\";")

proj_conf = conf_list("project", [("Debug", {
    "SDKROOT": "iphoneos",
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "DEVELOPMENT_TEAM": "4A3PUKS9R9",
    "CODE_SIGN_STYLE": "Automatic",
    "ONLY_ACTIVE_ARCH": "YES",
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "ALWAYS_SEARCH_USER_PATHS": "NO",
})])
add("project", "PBXProject",
    f"\t\t\tisa = PBXProject;\n\t\t\tattributes = {{\n\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastSwiftUpdateCheck = 2700;\n\t\t\t\tLastUpgradeCheck = 2700;\n\t\t\t}};\n"
    f"\t\t\tbuildConfigurationList = {proj_conf};\n\t\t\tdevelopmentRegion = en;\n\t\t\thasScannedForEncodings = 0;\n\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n"
    f"\t\t\tmainGroup = {g_main};\n\t\t\tminimizedProjectReferenceProxies = 1;\n\t\t\tpackageReferences = {lst(list(pkg.values()))};\n\t\t\tpreferredProjectObjectVersion = 77;\n"
    f"\t\t\tproductRefGroup = {g_products};\n\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n\t\t\ttargets = {lst([t_app, t_ext])};")


def render():
    out = ["// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 77;\n\tobjects = {\n"]
    for isa in sorted({o[0] for o in objs}):
        out.append(f"\n/* Begin {isa} section */\n")
        for _, i, name, body in sorted((o for o in objs if o[0] == isa), key=lambda o: o[1]):
            out.append(f"\t\t{i} /* {name} */ = {{\n{body}\n\t\t}};\n")
        out.append(f"/* End {isa} section */\n")
    out.append(f"\t}};\n\trootObject = {oid('project')};\n}}\n")
    return "".join(out)


text = render()
if "--check" in sys.argv:
    same = OUT.exists() and OUT.read_text() == text
    print("same" if same else "differs")
    sys.exit(0 if same else 1)
OUT.parent.mkdir(exist_ok=True)
OUT.write_text(text)
print(f"wrote {OUT.relative_to(HERE)} ({len(objs)} objects)")
