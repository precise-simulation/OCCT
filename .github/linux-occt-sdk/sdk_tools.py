#!/usr/bin/env python3
import argparse
import gzip
import hashlib
import json
import pathlib
import re
import subprocess
import sys
import tarfile

SYMBOL_PREFIXES = ("GLIBC_", "GLIBCXX_", "CXXABI_")
LEAK_PATHS = (
    b"/work/src",
    b"/work/build",
    b"/work/stage",
    b"/github/workspace",
    b"/home/runner/work",
)
OPTIONAL_DEP_RE = re.compile(
    r"(libGL|libEGL|libGLES|libX11|libXmu|libfreetype|libfontconfig|libfreeimage|"
    r"libtbb|libvtk|libtcl|libtk8|libopenvr|libdraco|libavcodec|libavformat|"
    r"libswscale|libavutil)", re.IGNORECASE
)


def run(*args: str) -> str:
    return subprocess.check_output(args, text=True, errors="replace")


def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def version_key(value: str):
    return tuple(int(piece) for piece in re.findall(r"\d+", value))


def symbol_maxima(paths):
    found = {prefix[:-1]: [] for prefix in SYMBOL_PREFIXES}
    for path in paths:
        text = run("readelf", "--version-info", str(path))
        for prefix in SYMBOL_PREFIXES:
            name = prefix[:-1]
            found[name].extend(re.findall(rf"\b{re.escape(prefix)}([0-9][0-9.]*)\b", text))
    result = {}
    for name, versions in found.items():
        result[name] = max(versions, key=version_key) if versions else None
    return result


def real_shared_objects(prefix: pathlib.Path):
    result = []
    for path in sorted((prefix / "lib").glob("libTK*.so*")):
        if path.is_symlink():
            continue
        if path.is_file() and "ELF" in run("file", "-b", str(path)):
            result.append(path)
    return result


def toolkit_names(prefix: pathlib.Path, linkage: str):
    suffix = ".a" if linkage == "static" else ".so"
    names = set()
    for path in (prefix / "lib").glob("libTK*"):
        name = path.name
        if linkage == "static" and name.endswith(suffix):
            names.add(name[3:-2])
        elif linkage == "shared" and ".so" in name:
            names.add(name[3:name.index(".so")])
    return sorted(names)


def exported_modules(prefix: pathlib.Path):
    config = (prefix / "lib/cmake/opencascade/OpenCASCADEConfig.cmake").read_text(errors="replace")
    match = re.search(r"set \(OpenCASCADE_MODULES ([^)]+)\)", config)
    return match.group(1).replace(";", " ").split() if match else []


def normalize_build_path(value: str, prefix: pathlib.Path) -> str:
    replacements = (
        (str(prefix), "<sdk-prefix>"),
        ("/work/stage", "<stage-dir>"),
        ("/work/build", "<build-dir>"),
        ("/work/src", "<source-dir>"),
    )
    for old, new in replacements:
        value = value.replace(old, new)
    return value


def requested_cmake_options(path: pathlib.Path, prefix: pathlib.Path):
    result = {}
    pattern = re.compile(r"^-D([^:=]+)(?::[^=]+)?=(.*)$")
    for line in path.read_text().splitlines():
        match = pattern.match(line)
        require(match is not None, f"invalid recorded CMake option: {line}")
        result[match.group(1)] = normalize_build_path(match.group(2), prefix)
    return dict(sorted(result.items()))


def resolved_cmake_options(path: pathlib.Path, prefix: pathlib.Path):
    result = {}
    exact = {
        "3RDPARTY_DIR",
        "CMAKE_BUILD_TYPE",
        "CMAKE_C_COMPILER_LAUNCHER",
        "CMAKE_CXX_COMPILER_LAUNCHER",
    }
    for line in path.read_text(errors="replace").splitlines():
        if not line or line.startswith(("#", "//")) or ":" not in line or "=" not in line:
            continue
        name_type, value = line.split("=", 1)
        name, cache_type = name_type.split(":", 1)
        if cache_type in {"INTERNAL", "STATIC"}:
            continue
        if not (name in exact or name.startswith(("BUILD_", "USE_", "INSTALL_DIR"))):
            continue
        result[name] = normalize_build_path(value, prefix)
    return dict(sorted(result.items()))


