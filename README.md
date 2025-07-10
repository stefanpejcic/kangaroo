# Kangaroo SSH JumpServer 🦘
SSH jumpserver - **not** for production use.

## How It Works

1. Define users in the `users.yml` file, along with the list of servers each user is allowed to access.
2. Start the container.
3. On startup, a `servers.yml` file is generated for each user based on the `users.yml` configuration.
4. The user logs in via SSH to the container.
5. Upon login, the user can select any server listed in their `servers.yml` file.
6. An SSH connection is then established to the selected remote server.

## Install

docker:

```
git clone --branch containerssh https://github.com/stefanpejcic/kangaroo.git && \
docker build kangaroo/. -t kangaroo:latest.
```

```
docker run -d \
  --name kangaroo \
  -v ./users.conf:/etc/users.conf:ro \
  -p 2222:22 \
  kangaroo:latest
```
