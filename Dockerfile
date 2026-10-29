FROM debian:trixie-slim

# Runtime settings are supplied by Compose or docker run.
LABEL org.opencontainers.image.source="https://github.com/felix-ciomp/cups-brother/"
LABEL org.opencontainers.image.description="CUPS Printer Server with Brother Linux driver"
LABEL org.opencontainers.image.author="Felix <felixw@163.com>"
LABEL org.opencontainers.image.url="https://github.com/felix-ciomp/cups-brother/blob/main/README.md"
LABEL org.opencontainers.image.licenses=MIT

# copy linux driver installer
COPY linux-brprinter-installer-2.2.4-1 /root/linux-brprinter-installer-2.2.4-1

# Install dependencies
RUN export DEBIAN_FRONTEND=noninteractive \
    && apt-get update -qq  && apt-get upgrade -qqy \
    && apt-get install -qqy \
    apt-utils \
    tzdata \
    usbutils \
    procps \
    cups \
    cups-filters \
    printer-driver-all \
    printer-driver-cups-pdf \
    printer-driver-foo2zjs \
    foomatic-db-compressed-ppds \
    openprinting-ppds \
    hpijs-ppds \
    hp-ppd \
    hplip \
    dbus \
    avahi-daemon \
    avahi-utils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

EXPOSE 631
EXPOSE 5353/udp

# Use CUPS itself to generate remote administration and sharing settings.
# Keep the distribution's authentication and encryption defaults.
RUN /usr/sbin/cupsd \
    && cupsctl --remote-admin --remote-any --share-printers \
    && /etc/init.d/cups stop \
    && printf '\nServerAlias *\n' >> /etc/cups/cupsd.conf \
    && /usr/sbin/cupsd -t

# back up cups configs in case used does not add their own
RUN cp -rp /etc/cups /etc/cups-bak
VOLUME [ "/etc/cups" ]

COPY avahi-daemon.conf /etc/avahi/avahi-daemon.conf
COPY entrypoint.sh /
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/sbin/cupsd", "-f"]
