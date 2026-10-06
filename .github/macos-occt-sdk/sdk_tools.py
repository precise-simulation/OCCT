#!/usr/bin/env python3
import argparse
import functools
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys


REQUESTED_MODULES = [
    "FoundationClasses",
    "ModelingData",
    "ModelingAlgorithms",
    "ApplicationFramework",
    "DataExchange",
]
REPRESENTATIVE_TOOLKITS = ("TKernel", "TKBO", "TKDESTEP", "TKV3d", "TKService")
FRAMEWORK_VARS = {
    "AppKit": "OpenCASCADE_AppKit_FRAMEWORK",
    "IOKit": "OpenCASCADE_IOKit_FRAMEWORK",
}
APPLE_SDK_FRAMEWORK_RE = re.compile(
    r"/[^;\"\n]*MacOSX[^;\"\n]*\.sdk/System/Library/Frameworks/(AppKit|IOKit)\.framework"
)
OPTIONAL_DEP_RE = re.compile(
    r"(freetype|freeimage|libtbb|vtk|tcl|tk8|openvr|draco|avcodec|avformat|"
    r"swscale|avutil|X11|Xmu|libGL|OpenGL\.framework)",
    re.IGNORECASE,
)


def run(*args: str) -> str:
    return subprocess.check_output(args, text=True, errors="replace")


def run_combined(*args: str) -> str:
    return subprocess.run(
        args,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        errors="replace",
        check=True,
    ).stdout


def run_ok(*args: str) -> bool:
    return subprocess.run(
        args,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode == 0


@functools.lru_cache(maxsize=None)
def developer_tool(name: str) -> str:
    return run("xcrun", "--find", name).strip()


def tool_identity(path: str):
    binary = pathlib.Path(path)
    what_text = ""
    if shutil.which("what"):
        what = subprocess.run(
            ["what", str(binary)],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
            check=False,
        )
        what_text = what.stdout.strip()
    return {
        "path": str(binary),
        "sha256": sha256(binary),
        "file": run("file", "-b", str(binary)).strip(),
        "what": what_text,
    }


def require(condition: bool, message: str):
    if not condition:
        raise RuntimeError(message)


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: pathlib.Path):
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: pathlib.Path, value):
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def parse_requested_options(path: pathlib.Path):
    result = {}
    pattern = re.compile(r"^-D([^:=]+)(?::[^=]+)?=(.*)$")
    for line in path.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        require(match is not None, f"invalid recorded CMake option: {line}")
        result[match.group(1)] = match.group(2)
    return dict(sorted(result.items()))


def parse_cache(path: pathlib.Path):
    exact = {
        "3RDPARTY_DIR",
        "CMAKE_BUILD_TYPE",
        "CMAKE_C_COMPILER",
        "CMAKE_CXX_COMPILER",
        "CMAKE_EXPORT_NO_PACKAGE_REGISTRY",
        "CMAKE_GENERATOR",
        "CMAKE_OSX_ARCHITECTURES",
        "CMAKE_OSX_DEPLOYMENT_TARGET",
        "CMAKE_OSX_SYSROOT",
    }
    result = {}
    for line in path.read_text(errors="replace").splitlines():
        if not line or line.startswith(("#", "//")) or ":" not in line or "=" not in line:
            continue
        name_type, value = line.split("=", 1)
        name, cache_type = name_type.split(":", 1)
        if cache_type in {"INTERNAL", "STATIC"}:
            continue
        if name in exact or name.startswith(("BUILD_", "USE_", "INSTALL_DIR")):
            result[name] = value
    return dict(sorted(result.items()))


def exported_modules(prefix: pathlib.Path):
    config = (prefix / "lib/cmake/opencascade/OpenCASCADEConfig.cmake").read_text(errors="replace")
    match = re.search(r"set \(OpenCASCADE_MODULES ([^)]+)\)", config)
    return match.group(1).replace(";", " ").split() if match else []


def toolkit_names(prefix: pathlib.Path, linkage: str):
    result = set()
    for path in (prefix / "lib").glob("libTK*"):
        if linkage == "static" and path.name.endswith(".a"):
            result.add(path.name[3:-2])
        elif linkage == "shared" and ".dylib" in path.name:
            result.add(path.name[3:path.name.index(".")])
    return sorted(result)


