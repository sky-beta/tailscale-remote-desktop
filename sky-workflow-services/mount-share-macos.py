import os, pty, select, signal, subprocess, sys, time

url = 'https://striking-rebecka-wxj3837-0de393a2.koyeb.app/alist/dav/'
username = os.environ['SHARED_ALIST_USERNAME']
password = os.environ['SHARED_ALIST_PASSWORD']

def mount_for(user, home):
    dest = home + '/Desktop/AList共享'
    if user == os.environ.get('USER'):
        os.makedirs(dest, exist_ok=True)
        args = ['mount_webdav', '-i', '-v', 'AList', url, dest]
    else:
        subprocess.run(['sudo','mkdir','-p',dest], check=True)
        subprocess.run(['sudo','chown',user+':staff',dest], check=True)
        args = ['sudo','-u',user,'mount_webdav','-i','-v','AList',url,dest]
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(args[0], args)
    data=b''; sent_user=False; sent_password=False; deadline=time.time()+90
    while time.time() < deadline:
        ready,_,_=select.select([fd],[],[],1)
        if ready:
            try: data += os.read(fd,4096)
            except OSError: pass
            lower=data.lower()
            if not sent_user and (b'username' in lower or b'user name' in lower):
                os.write(fd,(username+'\n').encode()); sent_user=True; data=b''
            if not sent_password and b'password' in lower:
                os.write(fd,(password+'\n').encode()); sent_password=True; data=b''
        done,status=os.waitpid(pid,os.WNOHANG)
        if done:
            code=os.waitstatus_to_exitcode(status)
            if code: raise RuntimeError('WebDAV mount failed for ' + user)
            print('Shared drive mounted for ' + user, flush=True)
            return
    os.kill(pid,signal.SIGTERM)
    raise RuntimeError('WebDAV mount timed out for ' + user)

mount_for(os.environ.get('USER','runner'), os.path.expanduser('~'))
if subprocess.run(['id','-u','skyremote'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode == 0:
    mount_for('skyremote','/Users/skyremote')
