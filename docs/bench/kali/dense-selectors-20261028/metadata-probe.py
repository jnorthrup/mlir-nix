import os, pathlib, time, datetime
print(datetime.datetime.now(datetime.timezone.utc).isoformat())
print('loadavg',os.getloadavg())
print('\n'.join(line for line in pathlib.Path('/proc/meminfo').read_text().splitlines() if line.startswith(('MemAvailable:','SwapFree:','SwapTotal:'))))
paths=[]
for p in pathlib.Path('/proc').glob('[0-9]*/comm'):
 try:
  if p.read_text().strip()=='java': paths.append(p.parent)
 except OSError: pass

def ticks(p):
 fields=(p/'stat').read_text().rsplit(')',1)[1].split()
 return int(fields[11])+int(fields[12])
first={p:ticks(p) for p in paths}
t0=time.monotonic();time.sleep(1);dt=time.monotonic()-t0
for p,t in first.items():
 try: print('java',p.name,'current_cpu_percent',round(100*(ticks(p)-t)/os.sysconf('SC_CLK_TCK')/dt,1))
 except OSError: pass
