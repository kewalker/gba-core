"""Run portable playtime simulations. SPDX-License-Identifier: GPL-3.0-only"""
import argparse,json,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--run',required=True,type=Path);p.add_argument('--iverilog-bin',type=Path);a=p.parse_args()
run=a.run.resolve();run.mkdir(parents=True,exist_ok=False);results=[]
def save(status,error=''):(run/'receipt.json').write_text(json.dumps(dict(status=status,error=error,tests=results),indent=2)+'\n')
def tool(name):
 path=(a.iverilog_bin/(name+('.exe' if __import__('os').name=='nt' else ''))) if a.iverilog_bin else shutil.which(name)
 if not path:raise RuntimeError('Missing '+name+'; add it to PATH or use --iverilog-bin')
 return str(path)
def execute(name,args,marker=None):
 r=subprocess.run(list(map(str,args)),cwd=ROOT,capture_output=True,text=True,timeout=240);output=r.stdout+r.stderr;(run/(name+'.log')).write_text(output)
 if r.returncode or (marker and marker not in output):raise RuntimeError(name+' failed; see '+str(run/(name+'.log')))
 return r.returncode
try:
 save('RUNNING');compiler=tool('iverilog');simulator=tool('vvp');rtl=sorted((ROOT/'src/rtl/overlay').glob('*.sv'))
 for name in ('format','decode','overlay','clock','host-0','host-1'):
  kind=name.split('-')[0];top='gba_playtime_'+kind+'_tb';binary=run/(name+'.vvp');opts=['-P'+top+'.ENDIAN_LITTLE='+name[-1]] if kind=='host' else []
  execute(name+'-compile',[compiler,'-g2012','-s',top,*opts,'-o',binary,*rtl,ROOT/'src/tb'/(top+'.sv')])
  code=execute(name,[simulator,binary],'PASS:');results.append(dict(name=name,status='PASS',exit_code=code));save('RUNNING');print('PASS: '+name,flush=True)
 save('PASS')
except Exception as e:save('FAILED',str(e));raise
