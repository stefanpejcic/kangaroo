FROM ubuntu:22.04

RUN apt update && \
    apt install -y openssh-server python3 python3-yaml sudo bash

# Create SSH config folders
RUN mkdir /var/run/sshd && chmod 755 /var/run/sshd

RUN rm -f /etc/update-motd.d/* \
 && sed -i 's/^PrintMotd yes/PrintMotd no/' /etc/ssh/sshd_config \
 && sed -i 's/^session optional pam_motd.so/#&/' /etc/pam.d/sshd

# Copy setup script
COPY entrypoint.sh /entrypoint.sh
COPY connect-to.sh /usr/local/bin/connect-to
RUN chmod +x /entrypoint.sh /usr/local/bin/connect-to

# Default command
CMD ["/entrypoint.sh"]
