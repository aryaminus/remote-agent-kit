"""Remap stale Mac project_roots in ControlKeel project.json bindings.

Runs ON THE BOX (invoked by ck-replica.sh after transfer). Idempotent:
only rewrites files whose root actually changes.

Usage: python3 ck-remap.py <box_user> <mac_dev_root>
Example: python3 ck-remap.py hermes /Users/aryaminus/Developer

Mapping:
  <mac_dev_root>/<proj>[/...] -> /home/<box_user>/work/<proj>[/...]
  <mac_home>                  -> /home/<box_user>
(where <mac_home> is the parent of <mac_dev_root>.)

Deliberately untouched: workspace_id, session_id, org_id, agent.
ControlKeel reconciles those itself on first use from the bound directory
(verified live: stale bindings resolve sessions with zero errors after
the path fix). Rewriting ids blindly would be worse than leaving them.
"""
import glob
import json
import os
import re
import sys


def main():
    box_user = sys.argv[1] if len(sys.argv) > 1 else "agentbox"
    mac_dev = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/Developer")
    mac_home = os.path.dirname(mac_dev.rstrip("/"))
    box_home = "/home/" + box_user
    box_work = box_home + "/work"

    patterns = [
        (re.compile("^" + re.escape(mac_dev) + r"/([^/]+)(.*)$"),
         lambda m: box_work + "/" + m.group(1) + m.group(2)),
    ]

    def remap(root):
        if not isinstance(root, str):
            return root, False
        for rx, fn in patterns:
            m = rx.match(root)
            if m:
                return fn(m), True
        if root == mac_home:
            return box_home, True
        return root, False

    files = [box_home + "/controlkeel/project.json"] + sorted(
        glob.glob(box_work + "/*/controlkeel/project.json"))
    changed = 0
    for f in files:
        try:
            with open(f) as fh:
                d = json.load(fh)
        except Exception as exc:
            print("SKIP (unreadable): %s (%s)" % (f, exc))
            continue
        new_root, did = remap(d.get("project_root"))
        if did:
            d["project_root"] = new_root
            with open(f, "w") as fh:
                json.dump(d, fh, indent=2)
            print("FIXED: %s -> %s" % (f, new_root))
            changed += 1
        else:
            print("OK already: %s" % f)
    print("remapped: %d" % changed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
