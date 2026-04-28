#!/usr/bin/env python3
"""Publish CEF build artifacts to a GitLab release.

Creates a tag and release if they don't exist, or appends asset links to an
existing release (for multi-architecture builds where the other arch published
first).

Artifacts are uploaded directly to the GitLab generic package registry so
they persist independently of CI job artifact expiration.

Required environment variables:
    ARCH             - Build architecture (amd64, arm64, armhf)
    DEB_VERSION      - Full Debian version (e.g. 147.0.3+ds3-1)
    ARTIFACT_DIR     - Artifact subdirectory name (e.g. build-output-amd64)
    CI_API_V4_URL    - GitLab API base URL
    CI_PROJECT_ID    - GitLab project numeric ID
    CI_PROJECT_URL   - GitLab project web URL
    CI_COMMIT_SHA    - Git commit SHA to tag
    SALSA_API_TOKEN  - Personal Access Token with api scope
"""

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request


def api(method, url, token, data=None):
    """Make a GitLab API request. Returns (success, response_body)."""
    payload = json.dumps(data).encode() if data else None
    req = urllib.request.Request(
        url,
        data=payload,
        headers={"Content-Type": "application/json", "PRIVATE-TOKEN": token},
        method=method,
    )
    try:
        resp = urllib.request.urlopen(req)
        body = resp.read().decode()
        return (True, json.loads(body) if body else None)
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        if e.code in (400, 404, 409):
            return (False, body)
        print(f"ERROR {e.code}: {body}", file=sys.stderr)
        raise


def upload_file(base_api, token, ver, filename, filepath):
    """Upload a file to the GitLab generic package registry.

    Returns the download URL on success, None on failure.
    """
    pkg_name = "cef-release"
    pkg_ver = urllib.parse.quote(ver, safe="")
    fname = urllib.parse.quote(filename, safe="")
    url = f"{base_api}/packages/generic/{pkg_name}/{pkg_ver}/{fname}"

    with open(filepath, "rb") as f:
        file_data = f.read()

    req = urllib.request.Request(
        url,
        data=file_data,
        headers={"PRIVATE-TOKEN": token, "Content-Type": "application/octet-stream"},
        method="PUT",
    )
    try:
        resp = urllib.request.urlopen(req)
        return url
    except urllib.error.HTTPError as e:
        # 409 = already uploaded (idempotent)
        if e.code == 409:
            print(f"  {filename}: already uploaded")
            return url
        print(f"  ERROR uploading {filename}: {e.code} {e.read().decode()}",
              file=sys.stderr)
        return None


def main():
    arch = os.environ["ARCH"]
    ver = os.environ["DEB_VERSION"]
    major = ver.split(".")[0]
    tag = f"debian/{ver}"
    artifact_dir = os.environ["ARTIFACT_DIR"]
    base_api = (
        f"{os.environ['CI_API_V4_URL']}/projects/{os.environ['CI_PROJECT_ID']}"
    )
    token = os.environ["SALSA_API_TOKEN"].strip()
    sha = os.environ["CI_COMMIT_SHA"]
    tag_encoded = urllib.parse.quote(tag, safe="")

    # Step 1: ensure tag exists at current commit
    ok, _ = api(
        "POST",
        f"{base_api}/repository/tags",
        token,
        {"tag_name": tag, "ref": sha},
    )
    if ok:
        print(f"Tag {tag} created")
    else:
        print(f"Tag {tag} already exists")

    # Step 2: collect artifact files for this architecture
    pkg = "chromium-embedded-framework"
    files = [
        f"libcef{major}_{ver}_{arch}.deb",
        f"libcef{major}-dbgsym_{ver}_{arch}.deb",
        f"libcef-dev_{ver}_{arch}.deb",
        f"libcef-common_{ver}_all.deb",
        f"{pkg}_{ver}.dsc",
        f"{pkg}_{ver}.debian.tar.xz",
        f"{pkg}_{ver}_{arch}.buildinfo",
        f"{pkg}_{ver}_{arch}.changes",
    ]

    # Step 3: upload each file to generic package registry
    print(f"Uploading {arch} artifacts to package registry")
    links = []
    for filename in files:
        filepath = os.path.join(artifact_dir, filename)
        if not os.path.exists(filepath):
            print(f"  {filename}: not found, skipping")
            continue
        url = upload_file(base_api, token, ver, filename, filepath)
        if url:
            link_type = "package" if filename.endswith(".deb") else "other"
            links.append({"name": filename, "url": url, "link_type": link_type})
            print(f"  {filename}: uploaded")

    if not links:
        print("ERROR: no files uploaded", file=sys.stderr)
        sys.exit(1)

    # Step 4: create release or append links to existing one
    ok, _ = api(
        "POST",
        f"{base_api}/releases",
        token,
        {
            "name": ver,
            "tag_name": tag,
            "description": (
                f"Debian binary packages for Chromium Embedded Framework {ver}."
            ),
            "assets": {"links": links},
        },
    )
    if ok:
        print(f"Release {tag} created with {arch} assets")
    else:
        # Release exists (other arch published first) -- append links
        print(f"Release {tag} exists -- appending {arch} asset links")
        for link in links:
            ok, _ = api(
                "POST",
                f"{base_api}/releases/{tag_encoded}/assets/links",
                token,
                link,
            )
            status = "added" if ok else "skipped (already exists)"
            print(f"  {link['name']}: {status}")


if __name__ == "__main__":
    main()