def real_libraries(prefix: pathlib.Path, linkage: str):
    suffix = ".a" if linkage == "static" else ".dylib"
    result = []
    for path in sorted((prefix / "lib").glob("libTK*")):
        if not path.is_file() or path.is_symlink():
            continue
        if linkage == "static" and path.name.endswith(suffix):
            result.append(path)
        elif linkage == "shared" and path.name.endswith(suffix):
            result.append(path)
    return result


def lipo_archs(path: pathlib.Path):
    items = run(developer_tool("lipo"), "-archs", str(path)).strip().split()
    require(len(items) == len(set(items)), f"duplicate Mach-O architecture slices in {path}: {items}")
    return set(items)


def expected_arches(architecture: str):
    return {architecture}


def macho_build(path: pathlib.Path, arch: str):
    output = run(developer_tool("vtool"), "-arch", arch, "-show-build", str(path))
    platforms = re.findall(r"^\s*platform\s+(\S+)\s*$", output, flags=re.MULTILINE)
    minoses = re.findall(r"^\s*minos\s+(\S+)\s*$", output, flags=re.MULTILINE)
    require(platforms, f"vtool reported no platform for {path} [{arch}]\n{output}")
    require(minoses, f"vtool reported no minimum OS for {path} [{arch}]\n{output}")
    require(len(set(platforms)) == 1, f"ambiguous platform for {path} [{arch}]: {platforms}")
    require(len(set(minoses)) == 1, f"ambiguous minimum OS for {path} [{arch}]: {minoses}")
    return {"platform": platforms[0], "minos": minoses[0]}


def validate_macho(path: pathlib.Path, architecture: str, deployment_target: str):
    observed = lipo_archs(path)
    expected = expected_arches(architecture)
    require(observed == expected, f"wrong architecture set in {path}: {sorted(observed)}; expected {sorted(expected)}")
    result = {}
    for arch in sorted(expected):
        build = macho_build(path, arch)
        require(build["platform"] == "MACOS", f"{path} [{arch}] platform is {build['platform']}, expected MACOS")
        require(build["minos"] == deployment_target, f"{path} [{arch}] minOS is {build['minos']}, expected {deployment_target}")
        result[arch] = build
    return result


def dylib_id(path: pathlib.Path) -> str:
    ids = [
        line.strip()
        for line in run(developer_tool("otool"), "-D", str(path)).splitlines()[1:]
        if line.strip()
    ]
    require(len(ids) == 1, f"expected one install ID for {path}: {ids}")
    return ids[0]


def dylib_dependencies(path: pathlib.Path):
    result = []
    for line in run(developer_tool("otool"), "-L", str(path)).splitlines()[1:]:
        line = line.strip()
        if line:
            result.append(line.split(" (", 1)[0])
    return result


def macho_rpaths(path: pathlib.Path):
    output = run(developer_tool("otool"), "-l", str(path))
    result = []
    lines = output.splitlines()
    for index, line in enumerate(lines):
        if line.strip() != "cmd LC_RPATH":
            continue
        for candidate in lines[index + 1:index + 6]:
            match = re.match(r"\s*path\s+(.+?)\s+\(offset\s+\d+\)", candidate)
            if match:
                result.append(match.group(1))
                break
    return result


