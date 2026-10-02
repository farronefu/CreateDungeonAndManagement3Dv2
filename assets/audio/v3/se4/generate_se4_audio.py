from pathlib import Path
import numpy as np, wave, math, json, hashlib, shutil, zipfile, html, base64

ROOT=Path(r'C:\Users\ikuya\Documents\GitHub\CreateDungeonAndManagement3Dv2')
OUT=Path(__file__).with_name('monsterchain-se4-audio')
(OUT/'audio').mkdir(parents=True,exist_ok=True)
SR=32000
rng=np.random.default_rng(2026100203)
def band_noise(ms,lo,hi):
    n=round(ms*SR/1000)
    pad=max(128,n)
    y=rng.normal(size=n+2*pad)
    f=np.fft.rfftfreq(len(y),1/SR)
    y=np.fft.irfft(np.fft.rfft(y)*((f>=lo)&(f<=hi)),n=len(y))[pad:pad+n]
    return y/(np.sqrt(np.mean(y*y))+1e-12)
def edge(y,attack_ms,release_ms):
    y=y.copy();na=min(len(y),round(attack_ms*SR/1000));nr=min(len(y),round(release_ms*SR/1000))
    if na:y[:na]*=np.linspace(0,1,na)
    if nr:y[-nr:]*=np.linspace(1,0,nr)
    return y
def grain(ms,lo,hi,decay):
    y=band_noise(ms,lo,hi);t=np.arange(len(y))/SR
    return edge(y*np.exp(-decay*t),.6,4)
def swell(ms,lo,hi):
    y=band_noise(ms,lo,hi)
    return y*np.maximum(0,np.sin(np.linspace(0,np.pi,len(y))))**1.6
def add(y,start_ms,part,gain):
    start=round(start_ms*SR/1000);n=min(len(part),len(y)-start)
    if n>0:y[start:start+n]+=part[:n]*gain
def filter_signal(y,hp=35,lp=6500):
    n=len(y);pad=max(n,1024);z=np.pad(y,(pad,pad));f=np.fft.rfftfreq(len(z),1/SR)
    gain=np.ones_like(f)
    if hp:gain*=np.sqrt(1/(1+(hp/np.maximum(f,1e-12))**8));gain[0]=0
    if lp:gain*=np.sqrt(1/(1+(f/lp)**8))
    return np.fft.irfft(np.fft.rfft(z)*gain,n=len(z))[pad:pad+n]
