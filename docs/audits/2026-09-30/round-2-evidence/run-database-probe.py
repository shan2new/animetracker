"""Create, migrate, probe, and remove only a newly owned disposable audit database."""
from pathlib import Path
import json
import os
import re
import subprocess
import uuid

evidence = Path(__file__).resolve().parent
root = evidence.parents[3]
server = root / 'server'
name = 'previously_release_audit_tests_20260930_' + uuid.uuid4().hex[:8]
assert re.fullmatch(r'previously_release_audit_tests_20260930_[a-f0-9]{8}', name)

def psql(query, variables=None):
    cmd = ['psql', '-h', '127.0.0.1', '-d', 'postgres', '-X', '-At', '-v', 'ON_ERROR_STOP=1']
    for key, value in (variables or {}).items():
        cmd += ['-v', f'{key}={value}']
    return subprocess.run(cmd, input=query, text=True, capture_output=True, check=True).stdout.strip()

assert psql("select count(*) from pg_database where datname = :'audit_name';", {'audit_name': name}) == '0'
env = dict(os.environ)
env.update(DATABASE_URL=f'postgres://127.0.0.1:5432/{name}', APP_ENV='test', DEV_AUTH_BYPASS='1',
           CLERK_SECRET_KEY='', CLERK_JWT_KEY='', OPENROUTER_API_KEY='', CEREBRAS_API_KEY='',
           TMDB_ACCESS_TOKEN='', NEWS_AGENT_DISABLED='1', GROUPING_LLM_DISABLED='1',
           SEARCH_CORRECT_DISABLED='1', SOCIAL_COMMENTS_ENABLED='0', MODERATION_ALERT_WEBHOOK_URL='')
created = False
ledger = {'database': name, 'host': '127.0.0.1', 'removed': False}
try:
    subprocess.run(['createdb', '-h', '127.0.0.1', name], check=True)
    created = True
    with (evidence / 'database-migrate.log').open('w') as log:
        subprocess.run(['npm', 'run', 'db:migrate'], cwd=server, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    with (evidence / 'database-probe.log').open('w') as log:
        subprocess.run([str(server / 'node_modules/.bin/tsx'), str(evidence / 'database-probe.ts')],
                       cwd=server, env=env, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=60)
finally:
    if created:
        assert psql("select count(*) from pg_stat_activity where datname = :'audit_name';", {'audit_name': name}) == '0'
        subprocess.run(['dropdb', '-h', '127.0.0.1', name], check=True)
        ledger['removed'] = True
    (evidence / 'database-probe-run.json').write_text(json.dumps(ledger, indent=2) + '\n')
print(json.dumps(ledger))
