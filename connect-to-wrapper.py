#!/usr/bin/env python3
import os
import sys
import yaml
import subprocess

username = os.getenv("USER")
config_path = f"/home/{username}/servers.yaml"

if not os.path.exists(config_path):
    print("No servers configured.")
    sys.exit(1)

if len(sys.argv) != 2:
    print("Usage: connect-to <target>")
    sys.exit(1)

target = sys.argv[1]

with open(config_path, "r") as f:
    servers = yaml.safe_load(f)

match = next((s for s in servers if s["name"] == target), None)

if not match:
    print("Access denied.")
    sys.exit(1)

subprocess.run(["ssh", f'{match["user"]}@{match["host"]}'])
