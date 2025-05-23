FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    openssh-server \
    git \
    curl \
    fzf \
    && rm -rf /var/lib/apt/lists/*

COPY . /opt/kangaroo

RUN chmod +x /opt/kangaroo/install.sh

RUN bash /opt/kangaroo/install.sh

EXPOSE 22

CMD ["/usr/sbin/sshd", "-D"]
