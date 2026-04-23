#!/usr/bin/env python3
"""Publish CEF build artifacts to a GitLab release.

Creates a tag and release if they don't exist, or appends asset links to an
existing release (for multi-architecture builds where the other arch published
first).

Required environment variables:
    ARCH             - Build architecture (amd64, arm64)
    BUILD_JOB_ID     - GitLab CI job ID that produced the artifacts
    DEB_VERSION      - Full Debian version (e.g. 147.0.3+ds2-1)
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


def main():
    arch = os.environ["ARCH"]
    ver = os.environ["DEB_VERSION"]
    major = ver.split(".")[0]
    tag = f"debian/{ver}"
    job_id = os.environ["BUILD_JOB_ID"]
    artifact_dir = os.environ["ARTIFACT_DIR"]
    base_api = (
        f"{os.environ['CI_API_V4_URL']}/projects/{os.environ['CI_PROJECT_ID']}"
    )
    base_url = (
        f"{os.environ['CI_PROJECT_URL']}/-/jobs/{job_id}"
        f"/artifacts/raw/{artifact_dir}"
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

    # Step 2: build asset links for this architecture
    pkg = "chromium-embedded-framework"
    links = [
        # Binary packages (arch-specific)
        {
            "name": f"libcef{major}_{ver}_{arch}.deb",
            "url": f"{base_url}/libcef{major}_{ver}_{arch}.deb",
            "link_type": "package",
        },
        {
            "name": f"libcef{major}-dbgsym_{ver}_{arch}.deb",
            "url": f"{base_url}/libcef{major}-dbgsym_{ver}_{arch}.deb",
            "link_type": "package",
        },
        {
            "name": f"libcef-dev_{ver}_{arch}.deb",
            "url": f"{base_url}/libcef-dev_{ver}_{arch}.deb",
            "link_type": "package",
        },
        {
            "name": f"libcef-common_{ver}_all.deb",
            "url": f"{base_url}/libcef-common_{ver}_all.deb",
            "link_type": "package",
        },
        # Source package (for mentors/sponsor review)
        {
            "name": f"{pkg}_{ver}.dsc",
            "url": f"{base_url}/{pkg}_{ver}.dsc",
            "link_type": "other",
        },
        {
            "name": f"{pkg}_{ver}.debian.tar.xz",
            "url": f"{base_url}/{pkg}_{ver}.debian.tar.xz",
            "link_type": "other",
        },
        # Build metadata (arch-specific)
        {
            "name": f"{pkg}_{ver}_{arch}.buildinfo",
            "url": f"{base_url}/{pkg}_{ver}_{arch}.buildinfo",
            "link_type": "other",
        },
        {
            "name": f"{pkg}_{ver}_{arch}.changes",
            "url": f"{base_url}/{pkg}_{ver}_{arch}.changes",
            "link_type": "other",
        },
    ]

    # Step 3: create release or append links to existing one
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

    # Step 4: mark build job artifacts as permanent
    ok, _ = api(
        "POST",
        f"{base_api}/jobs/{job_id}/artifacts/keep",
        token,
    )
    if ok:
        print(f"Artifacts for job {job_id} marked as permanent")
    else:
        print(f"Could not mark artifacts for job {job_id} as permanent")


if __name__ == "__main__":
    main()
