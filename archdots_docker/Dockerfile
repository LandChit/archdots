FROM archlinux:latest

# Everything a fresh Arch box would already have. Deliberately minimal: the
# point of the test is that install.sh installs the rest itself, so anything
# added here is something the script is no longer being tested on.
#
# base-devel and git are the genuine prerequisites (makepkg needs base-devel to
# bootstrap paru). sudo, because the script refuses to run as root and calls
# sudo for pacman. The rest are the bits archinstall would leave behind.
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
      base-devel git sudo \
      mesa libxkbcommon wayland xorg-xwayland seatd && \
    pacman -Scc --noconfirm

# The script refuses to run as root — stow, the venv and gsettings must be the
# user's. NOPASSWD so an unattended --yes run is not blocked on a prompt.
RUN useradd -m -G wheel -s /bin/bash tester && \
    echo "tester ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/tester

# uid 1000 matches the usual first host user, which is what makes the host's
# Wayland socket readable when it is bind-mounted in for a nested session.
# The directory has to exist and be owned by tester before docker mounts into it.
RUN install -d -o tester -g tester -m 0700 /run/user/1000

USER tester
WORKDIR /home/tester

# The repo is NOT copied in. runscript.sh mounts it read-only at /src and copies
# it to a writable path inside the container, so editing install.sh does not
# mean rebuilding this image.
CMD ["/bin/bash"]