def buf(ms):return np.zeros(round(ms*SR/1000))
qa=[];records=[]
def write(key,y,peak,usage):
    y=edge(filter_signal(y),1,15)
    y*=10**(peak/20)/(np.max(np.abs(y))+1e-15)
    # Individual recipe levels, never a shared loudness target.
    pcm=np.rint(np.clip(y,-1,1)*32767).astype('<i2')
    p=OUT/'audio'/(key+'.wav')
    with wave.open(str(p),'wb') as w:w.setparams((1,2,SR,len(pcm),'NONE','not compressed'));w.writeframes(pcm.tobytes())
    v=pcm.astype(np.float64)/32768
    q={'key':key,'sample_rate':SR,'channels':1,'seconds':len(v)/SR,'peak_dbfs':20*math.log10(max(np.max(np.abs(v)),1e-15)),'rms_dbfs':20*math.log10(max(np.sqrt(np.mean(v*v)),1e-15)),'clipped_samples':int(np.sum(np.abs(pcm.astype(np.int32))>=32767)),'first_sample':int(pcm[0]),'last_sample':int(pcm[-1]),'dc_offset':float(np.mean(v)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
    assert q['clipped_samples']==0 and q['first_sample']==0 and q['last_sample']==0
    assert abs(q['peak_dbfs']-peak)<.01
    qa.append(q);records.append({'key':key,'file':'assets/audio/se/'+key+'.wav','seconds':q['seconds'],'sha256':q['sha256'],'usage':usage,'status':'generated_recipe_se4','peak_dbfs_target':peak})

y=buf(300)
for i,(at,ms,gain) in enumerate(zip([0,18,62,113,172],[85,60,48,44,35],[1,.5,.25,.13,.07])):add(y,at,grain(ms,280,3400,65 if i==0 else 105),gain)
add(y,0,grain(65,170,850,78),.38)
write('torch_break',y,-10,'松明破壊。太い木の割れと小さい破片。')
y=buf(180);add(y,0,swell(90,130,850),.47)
for at,ms,gain in zip([13,36,59,86,118],[27,21,31,30,34],[.4,.22,.2,.12,.075]):add(y,at,grain(ms,440,1900,95),gain)
add(y,52,swell(93,650,2100),.11)
write('spawn_moss',y,-21,'草・コケの誕生。音階のないごく小さい葉擦れ。')
y=buf(245);add(y,0,swell(135,170,1080),.34);add(y,53,swell(85,380,1450),.18);add(y,105,grain(52,430,2450,90),.22);add(y,122,swell(108,690,2600),.14)
for at,gain in [(154,.07),(186,.045)]:add(y,at,grain(30,550,2000,110),gain)
write('grass_evolve',y,-20,'草がBUD/FLOWERへ進化。根と芽の小さな有機音。')
y=buf(120);add(y,0,grain(80,130,730,62),.62);add(y,8,grain(55,380,1350,90),.23)
write('moss_hit',y,-15,'草の実際の命中。弱い無音程の体当たり。')
y=buf(155);add(y,0,grain(85,850,5300,65),.75);add(y,14,grain(75,400,2300,72),.35)
for at,gain in [(30,.2),(55,.09)]:add(y,at,grain(29,1300,5000,110),gain)
write('tree_hit',y,-10,'進化草BUD/FLOWERの実際の命中。短いザクッ。')
y=buf(255)
for at,ms,gain in zip([0,22,57,96,137,185],[60,55,53,62,54,43],[.43,.35,.3,.22,.16,.085]):add(y,at,swell(ms,850,4400),gain)
write('moss_die',y,-15,'草・コケの撃破/捕食成立。枝を折らず葉が散る。')
y=buf(235);add(y,0,swell(36,360,1900),.17);add(y,22,grain(78,550,4300,88),.95);add(y,28,grain(60,210,900,83),.31)
for at,gain in zip([41,78,119,164],[.39,.16,.085,.04]):add(y,at,grain(35,790,3500,130),gain)
write('tree_die',y,-11,'進化草BUD/FLOWERの撃破/捕食成立。引っ張られた枝折れ。')
y=buf(245);t=np.arange(round(.175*SR))/SR;freq=195+(103-195)*np.minimum(t/.17,1);phase=2*np.pi*np.cumsum(freq)/SR
buzz=sum(np.sin(h*phase+.08*h)/h**1.45 for h in range(1,13));env=np.minimum(t/.012,1)*np.maximum(0,1-t/.175)**1.5
buzz=buzz*env*(.76+.18*np.sin(2*np.pi*39*t))*.37
add(y,0,filter_signal(buzz,hp=None,lp=2600),1);add(y,137,grain(70,950,4100,73),.31)
write('bee_die',y,-13,'蜂の撃破。短い羽の失速と破片、ジングルなし。')
y=buf(440)
for midi,at in zip([62,66,64,69],[0,75,190,265]):
    t=np.arange(round(.160*SR))/SR;phase=2*np.pi*440*2**((midi-69)/12)*t
    tone=(np.sin(phase+.32*np.sin(2*phase))+.10*np.sin(3*phase))*np.exp(-24*t)
    add(y,at,edge(tone,3,30),.46)
write('ui_confirm',y,-12,'はい/いいえ、画面遷移、魔王配置成功、強化購入成功の共通電子決定音。')
# Exact isolated low term from the old place synthesizer, rendered first at its original rate.
oldsr=22050;n=round(.185*oldsr);t=np.arange(n)/oldsr;frequency=90+(45-90)*(t/.5);phase=np.cumsum(frequency/oldsr)
low=np.sin(phase*2*np.pi)*.9*np.minimum(1,t/.004)*np.exp(-6*t)
low=np.trunc(np.clip(low,-1,1)*32000).astype(np.int16).astype(float)/32768
y=np.interp(np.arange(round(.185*SR))/SR,t,low);y=filter_signal(y,hp=None,lp=210);y=edge(y,3,38)
write('miss',y,-12,'空振り・操作不成立。旧placeの先頭低音だけ。880Hz成分なし。')

existing=['bee_attack','pillbug_die','hero_hit','dig','spawn_bug','pillbug_evolve','grab','door','victory','defeat']
for key in existing+['ui_move']:
    source=ROOT/'assets/audio/se'/('click.wav' if key=='ui_move' and (ROOT/'assets/audio/se/click.wav').exists() else key+'.wav')
    target=OUT/'audio'/(key+'.wav');shutil.copyfile(source,target)
    assert hashlib.sha256(target.read_bytes()).digest()==hashlib.sha256(source.read_bytes()).digest()
    with wave.open(str(target),'rb') as w:seconds=w.getnframes()/w.getframerate()
    uses={'bee_attack':'蜂の対勇者命中・捕食成立。','pillbug_die':'ダンゴムシ・丸まり進化中の死亡。','hero_hit':'勇者の剣の実命中。','dig':'掘削成功。','spawn_bug':'ダンゴムシ誕生。','pillbug_evolve':'ダンゴムシから蜂への進化。','grab':'魔王捕獲。','door':'門の開閉。','victory':'勝利。','defeat':'敗北。'}
    records.append({'key':key,'file':'assets/audio/se/'+key+'.wav','sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'seconds':seconds,'status':'byte_identical_copy','source':source.name,'usage':'UI選択移動。旧clickのバイト完全コピー。' if key=='ui_move' else uses[key]+'既存素材を完全保持。'})
manifest={'version':'SE4','seed':2026100203,'new_sample_rate':SR,'normalization':'Per-recipe peak targets only; quiet grass levels preserved. Existing recordings copied byte for byte.','subjective_listening_performed':False,'se':records,'legacy_synthesized_keys':['heal','cutin'],'bgm':'unchanged'}
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(OUT/'audio_QA.json').write_text(json.dumps(qa,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
cards=[]
for row in records:
    data=base64.b64encode((OUT/'audio'/(row['key']+'.wav')).read_bytes()).decode()
    cards.append('<article><h2>'+html.escape(row['key'])+'</h2><p>'+html.escape(row['usage'])+'</p><audio controls preload="none" src="data:audio/wav;base64,'+data+'"></audio><small>'+str(row['seconds'])+'秒 · '+('既存素材そのまま' if row['status']=='byte_identical_copy' else str(row['peak_dbfs_target'])+' dBFS')+'</small></article>')
page='''<!doctype html><html lang="ja"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>MonsterChain SE4 個別試聴</title><style>body{margin:0;background:#101b16;color:#ecf3e8;font:16px/1.6 system-ui}main{max-width:1100px;margin:auto;padding:36px}h1{font-size:32px}section{display:grid;grid-template-columns:repeat(auto-fit,minmax(290px,1fr));gap:16px}article{background:#1c2d23;border:1px solid #39543d;border-radius:16px;padding:22px}h2{margin:0;color:#c9e69a}audio{width:100%;margin:12px 0}small{display:block;color:#bac9b4}header{margin-bottom:28px}</style><main><header><h1>MonsterChain SE4 · 個別試聴</h1><p>命中・死亡・UI操作を用途ごとに整理した音源です。草の誕生と進化は意図して小さい音量です。プレーヤー音量を揃えて比較してください。</p><p>数値検査済み。耳による主観的評価は未実施。BGMと既存10音は変更していません。heal/cutinはゲーム内の既存合成を維持します。</p></header><section>'''+''.join(cards)+'</section></main></html>'
preview=OUT/'MonsterChain_SE4_個別試聴.html';preview.write_text(page,encoding='utf-8')
source=Path(__file__);shutil.copyfile(source,OUT/'generate_se4_audio.py')
bundle=OUT/'MonsterChain_SE4_全SE_WAV.zip'
with zipfile.ZipFile(bundle,'w',zipfile.ZIP_DEFLATED) as z:
    for f in sorted((OUT/'audio').glob('*.wav')):z.write(f,'assets/audio/se/'+f.name)
    for name in ['manifest.json','audio_QA.json','generate_se4_audio.py']:z.write(OUT/name,name)
    z.write(preview,preview.name)
print(json.dumps({'preview':str(preview),'zip':str(bundle),'zip_sha256':hashlib.sha256(bundle.read_bytes()).hexdigest(),'recorded_se_count':len(records),'generated_se_count':len(qa),'qa_all_pass':True},ensure_ascii=False))
