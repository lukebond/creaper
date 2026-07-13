# creaper guitar addon — free/open native-Linux guitar plugins, layered on top
# of the lean base image (the base carries no plugins). Build with:
#   ./scripts/build.sh guitar
# or directly:
#   docker build -f addons/guitar.Dockerfile --build-arg BASE=creaper:latest -t creaper:guitar .
# Run it with: CREAPER_IMAGE=creaper:guitar ./run.sh
#
# ARG BASE lets addons stack (build guitar from base, then another from guitar).
ARG BASE=creaper:latest
FROM ${BASE}

USER root

# NAM and Ratatouille aren't in Arch's official repos, but the OSAMC pro-audio
# binary repo ships them prebuilt — so no AUR helper / build step is needed.
# https://github.com/osam-cologne/archlinux-proaudio
RUN pacman-key --init && \
    curl -fsSL https://arch.osamc.de/proaudio/osamc.gpg | pacman-key --add - && \
    pacman-key --lsign-key 762AE5DB2B38786364BD81C4B9141BCC62D38EE5 && \
    printf '\n[proaudio]\nServer = https://arch.osamc.de/$repo/$arch\n' >> /etc/pacman.conf

# All installs land in system scan dirs (/usr/lib/{lv2,vst3,clap}) that REAPER
# already scans — they just appear in the FX browser.
RUN pacman -Syu --noconfirm --needed \
        gxplugins.lv2 \
        guitarix \
        dragonfly-reverb-lv2 dragonfly-reverb-vst3 dragonfly-reverb-clap \
        lsp-plugins-lv2 lsp-plugins-vst3 lsp-plugins-clap \
        neural-amp-modeler-lv2 \
        ratatouille-lv2 && \
    pacman -Scc --noconfirm

USER 1000