def validate_shared(prefix: pathlib.Path, architecture: str, deployment_target: str, forbidden=()):
    libraries = real_libraries(prefix, "shared")
    require(libraries, "no real OCCT dylibs found")
    libdir = (prefix / "lib").resolve()
    for link in sorted((prefix / "lib").glob("libTK*.dylib")):
        if link.is_symlink():
            target = link.resolve(strict=True)
            require(target == libdir or libdir in target.parents, f"dylib symlink escapes package: {link} -> {target}")

    evidence = {}
    for path in libraries:
        require("Mach-O" in run("file", "-b", str(path)), f"not a Mach-O dylib: {path}")
        require(
            re.match(r"^libTK.+\.\d+\.\d+\.\d+\.dylib$", path.name) is not None,
            f"real dylib does not use the expected VERSION filename: {path.name}",
        )
        build = validate_macho(path, architecture, deployment_target)
        install_id = dylib_id(path)
        require(install_id.startswith("@rpath/"), f"non-@rpath install ID in {path}: {install_id}")
        require(
            re.match(r"^@rpath/libTK.+\.\d+\.\d+\.dylib$", install_id) is not None,
            f"install ID is not the expected SOVERSION alias in {path}: {install_id}",
        )
        alias = prefix / "lib" / install_id[len("@rpath/"):]
        require(alias.exists(), f"install ID alias is absent from package: {alias}")
        require(alias.is_symlink(), f"SOVERSION install-ID alias is not a symlink: {alias}")
        require(alias.resolve() == path.resolve(), f"install ID alias does not resolve to {path.name}: {alias}")
        toolkit = path.name.split(".", 1)[0]
        unversioned = prefix / "lib" / f"{toolkit}.dylib"
        require(unversioned.is_symlink(), f"missing unversioned dylib symlink: {unversioned}")
        require(unversioned.resolve() == path.resolve(), f"unversioned dylib does not resolve to real library: {unversioned}")
        require(
            os.readlink(unversioned) == alias.name,
            f"unversioned dylib does not point to SOVERSION alias: {unversioned} -> {os.readlink(unversioned)}",
        )
        require(
            os.readlink(alias) == path.name,
            f"SOVERSION alias does not point to real VERSION dylib: {alias} -> {os.readlink(alias)}",
        )
        deps = dylib_dependencies(path)
        rpaths = macho_rpaths(path)
        load_text = "\n".join([install_id, *deps, *rpaths])
        for needle in ["/opt/homebrew", "/usr/local", "/Users/runner/", *forbidden]:
            if needle:
                require(needle not in load_text, f"producer/non-system path {needle} appears in Mach-O load commands for {path}")
        for dep in deps:
            require(not OPTIONAL_DEP_RE.search(dep), f"disabled optional runtime dependency in {path}: {dep}")
            require("/opt/homebrew/" not in dep and not dep.startswith("/usr/local/"), f"non-system package dependency in {path}: {dep}")
            if dep.startswith("@rpath/libTK"):
                dep_alias = prefix / "lib" / dep[len("@rpath/"):]
                require(
                    re.match(r"^@rpath/libTK.+\.\d+\.\d+\.dylib$", dep) is not None,
                    f"OCCT dependency does not use its SOVERSION alias in {path}: {dep}",
                )
                require(dep_alias.is_symlink(), f"OCCT dependency alias is missing from package: {dep}")
            elif dep.startswith("@"):
                raise RuntimeError(f"unexpected loader-relative dependency in {path}: {dep}")
            elif not dep.startswith(("/usr/lib/", "/System/Library/")):
                raise RuntimeError(f"unexpected absolute dependency in {path}: {dep}")
        if run_ok(developer_tool("codesign"), "-d", str(path)):
            require(
                run_ok(developer_tool("codesign"), "--verify", "--strict", str(path)),
                f"thin dylib signature verification failed: {path}",
            )
        evidence[path.name] = {
            "architectures": sorted(lipo_archs(path)),
            "build": build,
            "install_id": install_id,
            "dependencies": deps,
            "rpaths": rpaths,
        }
    return evidence


def validate_static(prefix: pathlib.Path, architecture: str):
    require(not any((prefix / "lib").glob("libTK*.dylib")), "static SDK contains shared OCCT dylibs")
    libraries = real_libraries(prefix, "static")
    require(libraries, "no static OCCT libraries found")
    expected = expected_arches(architecture)
    evidence = {}
    for path in libraries:
        observed = lipo_archs(path)
        require(observed == expected, f"wrong archive architecture set in {path}: {sorted(observed)}; expected {sorted(expected)}")
        evidence[path.name] = sorted(observed)

    cmake_dir = prefix / "lib/cmake/opencascade"
    config_text = (cmake_dir / "OpenCASCADEConfig.cmake").read_text(errors="replace")
    targets_text = "\n".join(
        path.read_text(errors="replace")
        for path in sorted(cmake_dir.glob("OpenCASCADE*Targets*.cmake"))
    )
    for framework, variable in FRAMEWORK_VARS.items():
        require(
            f"find_library({variable} NAMES {framework})" in config_text,
            f"static package config does not resolve {framework} on the consumer",
        )
    require(
        not re.search(r"/[^;\"\n]*MacOSX[^;\"\n]*\.sdk/System/Library/Frameworks/[^;\"\n]*\.framework", targets_text),
        "static target exports contain an absolute producer SDK framework path",
    )
    return evidence


