# Kangaroo SSH JumpServer 🦘
Open source SSH jumpserver - **not** for production use.

## Install

docker:

```
git clone https://github.com/stefanpejcic/kangaroo/ kangaroo & &docker build kangaroo/. -t kangaroo:latest.

```

```
docker run -d \
  --name kangaroo \
  -v ./users.conf:/etc/users.conf:ro \
  -p 2222:22 \
  kangaroo:latest

```
