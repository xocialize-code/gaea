#!/usr/bin/env python3
"""A local stand-in for GitHub's Releases API, for Gaea's plugin-manager tests.

It serves a folder laid out as <root>/<owner>/<repo>/<tag>/<asset files> the way api.github.com serves a repo's
releases, so Gaea's real install path (GAEA_GITHUB_API=http://127.0.0.1:<port>) can be pointed at releases that
GitHub doesn't have: a tampered bundle, an ad-hoc-signed one, a second version.

    python3 tools/release-standin.py <root> [--port 8766]

GET /repos/<owner>/<repo>/releases               the releases, newest tag first
GET /repos/<owner>/<repo>/releases/assets/<id>   an asset's bytes (the API path Gaea uses with a token)
GET /download/<owner>/<repo>/<tag>/<name>        an asset's bytes (the public download link)

A file named `notes.md` in a tag's folder becomes the release body, and `prerelease` marks it a pre-release.
"""
import argparse
import hashlib
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import quote, unquote, urlparse


def asset_id(owner, repo, tag, name):
    return int(hashlib.sha256(f"{owner}/{repo}/{tag}/{name}".encode()).hexdigest()[:12], 16)


def version_key(tag):
    core = tag.lstrip("vV").split("-")[0]
    try:
        return tuple(int(p) for p in core.split("."))
    except ValueError:
        return (0,)


class Handler(BaseHTTPRequestHandler):
    root = "."

    def log_message(self, fmt, *args):
        sys.stderr.write("standin: " + fmt % args + "\n")

    def send(self, status, body, content_type="application/json"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def releases(self, owner, repo):
        base = os.path.join(self.root, owner, repo)
        if not os.path.isdir(base):
            return None
        origin = f"http://{self.headers.get('Host')}"
        out = []
        for tag in sorted(os.listdir(base), key=version_key, reverse=True):
            folder = os.path.join(base, tag)
            if not os.path.isdir(folder):
                continue
            names = sorted(n for n in os.listdir(folder) if n not in ("notes.md", "prerelease"))
            notes = os.path.join(folder, "notes.md")
            out.append({
                "tag_name": tag,
                "draft": False,
                "prerelease": os.path.exists(os.path.join(folder, "prerelease")),
                "body": open(notes).read() if os.path.exists(notes) else f"Stand-in release {tag}",
                "published_at": "2026-10-28T00:00:00Z",
                "html_url": f"{origin}/{owner}/{repo}/releases/tag/{tag}",
                "assets": [{
                    "id": asset_id(owner, repo, tag, n),
                    "name": n,
                    "size": os.path.getsize(os.path.join(folder, n)),
                    "url": f"{origin}/repos/{owner}/{repo}/releases/assets/{asset_id(owner, repo, tag, n)}",
                    "browser_download_url": f"{origin}/download/{owner}/{repo}/{quote(tag)}/{quote(n)}",
                } for n in names],
            })
        return out

    def do_GET(self):
        parts = [unquote(p) for p in urlparse(self.path).path.strip("/").split("/")]
        if len(parts) == 4 and parts[0] == "repos" and parts[3] == "releases":
            releases = self.releases(parts[1], parts[2])
            if releases is None:
                return self.send(404, b'{"message":"Not Found"}')
            return self.send(200, json.dumps(releases).encode())
        if len(parts) == 6 and parts[0] == "repos" and parts[3:5] == ["releases", "assets"]:
            owner, repo, wanted = parts[1], parts[2], int(parts[5])
            for tag in os.listdir(os.path.join(self.root, owner, repo)):
                folder = os.path.join(self.root, owner, repo, tag)
                for name in os.listdir(folder):
                    if asset_id(owner, repo, tag, name) == wanted:
                        return self.send(200, open(os.path.join(folder, name), "rb").read(), "application/octet-stream")
            return self.send(404, b'{"message":"Not Found"}')
        if len(parts) == 5 and parts[0] == "download":
            path = os.path.join(self.root, *parts[1:])
            if os.path.isfile(path):
                return self.send(200, open(path, "rb").read(), "application/octet-stream")
        self.send(404, b'{"message":"Not Found"}')


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("root")
    parser.add_argument("--port", type=int, default=8766)
    args = parser.parse_args()
    Handler.root = os.path.abspath(args.root)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"release stand-in on http://127.0.0.1:{args.port} serving {Handler.root}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