def looks_textual(path: pathlib.Path):
    with path.open("rb") as stream:
        sample = stream.read(65536)
    if b"\0" in sample:
        return False
    try:
        sample.decode("utf-8")
        return True
    except UnicodeDecodeError:
        return False


def scan_leaks(prefix: pathlib.Path, forbidden):
    needles = {"/opt/homebrew", "/usr/local", "/Users/runner/"}
    needles.update(value for value in forbidden if value and value not in {"/", str(prefix)})
    encoded = [(value, value.encode()) for value in sorted(needles, key=len, reverse=True)]
    for path in prefix.rglob("*"):
        if not path.is_file() or path.is_symlink() or path.name == "build-manifest.json":
            continue
        if not looks_textual(path):
            continue
        overlap = b""
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                data = overlap + chunk
                for text, needle in encoded:
                    require(needle not in data, f"producer path {text} leaked into {path}")
                overlap = data[-4096:]


def validate_prefix(args):
    prefix = pathlib.Path(args.prefix).resolve()
    require((prefix / "include/opencascade/Standard_Version.hxx").is_file(), "missing Standard_Version.hxx")
    require((prefix / "lib/cmake/opencascade/OpenCASCADEConfig.cmake").is_file(), "missing OpenCASCADEConfig.cmake")
    require((prefix / "bin/env.sh").is_file(), "missing bin/env.sh")
    require((prefix / "share/opencascade/resources").is_dir(), "missing installed OCCT resources")
    for toolkit in REPRESENTATIVE_TOOLKITS:
        expected = prefix / "lib" / f"lib{toolkit}.a"
        if args.linkage == "static":
            require(expected.is_file(), f"missing static {toolkit}")
        else:
            require(any((prefix / "lib").glob(f"lib{toolkit}*.dylib")), f"missing shared {toolkit}")
    env_text = (prefix / "bin/env.sh").read_text(errors="replace")
    require('export THIRDPARTY_DIR=""' in env_text, "env.sh has non-empty THIRDPARTY_DIR fallback")

    forbidden = list(args.forbidden_path or [])
    manifest = None
    manifest_path = prefix / "build-manifest.json"
    if manifest_path.is_file():
        manifest = read_json(manifest_path)
        require(manifest["artifact"]["architecture"] == args.architecture, "manifest architecture mismatch")
        require(manifest["artifact"]["deployment_target"] == args.deployment_target, "manifest deployment target mismatch")
        require(manifest["linkage"] == args.linkage, "manifest linkage mismatch")
        producer = manifest.get("producer", {})
        forbidden.extend(producer.get("forbidden_paths", []))
        forbidden.extend(filter(None, [producer.get("developer_dir"), producer.get("sdk_path")]))
    scan_leaks(prefix, forbidden)

    if args.linkage == "shared":
        observed = validate_shared(prefix, args.architecture, args.deployment_target, forbidden)
    else:
        observed = validate_static(prefix, args.architecture)
    if manifest:
        if "mach_o" in manifest:
            require(observed == manifest["mach_o"], "packaged library evidence differs from recorded thin manifest")
        for rel, expected_hash in manifest.get("representative_sha256", {}).items():
            path = prefix / rel
            require(path.is_file(), f"manifest representative file is missing: {rel}")
            require(sha256(path) == expected_hash, f"manifest representative hash differs: {rel}")


