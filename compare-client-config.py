"""Compare two Mattermost /api/v4/config/client?format=old dumps.

Usage: python3 -I compare-client-config.py BASE.json OTHER.json

Prints keys added, removed and changed. Values are printed only for keys
on the SHOW list; every other value is masked, so a key such as
GiphySdkKey never reaches the terminal.
"""
import json
import sys

SHOW = {
    "EnableSignUpWithGitLab", "GitLabButtonColor", "GitLabButtonText",
    "EnableSignUpWithGoogle", "EnableSignUpWithOffice365", "EnableSignUpWithOpenId",
    "BuildNumber", "Version", "BuildHash", "BuildHashEnterprise",
    "BuildEnterpriseReady", "BuildDate", "SiteURL", "IsLicensed", "AboutLink",
}


def show(key, value):
    return repr(value) if key in SHOW else "<masked>"


def main(base_path, other_path):
    with open(base_path) as f:
        base = json.load(f)
    with open(other_path) as f:
        other = json.load(f)
    added = sorted(set(other) - set(base))
    removed = sorted(set(base) - set(other))
    changed = sorted(k for k in set(base) & set(other) if base[k] != other[k])
    print(f"keys: {len(base)} -> {len(other)}")
    for k in added:
        print(f"  + {k} = {show(k, other[k])}")
    for k in removed:
        print(f"  - {k} (was {show(k, base[k])})")
    for k in changed:
        print(f"  ~ {k}: {show(k, base[k])} -> {show(k, other[k])}")
    if not (added or removed or changed):
        print("  identical")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