def representative_hashes(prefix: pathlib.Path, linkage: str):
    candidates = [
        prefix / "include/opencascade/Standard_Version.hxx",
        prefix / "lib/cmake/opencascade/OpenCASCADEConfig.cmake",
        prefix / "lib/cmake/opencascade/OpenCASCADEConfigVersion.cmake",
    ]
    target_files = sorted((prefix / "lib/cmake/opencascade").glob("OpenCASCADE*Targets.cmake"))
    if target_files:
        candidates.append(target_files[0])
    for toolkit in ("TKernel", "TKBO", "TKDESTEP", "TKV3d", "TKService"):
        if linkage == "static":
            candidates.append(prefix / "lib" / f"lib{toolkit}.a")
        else:
            matches = sorted((prefix / "lib").glob(f"lib{toolkit}.so*"))
            real = [p for p in matches if p.is_file() and not p.is_symlink()]
            if real:
                candidates.append(real[-1])
    return {str(path.relative_to(prefix)): sha256(path) for path in candidates if path.is_file()}


def normalize_tarinfo(info: tarfile.TarInfo, epoch: int):
    info.uid = 0
    info.gid = 0
    info.uname = ""
    info.gname = ""
    info.mtime = epoch
    return info


def create_archive(args):
    prefix = pathlib.Path(args.prefix).resolve()
    output = pathlib.Path(args.output).resolve()
    epoch = int(args.source_date_epoch)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as archive:
                archive.dereference = False
                root_info = normalize_tarinfo(archive.gettarinfo(str(prefix), arcname=prefix.name), epoch)
                archive.addfile(root_info)
                paths = sorted(prefix.rglob("*"), key=lambda path: path.relative_to(prefix).as_posix())
                for path in paths:
                    arcname = (pathlib.PurePosixPath(prefix.name) / path.relative_to(prefix).as_posix()).as_posix()
                    info = normalize_tarinfo(archive.gettarinfo(str(path), arcname=arcname), epoch)
                    if info.isfile():
                        with path.open("rb") as stream:
                            archive.addfile(info, stream)
                    else:
                        archive.addfile(info)


def make_manifest(args):
    prefix = pathlib.Path(args.prefix).resolve()
    consumer = pathlib.Path(args.consumer).resolve()
    shared = real_shared_objects(prefix) if args.linkage == "shared" else []
    cmake_options = {
        "requested": requested_cmake_options(pathlib.Path(args.configure_options), prefix),
        "resolved_cache": resolved_cmake_options(pathlib.Path(args.cmake_cache), prefix),
    }
    manifest = {
        "schema_version": 1,
        "occt": {"version": args.version, "commit": args.source_sha, "event_sha": args.event_sha},
        "producer": {
            "image": args.image,
            "image_tag": args.image_tag,
            "image_digest": args.image_digest,
            "architecture": run("uname", "-m").strip(),
            "gcc": run("gcc", "--version").splitlines()[0],
            "gxx": run("g++", "--version").splitlines()[0],
            "cmake": run("cmake", "--version").splitlines()[0],
            "glibc_baseline": "2.17",
            "source_date_epoch": int(args.source_date_epoch),
        },
        "linkage": args.linkage,
        "cmake_options": cmake_options,
        "requested_modules": [
            "FoundationClasses",
            "ModelingData",
            "ModelingAlgorithms",
            "ApplicationFramework",
            "DataExchange",
        ],
        "exported_modules": exported_modules(prefix),
        "toolkits": toolkit_names(prefix, args.linkage),
        "symbol_versions": {
            "shared_objects": symbol_maxima(shared) if shared else None,
            "consumer": symbol_maxima([consumer]),
            "static_scope": (
                "consumer values qualify only archive members pulled by the fixture"
                if args.linkage == "static" else None
            ),
        },
        "representative_sha256": representative_hashes(prefix, args.linkage),
    }
    pathlib.Path(args.output).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")


def require(condition: bool, message: str):
    if not condition:
        raise RuntimeError(message)


def scan_leaks(prefix: pathlib.Path):
    for path in prefix.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        overlap = b""
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                data = overlap + chunk
                for leak in LEAK_PATHS:
                    require(leak not in data, f"producer path {leak.decode()} leaked into {path}")
                overlap = data[-64:]