def normalize_static_frameworks(args):
    prefix = pathlib.Path(args.prefix).resolve()
    sdk_path = pathlib.Path(args.sdk_path).resolve()
    cmake_dir = prefix / "lib/cmake/opencascade"
    config = cmake_dir / "OpenCASCADEConfig.cmake"
    targets = sorted(cmake_dir.glob("OpenCASCADE*Targets*.cmake"))
    require(config.is_file(), "missing OpenCASCADEConfig.cmake")
    require(targets, "no installed target exports found")

    replacements = {}
    counts = {framework: 0 for framework in FRAMEWORK_VARS}

    for target in targets:
        original = target.read_text(encoding="utf-8")

        def replace_framework(match):
            producer_path = match.group(0)
            framework = match.group(1)
            replacement = f"${{{FRAMEWORK_VARS[framework]}}}"
            replacements[producer_path] = replacement
            counts[framework] += 1
            return replacement

        changed = APPLE_SDK_FRAMEWORK_RE.sub(replace_framework, original)
        if changed != original:
            target.write_text(changed, encoding="utf-8", newline="\n")

    config_text = config.read_text(encoding="utf-8")
    marker = "# Import OpenCASCADE targets."
    require(marker in config_text, "could not locate target import marker in OpenCASCADEConfig.cmake")
    require("OpenCASCADE_AppKit_FRAMEWORK" not in config_text, "framework normalization block already present")
    block = """# Resolve Apple frameworks on the consumer host for relocatable static targets.
if(APPLE)
  find_library(OpenCASCADE_AppKit_FRAMEWORK NAMES AppKit)
  find_library(OpenCASCADE_IOKit_FRAMEWORK NAMES IOKit)
  if(NOT OpenCASCADE_AppKit_FRAMEWORK OR NOT OpenCASCADE_IOKit_FRAMEWORK)
    message(FATAL_ERROR "Required Apple AppKit/IOKit frameworks were not found")
  endif()
endif()

"""
    config.write_text(config_text.replace(marker, block + marker, 1), encoding="utf-8", newline="\n")
    combined = "\n".join(path.read_text(errors="replace") for path in targets)
    for producer_path in replacements:
        require(producer_path not in combined, f"producer framework path remains: {producer_path}")
    require(
        not re.search(r"/[^;\"\n]*MacOSX[^;\"\n]*\.sdk/System/Library/Frameworks/[^;\"\n]*\.framework", combined),
        "unexpected absolute Apple SDK framework path remains",
    )
    write_json(
        pathlib.Path(args.record),
        {
            "producer_sdk_path": str(sdk_path),
            "replacements": [
                {"producer_path": path, "replacement": replacement}
                for path, replacement in sorted(replacements.items())
            ],
            "replacement_counts": dict(sorted(counts.items())),
        },
    )


def normalize_env(args):
    path = pathlib.Path(args.path)
    text = path.read_text(encoding="utf-8")
    text, count = re.subn(
        r'export THIRDPARTY_DIR="[^"]*"',
        'export THIRDPARTY_DIR=""',
        text,
        count=1,
    )
    require(count == 1, f"failed to normalize THIRDPARTY_DIR in {path}")
    path.write_text(text, encoding="utf-8", newline="\n")


def representative_hashes(prefix: pathlib.Path, linkage: str):
    candidates = [
        prefix / "include/opencascade/Standard_Version.hxx",
        prefix / "lib/cmake/opencascade/OpenCASCADEConfig.cmake",
        prefix / "lib/cmake/opencascade/OpenCASCADEConfigVersion.cmake",
    ]
    target_files = sorted((prefix / "lib/cmake/opencascade").glob("OpenCASCADE*Targets.cmake"))
    if target_files:
        candidates.append(target_files[0])
    for toolkit in REPRESENTATIVE_TOOLKITS:
        if linkage == "static":
            candidates.append(prefix / "lib" / f"lib{toolkit}.a")
        else:
            matches = [
                path for path in (prefix / "lib").glob(f"lib{toolkit}*.dylib")
                if path.is_file() and not path.is_symlink()
            ]
            if matches:
                candidates.append(sorted(matches)[-1])
    return {
        path.relative_to(prefix).as_posix(): sha256(path)
        for path in candidates
        if path.is_file()
    }


def consumer_evidence(path: pathlib.Path, deployment_target: str):
    architectures = lipo_archs(path)
    build = {}
    for arch in sorted(architectures):
        info = macho_build(path, arch)
        require(info["platform"] == "MACOS", f"consumer platform is {info['platform']} [{arch}]")
        require(info["minos"] == deployment_target, f"consumer minOS is {info['minos']}, expected {deployment_target} [{arch}]")
        build[arch] = info
    return {
        "architectures": sorted(architectures),
        "build": build,
        "dependencies": dylib_dependencies(path),
    }


