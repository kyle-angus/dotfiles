FROM ubuntu:20.04

RUN apt-get update && apt-get upgrade -y 
RUN apt-get install -y man-db

RUN yes | unminimize

ENV TZ=America/New_York
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
  && echo $TZ > /etc/timezone
RUN set -xe \
  && apt-get install -y sudo git curl wget vim tmux fzf lynx build-essential \
  && useradd -m -p "9CULiXg7pmeWc" -s /bin/bash kangus \
  && usermod -aG sudo kangus \
  && mkdir -p /etc/sudoers.d \
  && touch /etc/sudoers.d/kangus \
  && echo "kangus ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/kangus \
  && chmod 0440 /etc/sudoers.d/kangus

USER kangus:kangus

WORKDIR /home/kangus

CMD ["/bin/bash"]