def validate_prefix(args):
    prefix = pathlib.Path(args.prefix).resolve()
    require((prefix / "include/opencascade/Standard_Version.hxx").is_file(), "missing Standard_Version.hxx")
    require((prefix / "lib/cmake/opencascade/OpenCASCADEConfig.cmake").is_file(), "missing OpenCASCADEConfig.cmake")
    require((prefix / "bin/env.sh").is_file(), "missing bin/env.sh")
    for toolkit in ("TKernel", "TKBO", "TKDESTEP", "TKV3d", "TKService"):
        if args.linkage == "static":
            require((prefix / "lib" / f"lib{toolkit}.a").is_file(), f"missing static {toolkit}")
        else:
            require(any((prefix / "lib").glob(f"lib{toolkit}.so*")), f"missing shared {toolkit}")
    env_text = (prefix / "bin/env.sh").read_text(errors="replace")
    require('export THIRDPARTY_DIR=""' in env_text, "env.sh has non-empty THIRDPARTY_DIR fallback")
    scan_leaks(prefix)

    if args.linkage == "shared":
        shared = real_shared_objects(prefix)
        require(shared, "no shared OCCT ELF libraries found")
        for path in shared:
            file_text = run("file", "-b", str(path))
            require("x86-64" in file_text or "x86_64" in file_text, f"wrong architecture: {path}: {file_text}")
            dynamic = run("readelf", "-d", str(path))
            for leak in ("/work/src", "/work/build", "/work/stage", "/github/workspace", "/home/runner/work"):
                require(leak not in dynamic, f"RPATH/RUNPATH leak {leak} in {path}")
            require(not OPTIONAL_DEP_RE.search(dynamic), f"disabled optional runtime dependency in {path}\n{dynamic}")
        glibc = symbol_maxima(shared).get("GLIBC")
        require(glibc is None or version_key(glibc) <= version_key("2.17"), f"shared libraries require GLIBC_{glibc}")
    else:
        require(not any((prefix / "lib").glob("libTK*.so*")), "static SDK contains shared OCCT toolkits")


def verify_symbols(args):
    manifest = json.loads(pathlib.Path(args.manifest).read_text())
    observed = symbol_maxima([pathlib.Path(args.consumer)])
    require(observed == manifest["symbol_versions"]["consumer"], f"consumer symbols differ: {observed}")
    glibc = observed.get("GLIBC")
    require(glibc is None or version_key(glibc) <= version_key("2.17"), f"consumer requires GLIBC_{glibc}")
    if args.linkage == "shared":
        shared = real_shared_objects(pathlib.Path(args.prefix))
        observed_shared = symbol_maxima(shared)
        require(observed_shared == manifest["symbol_versions"]["shared_objects"], "shared-object symbol evidence differs")


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    manifest = sub.add_parser("manifest")
    manifest.add_argument("--prefix", required=True)
    manifest.add_argument("--consumer", required=True)
    manifest.add_argument("--cmake-cache", required=True)
    manifest.add_argument("--configure-options", required=True)
    manifest.add_argument("--linkage", choices=("shared", "static"), required=True)
    manifest.add_argument("--source-sha", required=True)
    manifest.add_argument("--event-sha", required=True)
    manifest.add_argument("--source-date-epoch", required=True)
    manifest.add_argument("--version", required=True)
    manifest.add_argument("--image", required=True)
    manifest.add_argument("--image-tag", required=True)
    manifest.add_argument("--image-digest", required=True)
    manifest.add_argument("--output", required=True)
    manifest.set_defaults(func=make_manifest)

    validate = sub.add_parser("validate-prefix")
    validate.add_argument("--prefix", required=True)
    validate.add_argument("--linkage", choices=("shared", "static"), required=True)
    validate.set_defaults(func=validate_prefix)

    verify = sub.add_parser("verify-symbols")
    verify.add_argument("--prefix", required=True)
    verify.add_argument("--consumer", required=True)
    verify.add_argument("--manifest", required=True)
    verify.add_argument("--linkage", choices=("shared", "static"), required=True)
    verify.set_defaults(func=verify_symbols)

    archive = sub.add_parser("archive")
    archive.add_argument("--prefix", required=True)
    archive.add_argument("--output", required=True)
    archive.add_argument("--source-date-epoch", required=True)
    archive.set_defaults(func=create_archive)

    args = parser.parse_args()
    try:
        args.func(args)
    except (RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
