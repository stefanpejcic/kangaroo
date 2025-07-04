FROM ubuntu:22.04

RUN apt update && \
    apt install -y openssh-server python3 python3-yaml sudo bash

# Create SSH config folders
RUN mkdir /var/run/sshd && chmod 755 /var/run/sshd

# Copy setup script
COPY entrypoint.sh /entrypoint.sh
COPY connect-to.sh /usr/local/bin/connect-to
RUN chmod +x /entrypoint.sh /usr/local/bin/connect-to

# Default command
CMD ["/entrypoint.sh"]
