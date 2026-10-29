#!/bin/bash
set -euo pipefail
exec 9>/tmp/kb/gen.lock
flock -n 9
cd "$HOME/work/mlir-nix-dense-selectors-20261028"
out=/tmp/kb/list-returns-20261028-v1/pmu-confirmation
[ ! -e "$out" ] || { echo "Confirmation already exists; will not restart or overwrite" >&2; exit 2; }
mkdir "$out"
cp "$0" "$out/commands.sh"
python3 - "$out" <<'PY'
from pathlib import Path
import subprocess,sys,datetime,hashlib,json,os
out=Path(sys.argv[1]);binary=Path('/tmp/kb/list-returns-20261028-v1/mlnix')
expected='a34739ca7f9dddaf7db70c45fa33c445b3ead6192e8bb5b2736527797b227e14'
base_env={k:v for k,v in os.environ.items() if not k.startswith('MLNIX_')}
base_env.update(MLNIX_JIT='1',MLNIX_STORE_ROOT='/tmp/mlnix-np-root',MLNIX_STATE_DIR='/tmp/mlnix-np-state')
orders=[['on','off'],['off','on'],['on','off']]
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def snapshot(name):
 lines=[now(),'loadavg '+Path('/proc/loadavg').read_text().strip(),subprocess.run(['free','-m'],text=True,capture_output=True,check=True).stdout.strip()]
 procs=subprocess.run(['ps','-eo','pid,ppid,comm,etime,pcpu,pmem'],text=True,capture_output=True,check=True).stdout.splitlines()
 selected=[p for p in procs[1:] if len(p.split())>2 and p.split()[2] in ('java','mlnix','mlnix-opt','ninja','cmake','clang-22','clang++-22','cc1plus')]
 lines+=['Relevant process CPU percentages are lifetime averages:',procs[0],'\n'.join(selected) if selected else 'No java/mlnix/build processes present']
 (out/name).write_text('\n'.join(lines)+'\n')
def check_binary():
 h=hashlib.sha256(binary.read_bytes()).hexdigest();assert h==expected,(h,expected);return h
manifest={'purpose':'Exactly three additional balanced PMU pairs per workload; preserve original off/on pair0. No new speed claim.','binary':str(binary),'binary_sha256':check_binary(),'new_pairs':{str(i):order for i,order in enumerate(orders,1)},'original_pair0':{'order':['off','on'],'files':'../pmu-lists-{off,on}-{workload}.json'},'environment':{'clear':'all inherited MLNIX_* variables','MLNIX_JIT':'1','MLNIX_DEFER':'1 (child command)','MLNIX_JIT_LISTS':'0 for off, absent for on','MLNIX_JIT_THRESHOLD':'absent/default1024','MLNIX_STORE_ROOT':'/tmp/mlnix-np-root','MLNIX_STATE_DIR':'/tmp/mlnix-np-state','other_feature_overrides':'absent','stats_and_profile':'absent'},'output_validation':'hw-counters.py discards stdout and checks exit only; full outputs validated in preserved profiles and timing series. No tool modification.','scope':'user-space inherited threads/children; PMU timings are diagnostic, not new timing-series measurements','started':now()}
(out/'parameters.json').write_text(json.dumps(manifest,indent=2)+'\n')
for workload in ('nixos-toplevel','nixpkgs-73'):
 args=['instantiate','--readonly-mode','--eval','--strict','test/nixos-toplevel.nix','--arg','nixpkgs','./.cache/nixpkgs'] if workload=='nixos-toplevel' else ['instantiate','--readonly-mode','--eval','--strict','--json','test/nixpkgs-drvs.nix','--argstr','system','x86_64-linux']
 for index,order in enumerate(orders,1):
  prefix=f'pair-{index}-{workload}'
  metadata={'pair':index,'workload':workload,'order':order,'binary_sha256':check_binary(),'started':now(),'arms':[]}
  snapshot(prefix+'-host-before.txt')
  for mode in order:
   env=base_env.copy()
   if mode=='off':env['MLNIX_JIT_LISTS']='0'
   command=['python3','scripts/hw-counters.py','--','env','MLNIX_DEFER=1',str(binary),*args]
   name=f'pair-{index}-lists-{mode}-{workload}.json'
   arm={'mode':mode,'file':name,'command':command,'settings':{'MLNIX_JIT':'1','MLNIX_JIT_LISTS':'0' if mode=='off' else 'absent','MLNIX_JIT_THRESHOLD':'absent/default1024'},'started':now()}
   with (out/name).open('w') as stream:
    child=subprocess.run(command,env=env,stdout=stream)
   arm.update(finished=now(),exit_code=child.returncode)
   metadata['arms'].append(arm)
   (out/(prefix+'-metadata.json')).write_text(json.dumps(metadata,indent=2)+'\n')
   assert child.returncode==0,(workload,index,mode,child.returncode)
   result=json.loads((out/name).read_text());assert result['exit_code']==0
   assert all('scaled' in v and v['running_ns']>0 for v in result['events'].values()),'PMU unavailable; stop without retry'
  metadata.update(finished=now(),final_binary_sha256=check_binary())
  (out/(prefix+'-metadata.json')).write_text(json.dumps(metadata,indent=2)+'\n')
  print('completed',prefix,'order',','.join(order),flush=True)
snapshot('host-complete.txt')
(out/'complete.txt').write_text('All six new pairs completed; original pair0 unchanged; no builds, gates, timing series or references executed.\n')
PY
