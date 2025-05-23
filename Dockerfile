FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    openssh-server \
    curl \
    fzf \
    rsyslog \
    && rm -rf /var/lib/apt/lists/*

COPY . /opt/kangaroo
WORKDIR /opt/kangaroo

RUN chmod +x cli.py \
 && chmod a+x server/client.sh \
 && mkdir -p server/logs \
 && touch server/logs/ssh_login.log \
 && chmod 666 server/logs/ssh_login.log
 
# Configure rsyslog
RUN echo '##### 🦘 Kangaroo SSH JumpServer #####\n\
module(load="imudp")\n\
input(type="imudp" port="514")\n\
module(load="imtcp")\n\
input(type="imtcp" port="514")\n\
' >> /etc/rsyslog.conf



 && mkdir -p /var/log/remote \
 && chown syslog:adm /var/log/remote \
 && echo '##### 🦘 Kangaroo SSH JumpServer #####\n\
$template RemoteLog,"/var/log/remote/%HOSTNAME%.log"\n\
*.* ?RemoteLog\n\
& ~' > /etc/rsyslog.d/remote.conf

# Restrict SSH access to run client.sh
RUN echo '##### 🦘 Kangaroo SSH JumpServer #####\n\
#PubkeyAuthentication yes\n\
AuthorizedKeysFile .ssh/authorized_keys\n\
Match User *,!root\n\
    ForceCommand /opt/kangaroo/server/client.sh' >> /etc/ssh/sshd_config

EXPOSE 22 514/udp 514/tcp

# Start both sshd and rsyslog
CMD mkdir -p /run/sshd && rsyslogd && /usr/sbin/sshd -D
