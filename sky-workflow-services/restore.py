import json, os, sys, time, urllib.request, urllib.error

base = 'http://127.0.0.1:5244/api'
with open(os.environ['ALIST_BACKUP_PATH'], encoding='utf-8-sig') as f:
    backup = json.load(f)
if backup.get('encrypted'):
    raise RuntimeError('Backup encryption requires a password')

def call(method, path, obj=None, token=None):
    data = None if obj is None else json.dumps(obj, ensure_ascii=False).encode()
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = token
    req = urllib.request.Request(base + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            result = json.load(response)
    except urllib.error.HTTPError as e:
        raise RuntimeError(f'{path}: HTTP {e.code}') from None
    if result.get('code') != 200:
        raise RuntimeError(f'{path}: API code {result.get("code")}')
    return result.get('data')

password = os.environ['ALIST_BOOTSTRAP_PASSWORD']
for attempt in range(45):
    try:
        token = call('POST', '/auth/login', {'username':'admin', 'password':password})['token']
        break
    except Exception:
        if attempt == 44:
            raise RuntimeError('AList startup/login failed') from None
        time.sleep(2)

def entries(path):
    data = call('GET', path, token=token)
    return data if isinstance(data, list) else (data or {}).get('content', [])

def restore_items(kind, items, key, current, create, update):
    old = {str(row.get(key)): row for row in entries(current)}
    count = 0
    for item in items or []:
        item = dict(item)
        previous = old.get(str(item.get(key)))
        item['id'] = previous.get('id') if previous else 0
        try:
            call('POST', update if previous else create, item, token)
        except RuntimeError:
            if kind != 'storages' or not any(str(x.get(key)) == str(item.get(key)) for x in entries(current)):
                raise
            print('storage configuration saved, but driver initialization failed: ' + str(item.get('driver')), flush=True)
        count += 1
    print(f'{kind}: {count} restored', flush=True)

roles = backup.get('roles') or []
restore_items('roles', [r for r in roles if r.get('name') != 'admin'], 'name', '/admin/role/list', '/admin/role/create', '/admin/role/update')
current_roles = {r.get('name'): r.get('id') for r in entries('/admin/role/list')}
role_map = {r.get('id'): current_roles.get(r.get('name')) for r in roles}
settings = [s for s in backup.get('settings', []) if s.get('key') not in ('version','index_progress','token') and not (s.get('key') == 'default_role' and s.get('value') in ('admin','guest'))]
if settings:
    call('POST', '/admin/setting/save', settings, token)
    print(f'settings: {len(settings)} restored', flush=True)
restore_items('storages', backup.get('storages'), 'mount_path', '/admin/storage/list', '/admin/storage/create', '/admin/storage/update')
restore_items('metas', backup.get('metas'), 'path', '/admin/meta/list', '/admin/meta/create', '/admin/meta/update')
restore_items('labels', backup.get('labels'), 'name', '/label/list', '/admin/label/create', '/admin/label/update')
existing_users = {u.get('username'): u for u in entries('/admin/user/list')}
users = []
for row in backup.get('users') or []:
    row = dict(row)
    prior = existing_users.get(row.get('username'))
    if prior and row.get('username') in ('admin', 'guest'):
        row['role'] = prior.get('role')
    else:
        legacy = row.get('role')
        legacy = legacy if isinstance(legacy, list) else [legacy]
        row['role'] = [role_map[v] for v in legacy if role_map.get(v) is not None]
    users.append(row)
restore_items('users', users, 'username', '/admin/user/list', '/admin/user/create', '/admin/user/update')
bindings = backup.get('label_file_bindings') or []
if bindings:
    call('POST','/admin/label_file_binding/restore',{'keep_ids':True,'override':True,'bindings':bindings},token)
print('Restore completed; passwords absent in backup cannot be restored.', flush=True)