def make_thin_manifest(args):
    prefix = pathlib.Path(args.prefix).resolve()
    consumer = pathlib.Path(args.consumer).resolve()
    framework_record = read_json(pathlib.Path(args.framework_normalization)) if args.framework_normalization else None
    mach_o = (
        validate_shared(prefix, args.architecture, args.deployment_target)
        if args.linkage == "shared"
        else validate_static(prefix, args.architecture)
    )
    manifest = {
        "schema_version": 1,
        "occt": {
            "version": args.version,
            "commit": args.source_sha,
            "event_sha": args.event_sha,
        },
        "artifact": {
            "architecture": args.architecture,
            "deployment_target": args.deployment_target,
            "sdk_name": prefix.name,
        },
        "linkage": args.linkage,
        "producer": {
            "runner_label": args.runner_label,
            "image_os": os.environ.get("ImageOS", ""),
            "image_version": os.environ.get("ImageVersion", ""),
            "sw_vers": run("sw_vers").strip(),
            "host_architecture": run("uname", "-m").strip(),
            "developer_dir": args.developer_dir,
            "xcode": run("xcodebuild", "-version").strip(),
            "clang_path": args.clang,
            "clang_version": run(args.clang, "--version").splitlines()[0],
            "clangxx_path": args.clangxx,
            "clangxx_version": run(args.clangxx, "--version").splitlines()[0],
            "sdk_path": args.sdk_path,
            "sdk_version": run("xcrun", "--sdk", "macosx", "--show-sdk-version").strip(),
            "cmake": run("cmake", "--version").splitlines()[0],
            "cmake_archive_sha256": os.environ.get("CMAKE_ARCHIVE_SHA256", ""),
            "generator": args.generator,
            "make": run("make", "--version").splitlines()[0],
            "gtar": run("gtar", "--version").splitlines()[0],
            "gzip": run_combined("gzip", "--version").splitlines()[0],
            "source_date_epoch": int(args.source_date_epoch),
            "forbidden_paths": sorted(set(args.forbidden_path or [])),
        },
        "cmake_options": {
            "requested": parse_requested_options(pathlib.Path(args.configure_options)),
            "resolved_cache": parse_cache(pathlib.Path(args.cmake_cache)),
        },
        "requested_modules": REQUESTED_MODULES,
        "exported_modules": exported_modules(prefix),
        "toolkits": toolkit_names(prefix, args.linkage),
        "mach_o": mach_o,
        "consumer": {
            **consumer_evidence(consumer, args.deployment_target),
            "link_command": pathlib.Path(args.consumer_link).read_text(errors="replace").strip(),
        },
        "framework_normalization": framework_record,
        "representative_sha256": representative_hashes(prefix, args.linkage),
    }
    write_json(pathlib.Path(args.output), manifest)


