#!/usr/bin/env python3
import ast
import json
import pathlib
import re
import sys


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
PROFILE_PATH = REPO_ROOT / ".github/occt-sdk-release/lean-profile.json"


def read(path: str) -> str:
    return (REPO_ROOT / path).read_text(encoding="utf-8")


def python_constant(path: str, name: str):
    tree = ast.parse(read(path), filename=path)
    for node in tree.body:
        if not isinstance(node, ast.Assign):
            continue
        if any(isinstance(target, ast.Name) and target.id == name for target in node.targets):
            return list(ast.literal_eval(node.value))
    raise RuntimeError(f"{path}: constant {name} was not found")


def shell_json_variable(path: str, name: str):
    text = read(path)
    match = re.search(rf"(?m)^{re.escape(name)}='([^']+)'$", text)
    if match is None:
        raise RuntimeError(f"{path}: shell variable {name} was not found")
    return json.loads(match.group(1))


def shell_build_profile(path: str):
    text = read(path)
    roots = re.findall(r'-DBUILD_ADDITIONAL_TOOLKITS=([^"\n]+)', text)
    disabled = re.findall(r'"-D([A-Za-z0-9_]+)=OFF"', text)
    return roots, disabled


def powershell_array(text: str, variable: str):
    match = re.search(
        rf"[\$]{re.escape(variable)}\s*=\s*@\((.*?)\n\s*\)",
        text,
        re.DOTALL,
    )
    if match is None:
        raise RuntimeError(f"PowerShell profile: ${variable} array was not found")
    return re.findall(r"'([^']+)'", match.group(1))


def release_expected_toolkits():
    path = ".github/occt-sdk-release/verify-release-assets.sh"
    text = read(path)
    match = re.search(
        r'expected_toolkits="\$\(cat <<\x27EOF\x27\n(.*?)\nEOF\n\)"',
        text,
        re.DOTALL,
    )
    if match is None:
        raise RuntimeError(f"{path}: expected_toolkits heredoc was not found")
    return match.group(1).splitlines()


def report_equal(errors, label: str, observed, expected):
    if observed != expected:
        errors.append(f"{label}: expected {expected!r}, observed {observed!r}")


def report_contains_all(errors, label: str, observed, expected):
    missing = [value for value in expected if value not in observed]
    if missing:
        errors.append(f"{label}: missing {missing!r}")


def main() -> int:
    profile = json.loads(PROFILE_PATH.read_text(encoding="utf-8"))
    roots = profile["requested_toolkits"]
    expected = profile["expected_toolkits"]
    disabled = profile["common_disabled_cmake_options"]
    errors = []

    report_equal(errors, "schema_version", profile.get("schema_version"), 1)
    if len(roots) != 5 or len(set(roots)) != len(roots):
        errors.append(f"canonical requested_toolkits must contain 5 unique entries: {roots!r}")
    if len(expected) != 28 or len(set(expected)) != len(expected):
        errors.append(f"canonical expected_toolkits must contain 28 unique entries: {expected!r}")
    if not set(roots).issubset(expected):
        errors.append("canonical requested_toolkits are not all present in expected_toolkits")
    if len(disabled) != len(set(disabled)):
        errors.append(f"canonical common_disabled_cmake_options contains duplicates: {disabled!r}")

    report_equal(
        errors,
        "Linux sdk_tools.py LEAN_ROOT_TOOLKITS",
        python_constant(".github/linux-occt-sdk/sdk_tools.py", "LEAN_ROOT_TOOLKITS"),
        roots,
    )
    report_equal(
        errors,
        "Linux sdk_tools.py EXPECTED_TOOLKITS",
        python_constant(".github/linux-occt-sdk/sdk_tools.py", "EXPECTED_TOOLKITS"),
        expected,
    )
    report_equal(
        errors,
        "macOS sdk_tools.py REQUESTED_TOOLKITS",
        python_constant(".github/macos-occt-sdk/sdk_tools.py", "REQUESTED_TOOLKITS"),
        roots,
    )
    report_equal(
        errors,
        "macOS sdk_tools.py EXPECTED_TOOLKITS",
        python_constant(".github/macos-occt-sdk/sdk_tools.py", "EXPECTED_TOOLKITS"),
        expected,
    )

    for platform in ("linux", "macos"):
        verifier = f".github/{platform}-occt-sdk/verify-release-assets.sh"
        report_equal(
            errors,
            f"{platform} release verifier root_toolkits",
            shell_json_variable(verifier, "root_toolkits"),
            roots,
        )
        report_equal(
            errors,
            f"{platform} release verifier expected_toolkits",
            shell_json_variable(verifier, "expected_toolkits"),
            expected,
        )

        build_script = f".github/{platform}-occt-sdk/build-sdk.sh"
        build_roots, build_disabled = shell_build_profile(build_script)
        report_equal(
            errors,
            f"{platform} build BUILD_ADDITIONAL_TOOLKITS occurrence count",
            len(build_roots),
            1,
        )
        if build_roots:
            report_equal(
                errors,
                f"{platform} build BUILD_ADDITIONAL_TOOLKITS",
                build_roots[0].split(";"),
                roots,
            )
        report_contains_all(
            errors,
            f"{platform} build common disabled CMake options",
            build_disabled,
            disabled,
        )

    report_equal(
        errors,
        "combined release verifier expected_toolkits",
        release_expected_toolkits(),
        expected,
    )

    windows_profile = read(".github/windows-occt-sdk/lean-profile.ps1")
    report_equal(
        errors,
        "Windows LeanRootToolkits",
        powershell_array(windows_profile, "LeanRootToolkits"),
        roots,
    )
    report_equal(
        errors,
        "Windows LeanExpectedToolkits",
        powershell_array(windows_profile, "LeanExpectedToolkits"),
        expected,
    )
    report_equal(
        errors,
        "Windows LeanDisabledCMakeOptions",
        powershell_array(windows_profile, "LeanDisabledCMakeOptions"),
        disabled,
    )

    for helper in (
        ".github/windows-occt-sdk/configure-lean.ps1",
        ".github/windows-occt-sdk/verify-lean-install.ps1",
    ):
        if "lean-profile.ps1" not in read(helper):
            errors.append(f"{helper}: does not import lean-profile.ps1")

    if errors:
        print("Lean profile consistency check failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(
        "Lean profile copies match the canonical contract: "
        f"{len(roots)} roots, {len(expected)} toolkits, "
        f"{len(disabled)} common disabled CMake options."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
