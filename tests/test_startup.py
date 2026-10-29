from pathlib import Path
import os, subprocess, tempfile
source=(Path(__file__).resolve().parents[1]/'entrypoint.sh').read_text().split('# Migrate daemon settings once,')[1]
with tempfile.TemporaryDirectory() as temporary:
    root=Path(temporary)
    conf=root/'cups'; conf.mkdir()
    skeleton=root/'cups-bak'; skeleton.mkdir()
    for name in ['cupsd.conf','cups-files.conf']:
        (conf/name).write_text('old '+name)
        (skeleton/name).write_text('new '+name)
    (conf/'printers.conf').write_text('existing printer')
    (conf/'ppd').mkdir(); (conf/'ppd'/'printer.ppd').write_text('existing driver')
    trace=root/'trace'
    def command(name, body):
        p=root/name; p.write_text('#!/bin/bash\n'+body+'\n');p.chmod(0o755); return str(p)
    daemon=command('cupsd','echo "cupsd:$*" >> "$TRACE"')
    service=command('service','echo "service:$*" >> "$TRACE"')
    pgrep=command('pgrep','exit "${DUPLICATE:-1}"')
    installer=command('installer','echo "installer:$1" >> "$TRACE"; cat >/dev/null')
    dbus_uuidgen=command('dbus-uuidgen','echo uuidgen >> "$TRACE"')
    dbus_daemon=command('dbus-daemon','echo dbus-start >> "$TRACE"')
    dbus_send=command('dbus-send','''if [[ "$*" == *org.freedesktop.DBus.ListNames* ]]; then
    exit "${BUS_MISSING:-1}"
fi
echo avahi-ready >> "$TRACE"''')
    avahi=command('avahi-daemon','''if [[ "$1" == --check ]]; then
    exit "${AVAHI_MISSING:-1}"
fi
echo avahi-start >> "$TRACE"''')
    script=root/'startup' 
    code='set -euo pipefail\n# Migrate daemon settings once,'+source
    for old,new in [('/etc/cups-bak',str(skeleton)),('/etc/cups',str(conf)),('/usr/sbin/cupsd',daemon),('/etc/init.d/cups',service),('/root/linux-brprinter-installer-2.2.4-1',installer),('pgrep -x cupsd',pgrep+' -x cupsd'),('/run/dbus',str(root/'run-dbus')),('/run/avahi-daemon',str(root/'run-avahi')),('dbus-uuidgen --ensure',dbus_uuidgen+' --ensure'),('dbus-daemon --system',dbus_daemon+' --system'),('dbus-send --system',dbus_send+' --system'),('avahi-daemon --check',avahi+' --check'),('avahi-daemon --daemonize',avahi+' --daemonize')]:
        code=code.replace(old,new)
    script.write_text(code)
    env={**os.environ,'TRACE':str(trace),'CUPSBRPRINTER':'TEST-MODEL','CUPS_ENABLE_AVAHI':'false'}
    def run(extra=None):
        trace.write_text('')
        return subprocess.run(['bash',str(script),daemon,'-f'],env={**env,**(extra or {})},capture_output=True,text=True)
    r=run(); assert r.returncode==0,r.stderr
    assert (conf/'cupsd.conf').read_text()=='new cupsd.conf'
    backups=list(conf.glob('.before-config-v2.*')); assert len(backups)==1
    assert (backups[0]/'cupsd.conf').read_text()=='old cupsd.conf'
    assert (conf/'printers.conf').read_text()=='existing printer'
    assert (conf/'ppd'/'printer.ppd').read_text()=='existing driver'
    assert trace.read_text().splitlines()==['cupsd:-t','installer:TEST-MODEL','service:stop','cupsd:-t','cupsd:-f']
    (conf/'cupsd.conf').write_text('later customization')
    r=run({'CUPSBRPRINTER':''}); assert r.returncode==0,r.stderr
    assert (conf/'cupsd.conf').read_text()=='later customization'
    assert len(list(conf.glob('.before-config-v2.*')))==1
    assert trace.read_text().splitlines()==['service:stop','cupsd:-t','cupsd:-f']
    r=run({'DUPLICATE':'0'}); assert r.returncode!=0
    assert 'cupsd:-f' not in trace.read_text()
    (conf/'.container-config-v2').unlink(); (conf/'cupsd.conf').unlink()
    r=run({'CUPSBRPRINTER':''}); assert r.returncode==0,r.stderr
    assert (conf/'cupsd.conf').read_text()=='new cupsd.conf'
    r=run({'CUPS_ENABLE_AVAHI':'true','CUPSBRPRINTER':''}); assert r.returncode==0,r.stderr
    assert trace.read_text().splitlines()==['service:stop','cupsd:-t','uuidgen','dbus-start','avahi-start','avahi-ready','cupsd:-f']
    r=run({'CUPS_ENABLE_AVAHI':'true','CUPSBRPRINTER':'','BUS_MISSING':'0','AVAHI_MISSING':'0'}); assert r.returncode==0,r.stderr
    assert trace.read_text().splitlines()==['service:stop','cupsd:-t','uuidgen','avahi-ready','cupsd:-f']
    print('Bonjour startup ordering and reuse checks passed.')
    print('Passed: existing/fresh config migration, backup, queues/PPDs preserved, repeat startup, empty model, and duplicate scheduler rejection.')