def verify_consumer(args):
    consumer = pathlib.Path(args.consumer).resolve()
    prefix = pathlib.Path(args.prefix).resolve()
    evidence = consumer_evidence(consumer, args.deployment_target)
    require(set(evidence["architectures"]) == {args.architecture}, f"consumer architecture mismatch: {evidence['architectures']}")
    dependencies = evidence["dependencies"]
    if args.linkage == "static":
        for dep in dependencies:
            require("libTK" not in dep, f"static consumer unexpectedly depends on OCCT dylib: {dep}")
            require(not OPTIONAL_DEP_RE.search(dep), f"static consumer has disabled optional runtime dependency: {dep}")
            require(
                dep.startswith(("/usr/lib/", "/System/Library/")),
                f"static consumer has unexpected non-system dependency: {dep}",
            )
        link_text = pathlib.Path(args.link_command).read_text(errors="replace")
        cache_text = pathlib.Path(args.cmake_cache).read_text(errors="replace")
        sdk_path = run("xcrun", "--sdk", "macosx", "--show-sdk-path").strip()
        for framework, variable in FRAMEWORK_VARS.items():
            match = re.search(
                rf"^{re.escape(variable)}:FILEPATH=(.+)$",
                cache_text,
                flags=re.MULTILINE,
            )
            require(
                match is not None and not match.group(1).endswith("-NOTFOUND"),
                f"consumer did not resolve {framework} with find_library()",
            )
            resolved = pathlib.Path(match.group(1))
            require(
                resolved.name == f"{framework}.framework",
                f"consumer resolved unexpected {framework} location: {resolved}",
            )
            resolved_text = str(resolved)
            require(
                resolved_text.startswith("/System/Library/Frameworks/")
                or resolved_text.startswith(str(pathlib.Path(sdk_path) / "System/Library/Frameworks")),
                f"consumer resolved {framework} outside the Apple system/selected SDK: {resolved}",
            )
            require(
                framework in link_text,
                f"consumer link command does not contain the resolved {framework} dependency",
            )
        require(
            not macho_rpaths(consumer),
            f"static consumer unexpectedly carries LC_RPATH entries: {macho_rpaths(consumer)}",
        )
    else:
        for dep in dependencies:
            if dep.startswith("@rpath/libTK"):
                require((prefix / "lib" / dep[len("@rpath/"):]).exists(), f"shared consumer dependency missing in SDK: {dep}")
            elif dep.startswith(("/usr/lib/", "/System/Library/")):
                continue
            else:
                raise RuntimeError(f"shared consumer has unexpected dependency: {dep}")
        expected_rpath = str(prefix / "lib")
        observed_rpaths = macho_rpaths(consumer)
        require(
            observed_rpaths and set(observed_rpaths) == {expected_rpath},
            f"shared consumer LC_RPATH entries do not point only to tested SDK: {observed_rpaths}",
        )


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    normalize = sub.add_parser("normalize-static-frameworks")
    normalize.add_argument("--prefix", required=True)
    normalize.add_argument("--sdk-path", required=True)
    normalize.add_argument("--record", required=True)
    normalize.set_defaults(func=normalize_static_frameworks)

    env_normalize = sub.add_parser("normalize-env")
    env_normalize.add_argument("--path", required=True)
    env_normalize.set_defaults(func=normalize_env)

    validate = sub.add_parser("validate-prefix")
    validate.add_argument("--prefix", required=True)
    validate.add_argument("--linkage", choices=("shared", "static"), required=True)
    validate.add_argument("--architecture", choices=("x86_64", "arm64"), required=True)
    validate.add_argument("--deployment-target", default="13.0")
    validate.add_argument("--forbidden-path", action="append")
    validate.set_defaults(func=validate_prefix)

    manifest = sub.add_parser("thin-manifest")
    manifest.add_argument("--prefix", required=True)
    manifest.add_argument("--consumer", required=True)
    manifest.add_argument("--consumer-link", required=True)
    manifest.add_argument("--cmake-cache", required=True)
    manifest.add_argument("--configure-options", required=True)
    manifest.add_argument("--framework-normalization")
    manifest.add_argument("--linkage", choices=("shared", "static"), required=True)
    manifest.add_argument("--architecture", choices=("x86_64", "arm64"), required=True)
    manifest.add_argument("--deployment-target", default="13.0")
    manifest.add_argument("--source-sha", required=True)
    manifest.add_argument("--event-sha", required=True)
    manifest.add_argument("--source-date-epoch", required=True)
    manifest.add_argument("--version", required=True)
    manifest.add_argument("--runner-label", required=True)
    manifest.add_argument("--developer-dir", required=True)
    manifest.add_argument("--sdk-path", required=True)
    manifest.add_argument("--clang", required=True)
    manifest.add_argument("--clangxx", required=True)
    manifest.add_argument("--generator", required=True)
    manifest.add_argument("--forbidden-path", action="append")
    manifest.add_argument("--output", required=True)
    manifest.set_defaults(func=make_thin_manifest)

    consumer = sub.add_parser("verify-consumer")
    consumer.add_argument("--prefix", required=True)
    consumer.add_argument("--consumer", required=True)
    consumer.add_argument("--link-command", required=True)
    consumer.add_argument("--cmake-cache", required=True)
    consumer.add_argument("--linkage", choices=("shared", "static"), required=True)
    consumer.add_argument("--architecture", choices=("x86_64", "arm64"), required=True)
    consumer.add_argument("--deployment-target", default="13.0")
    consumer.set_defaults(func=verify_consumer)

    args = parser.parse_args()
    try:
        args.func(args)
    except (RuntimeError, subprocess.CalledProcessError, OSError, KeyError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
