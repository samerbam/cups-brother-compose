# CUPS-docker

Run a CUPS print server on a remote machine to share USB printers over WiFi. Built primarily to use with Raspberry Pis as a headless server, but there is no reason this wouldn't work on `amd64` machines. Tested and confirmed working on a Raspberry Pi 3B+ (`arm/v7`) and Raspberry Pi 4 (`arm64/v8`).

Container packages available from Docker Hub and Github Container Registry (ghcr.io)
  - Docker Hub Image: `anujdatar/cups`
  - GHCR Image: `ghcr.io/anujdatar/cups`

## Usage

Build and run this repository on a Linux host with access to the printer's USB bus:

```sh
cp .env.example .env
# Edit .env, particularly CUPS_PASSWORD, TIMEZONE, and CUPS_BR_PRINTER.
docker compose up -d --build
```

Compose builds the local Dockerfile. All deployment settings live in `.env`
and are passed at runtime; no build arguments are needed. `.env` and the default
configuration directory are excluded from Git and the Docker build context.

| Compose variable | Default | Purpose |
| --- | --- | --- |
| `CUPS_HOSTNAME` | `cups` | Container hostname, also used by Avahi for its `.local` name |
| `CUPS_ENABLE_AVAHI` | `true` | Start the container system bus and Bonjour advertiser; set `false` to disable |
| `CUPS_ADMIN_USER` | `admin` | CUPS administrator (`CUPSADMIN` inside the container) |
| `CUPS_PASSWORD` | Required | Administrator password (`CUPSPASSWORD`) |
| `TIMEZONE` | `Etc/UTC` | Installed IANA timezone name (`TZ`) |
| `CUPS_BR_PRINTER` | Empty | Brother model (`CUPSBRPRINTER`); installer runs only when a model is specified |
| `CONFIG_PATH` | `./config` | Persistent CUPS configuration directory |
| `CUPS_BIND_ADDRESS` | `0.0.0.0` | Host address for the published web/IPP port |
| `CUPS_PORT` | `631` | Host port; container continues listening on 631 |
| `CUPS_USB_PATH` | `/dev/bus/usb` | Host USB path mounted at `/dev/bus/usb` |
| `CUPS_CONTAINER_NAME` | `cups` | Container name |
| `CUPS_RESTART_POLICY` | `unless-stopped` | Container restart policy |

After editing `.env`, run `docker compose up -d` to recreate the container with
the new settings. Credentials and timezone are applied on each startup. Changing
the admin name creates a new administrator; it does not remove the old account
from an existing container. Recreating the container starts with fresh accounts.
The Brother installer runs on each startup when a model is set and may require
network access. Its background CUPS service is stopped before the container starts
its foreground server, keeping web and local authentication in the same process.
Changing the model does not remove old queues or drivers.

For direct `docker run` usage, supply `CUPSADMIN`, `CUPSPASSWORD`, and `TZ`
explicitly, and optionally `CUPSBRPRINTER`. The image contains no default password.
The CUPS configuration enables remote administration and printer sharing using
`cupsctl`, preserving Debian's default password authentication and encryption
settings. Use `https://<server-address>:<CUPS_PORT>/admin/` for administration.
CUPS may present a self-signed certificate on your local network.

### AirPrint / Bonjour discovery on your LAN

The image starts D-Bus and Avahi before its final CUPS server. CUPS registers
shared queues with Avahi, supplying each queue's description and IPP capabilities.
There is no manually maintained AirPrint service file. This enables discovery;
actual AirPrint printing still depends on the driver and document formats the
queue supports.

For a Linux Docker host such as HexOS/TrueNAS, use the standalone
`docker-compose.airprint.yml` file **instead of** `docker-compose.yml`:

```sh
docker compose -f docker-compose.airprint.yml up -d --build
```

In Dockhand, set the repository's Compose file path to
`docker-compose.airprint.yml`, pull the latest revision, rebuild, and recreate.
Keep your current `CONFIG_PATH` and runtime variables. Do not deploy both Compose
files as separate stacks or combine them as overrides.

This file uses host networking so multicast discovery reaches your LAN. It does
not publish ports: CUPS listens directly on host TCP port 631, and Avahi uses UDP
5353. `CUPS_PORT` and `CUPS_BIND_ADDRESS` apply only to the original bridge-mode
file. Check that host TCP 631 is free before switching. Other host mDNS responders
can coexist when they also permit shared multicast sockets; if Avahi reports a
conflict, inspect the host's mDNS setup rather than disabling system services.
Host networking also allows CUPS to listen on all host interfaces; use the host
firewall to restrict access to your intended LAN.

The original `docker-compose.yml` retains bridge networking and configurable
published ports. Avahi can run there, but ordinary port publishing alone does not
make its multicast announcements available on your LAN.

After deploying, confirm the printer is shared in the CUPS administration page.
On a Mac on the same network, `dns-sd -Z _ipp._tcp local.` should list a record
whose `rp` field is `printers/HL3170CDW` (or your actual queue name). The advertised
hostname must resolve to your NAS's reachable LAN address. The printer description
can be changed using CUPS's Modify Printer page.

### Updating an existing installation in Dockhand

Pull the latest Git revision, rebuild the image, and recreate the container.
Restarting an existing container does not apply image changes. Keep the existing
`CONFIG_PATH` and environment variables.

On its first startup with this version, the container saves the existing
`cupsd.conf` and `cups-files.conf` in a private `.before-config-v2.*` directory
inside `CONFIG_PATH`, then installs the new daemon settings. Existing printer
queues, PPDs, and TLS certificates remain in place. Custom daemon settings must
be reapplied after migration. The `.container-config-v2` marker prevents subsequent
starts from replacing your settings again.

The entrypoint completes Brother installation, stops its temporary background
CUPS service, checks that no scheduler remains, and then executes `cupsd -f`.
If cleanup fails, startup fails rather than launching a second scheduler.
For direct `docker run` usage, the default command is already provided; commands
passed after the image name replace it.

## Server Administration
You should now be able to access CUPS admin server using the IP address of your headless computer/server http://192.168.xxx.xxx:631, or whatever. If your server has avahi-daemon/mdns running you can use the hostname, http://printer.local:631. (IP and hostname will vary, these are just examples)

If you are running this on your PC, i.e. not on a headless server, you should be able to log in on http://localhost:631

## Thanks
Based on the work done by **RagingTiger**: [https://github.com/RagingTiger/cups-airprint](https://github.com/RagingTiger/cups-airprint)

Startup and configuration structure informed by [ydkn/docker-cups](https://gitlab.com/ydkn/docker-cups/).
