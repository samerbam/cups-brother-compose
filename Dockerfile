FROM debian:stable-slim

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
    avahi-daemon \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

EXPOSE 631
EXPOSE 5353/udp

# Baked-in config file changes
RUN sed -i 's/Listen localhost:631/Listen 0.0.0.0:631/' /etc/cups/cupsd.conf && \
    sed -i 's/Browsing Off/Browsing On/' /etc/cups/cupsd.conf && \
    sed -i 's/<Location \/>/<Location \/>\n  Allow All/' /etc/cups/cupsd.conf && \
    sed -i 's/<Location \/admin>/<Location \/admin>\n  Allow All\n  Require user @SYSTEM/' /etc/cups/cupsd.conf && \
    sed -i 's/<Location \/admin\/conf>/<Location \/admin\/conf>\n  Allow All/' /etc/cups/cupsd.conf && \
    echo "ServerAlias *" >> /etc/cups/cupsd.conf && \
    echo "DefaultEncryption Never" >> /etc/cups/cupsd.conf

# back up cups configs in case used does not add their own
RUN cp -rp /etc/cups /etc/cups-bak
VOLUME [ "/etc/cups" ]

COPY entrypoint.sh /
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
