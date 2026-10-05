"""Local translation editor. Python 3.10+, standard library only."""
import argparse
from collections import Counter
from datetime import datetime
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
import shutil
import threading
from urllib.parse import urlparse
import webbrowser
ROOT=Path(__file__).resolve().parent
PREFIX=re.compile(r"\A(?:(?:\s*//[^\r\n]*(?:\r?\n|$))|(?:\s*<(?:PARTVOICE|voice)\b[^>]*>))+\s*",re.I)
PROTECTED=re.compile(r'(?m)^[ \t]*//【[^\r\n]*(?:\r?\n)?|<[^>]+>|%(?:\d+\$)?[a-zA-Z]|\\[nrt]')
STATUSES={'machine-translated','reviewed','needs-context','needs-fit','translation-error','new'}
def split_prefix(text):
    match=PREFIX.match(text)
    return (text[:match.end()],text[match.end():]) if match else ('',text)
class Catalog:
    def __init__(self,path):
        self.path=path.resolve();self.lock=threading.Lock()
        self.rows=[json.loads(line) for line in self.path.read_text(encoding='utf-8-sig').splitlines() if line]
        self.by_id={r['id']:r for r in self.rows}
        if len(self.by_id)!=len(self.rows):raise ValueError('Duplicate catalog IDs')
        self.backup=None
    def public_rows(self):
        with self.lock:
            return [dict(id=r['id'],file=r['file'],source=split_prefix(r['source'])[1],
                         translation=split_prefix(r.get('translation',''))[1],status=r.get('status','new'),
                         speaker=(re.search(r'//【(.*?)】',r['source']).group(1) if re.search(r'//【(.*?)】',r['source']) else ''),
                         editable=not re.search(r'media/script/lang/en/',r['source']) and bool(r.get('translation')))
                    for r in self.rows]
    def update(self,record_id,translation,status):
        if not isinstance(translation,str) or len(translation)>100000:raise ValueError('Invalid translation')
        if status not in STATUSES:raise ValueError('Invalid status')
        with self.lock:
            old=self.by_id[record_id]
            if re.search(r'media/script/lang/en/',old['source']) or not old.get('translation'):
                raise ValueError('Technical entry')
            prefix,_=split_prefix(old['translation']);revised=prefix+translation
            if '\x00' in revised:raise ValueError('NUL characters are not allowed')
            if Counter(PROTECTED.findall(revised))!=Counter(PROTECTED.findall(old['source'])):
                raise ValueError('Служебные теги и команды должны остаться без изменений.')
            if not self.backup:
                folder=self.path.parent/'backups';folder.mkdir(exist_ok=True)
                backup=folder/(self.path.stem+'-'+datetime.now().strftime('%Y%m%d-%H%M%S-%f')+'.jsonl')
                shutil.copy2(self.path,backup);self.backup=backup
            changed=dict(old,translation=revised,status=status);temporary=self.path.with_suffix('.jsonl.tmp')
            try:
                with temporary.open('w',encoding='utf-8',newline='\n') as stream:
                    for row in self.rows:stream.write(json.dumps(changed if row is old else row,ensure_ascii=False)+'\n')
                temporary.replace(self.path)
            finally:
                if temporary.exists():temporary.unlink()
            old.clear();old.update(changed)
            return {'ok':True,'backup':str(self.backup),'sha256':hashlib.sha256(self.path.read_bytes()).hexdigest()}
def handler(catalog):
    class Handler(BaseHTTPRequestHandler):
        def send(self,data,status=200,kind='application/json; charset=utf-8'):
            encoded=json.dumps(data,ensure_ascii=False).encode() if kind.startswith('application/json') and not isinstance(data,bytes) else data
            self.send_response(status);self.send_header('Content-Type',kind)
            self.send_header('Content-Length',str(len(encoded)));self.send_header('Cache-Control','no-store')
            self.send_header('X-Content-Type-Options','nosniff');self.end_headers();self.wfile.write(encoded)
        def do_GET(self):
            path=urlparse(self.path).path
            if path=='/api/catalog':self.send({'path':str(catalog.path),'records':catalog.public_rows()})
            elif path in ('/','/index.html'):self.send((ROOT/'index.html').read_bytes(),kind='text/html; charset=utf-8')
            elif path=='/metrics.json':self.send((ROOT/'metrics.json').read_bytes())
            else:self.send({'error':'Not found'},404)
        def do_POST(self):
            origin=self.headers.get('Origin')
            if origin and origin!='http://'+self.headers.get('Host',''):
                self.send({'error':'Origin rejected'},403);return
            if urlparse(self.path).path!='/api/record':self.send({'error':'Not found'},404);return
            try:
                size=int(self.headers.get('Content-Length','0'))
                if not 0<size<200000:raise ValueError('Invalid request size')
                payload=json.loads(self.rfile.read(size))
                self.send(catalog.update(payload['id'],payload['translation'],payload['status']))
            except (KeyError,ValueError) as error:self.send({'error':str(error)},400)
            except OSError as error:self.send({'error':'Не удалось сохранить файл: '+str(error)},500)
    return Handler
def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('catalog',nargs='?',type=Path,default=ROOT/'translations/translation.jsonl')
    parser.add_argument('--port',type=int,default=8775);parser.add_argument('--no-open',action='store_true')
    args=parser.parse_args();catalog=Catalog(args.catalog)
    server=ThreadingHTTPServer(('127.0.0.1',args.port),handler(catalog));url=f'http://127.0.0.1:{args.port}/'
    print(f'Slow Damage editor: {url}\nCatalog: {catalog.path}\nCtrl+C to stop.',flush=True)
    if not args.no_open:threading.Timer(.5,lambda:webbrowser.open(url)).start()
    try:server.serve_forever()
    except KeyboardInterrupt:pass
    finally:server.server_close()
if __name__=='__main__':main()
