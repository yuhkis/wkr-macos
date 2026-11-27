(function () {
  'use strict';
  const data = window.WKR_DATA, aggregate = window.WKRProgress;
  const el = id => document.getElementById(id);
  const ids = data.lessons.map(l => l.id);
  const storageKey = 'wakara.practice.v2.' + data.layoutVersion;
  const bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.wkrProgress;
  let progress = aggregate.clean(null, ids, data.layoutVersion), save = false;
  let lessonIndex = 0, itemIndex = 0, keyIndex = 0, correct = 0, total = 0, mode = 'trial';
  const trial = window.WKRTrial.create(data.rules), freeTrial = window.WKRTrial.create(data.rules, 1000);
  let composing = false, justComposed = false, compositionEnter = 'none', itemDone = false, lessonDone = false;
  const isEnter = e => e.key === 'Enter' || e.code === 'Enter' || e.code === 'NumpadEnter' || e.keyCode === 13;
  const shortcut = e => e.metaKey || e.ctrlKey || e.altKey;
  const native = message => { if (bridge) bridge.postMessage(message); };
  const status = text => { el('storage-status').textContent = text; };
  function read() {
    if (bridge) { native({action:'load'}); return; }
    try {
      const raw = localStorage.getItem(storageKey);
      if (raw) { progress = aggregate.clean(JSON.parse(raw), ids, data.layoutVersion); save = true; }
    } catch (_) { status('保存データを読み込めません。保存せずに練習できます。'); }
    el('save').checked = save; renderNav();
  }
  // Native host returns validated aggregates only; no lesson text is bridged.
  window.wkrReceiveProgress = value => {
    if (value && value.error) { save=false; el('save').checked=false; status('保存処理を完了できませんでした。保存先を確認してください。'); return; }
    save=!!(value && value.enabled); progress=aggregate.clean(value && value.progress,ids,data.layoutVersion);
    el('save').checked=save; renderNav();
    status(save ? 'このアプリ内に成績を保存しています。' : '成績の保存はオフです。');
  };
  function persist() {
    if (!save) return;
    const safe=aggregate.clean(progress,ids,data.layoutVersion);
    if (bridge) { native({action:'save',progress:safe}); return; }
    try { localStorage.setItem(storageKey,JSON.stringify(safe)); status('このブラウザに課題別の成績を保存しました。'); }
    catch (_) { save=false; el('save').checked=false; status('成績を保存できません。保存せずに練習を続けます。'); }
  }
  function clearSaved() {
    save=false;el('save').checked=false;
    progress=aggregate.clean(null,ids,data.layoutVersion);
    if (bridge) native({action:'delete'});
    else {
      try { localStorage.removeItem(storageKey);status('保存した成績を削除しました。保存はオフです。'); }
      catch (_) { status('保存データを削除できませんでした。ブラウザのサイトデータ設定から削除してください。'); }
    }
    renderNav();
  }
  function renderNav() {
    el('lessons').replaceChildren();
    data.lessons.forEach((l,i)=>{
      const b=document.createElement('button');b.type='button';b.textContent=l.title;b.setAttribute('aria-current',String(i===lessonIndex));
      const score=progress.lessons[l.id];
      if(score){const s=document.createElement('span');s.className='badge';s.textContent=score.completed+'回完了 · 最高'+score.bestAccuracy+'%';b.append(s);}
      b.addEventListener('click',()=>start(i));el('lessons').append(b);
    });
  }
  function start(i) {
    lessonIndex=i;itemIndex=0;keyIndex=0;correct=0;total=0;lessonDone=false;composing=false;justComposed=false;compositionEnter='none';
    trial.reset();freeTrial.reset();el('free-typing').value='';
    el('score').textContent='';renderNav();render();
  }
  function render() {
    const l=data.lessons[lessonIndex],x=l.exercises[itemIndex];itemDone=false;keyIndex=0;trial.reset();
    el('lesson-title').textContent=l.title;el('tip').textContent=l.tip;el('stage').textContent=l.stage;
    el('position').textContent=(itemIndex+1)+' / '+l.exercises.length;
    el('target').textContent=x.text;el('typing').value='';el('typing').disabled=false;el('next').disabled=true;
    el('next').textContent='次へ';el('grade').disabled=false;
    el('mode-help').textContent=mode==='trial' ? 'ABC・英数で入力すると、この欄だけでかなが出ます。行キーは続くキーで変化します。Enterか「採点」で採点、Backspaceで修正できます。WKRを起動したままでも使えます。' : 'WKR v2とApple日本語入力のひらがなを使います。確定してからEnterで採点。反応しない場合は「採点」を押します。練習帳側では変換しません。Google日本語入力・azooKeyは専用テーブルを設定して使う方式です（実IME未確認）。';
    el('free-help').textContent=mode==='trial' ? 'ABC・英数で自由に体験。Hで「あ」、E→Kで「き」、W→E→Rで「わから」。Enterで区切ります。かな入力の体験で、漢字変換はしません。' : 'WKRで自由に入力できます。この欄は採点・保存しません。';
    el('feedback').textContent='練習欄を選んで始めましょう。';renderKeys();
  }
  function renderKeys() {
    const x=data.lessons[lessonIndex].exercises[itemIndex];el('keys').replaceChildren();
    x.keys.forEach((k,i)=>{const n=document.createElement('kbd');n.textContent=k.toUpperCase();el('keys').append(n);});
  }
  function finishItem() {
    itemDone=true;trial.reset();el('typing').value='';el('typing').disabled=true;el('grade').disabled=true;el('next').disabled=false;
    const l=data.lessons[lessonIndex];el('feedback').textContent='できました。次のことばへ進みましょう。';
    if(itemIndex===l.exercises.length-1){
      lessonDone=true;const accuracy=total?Math.round(correct/total*100):100;
      aggregate.complete(progress,l.id,accuracy);persist();renderNav();
      el('score').textContent='課題完了 · 正答率 '+accuracy+'%（'+'正しい回答 / 提出した回答'+'）';
      el('next').textContent=lessonIndex<data.lessons.length-1?'次の課題へ':'最初の課題へ';
    }
    el('next').focus();
  }
  el('typing').addEventListener('compositionstart',()=>{
    composing=true;justComposed=false;compositionEnter='none';el('grade').disabled=true;
  });
  el('typing').addEventListener('compositionupdate',()=>{
    if(compositionEnter==='released')compositionEnter='none';
  });
  el('typing').addEventListener('compositionend',()=>{
    composing=false;justComposed=compositionEnter!=='released';compositionEnter='none';
    el('grade').disabled=itemDone;
  });
  function grade() {
    if(composing||itemDone)return;
    const input=el('typing').value.normalize('NFC').trim();
    if(!input)return;total++;
    if(input===data.lessons[lessonIndex].exercises[itemIndex].text){correct++;finishItem();}
    else {trial.reset();el('typing').value='';el('feedback').textContent='もう一度、見本のひらがなで入力してみましょう。';}
  }
  function simulate(e, field, engine, graded) {
    if(e.metaKey||e.ctrlKey||e.altKey||e.key==='Tab')return;
    if(e.repeat){e.preventDefault();return;}
    if(e.key==='Backspace'){e.preventDefault();field.value=engine.backspace();return;}
    if(isEnter(e)){e.preventDefault();field.value=engine.flush();if(graded)grade();return;}
    if(e.key==='Escape'){e.preventDefault();engine.reset();field.value='';return;}
    const key=window.WKRTrial.token(e);
    if(key!==null){e.preventDefault();field.value=engine.feed(key);field.setSelectionRange(field.value.length,field.value.length);}
  }
  for(const [id,engine] of [['typing',trial],['free-typing',freeTrial]]) {
    const field=el(id);
    field.addEventListener('paste',e=>{if(mode==='trial')e.preventDefault();});
    field.addEventListener('drop',e=>{if(mode==='trial')e.preventDefault();});
    field.addEventListener('input',()=>{
      if(mode==='trial'){engine.reset();field.value='';el('feedback').textContent='QWERTY体験はABC・英数で入力してください。WKRで入力するときは「WKR・IMEで練習」を選んでください。';}
    });
  }
  el('free-typing').addEventListener('keydown',e=>{
    if(mode==='trial'&&!e.isComposing&&e.keyCode!==229)simulate(e,el('free-typing'),freeTrial,false);
  });
  el('free-clear').addEventListener('click',()=>{freeTrial.reset();el('free-typing').value='';});
  el('typing').addEventListener('keydown',e=>{
    if(itemDone)return;
    if(composing||e.isComposing||e.keyCode===229){
      // Retain only evidence for the current confirmation key, in memory.
      // Unknown 229 events never release the post-composition guard.
      compositionEnter=isEnter(e)&&!shortcut(e)&&!e.repeat?'down':'none';
      return;
    }
    if(e.key==='Tab'||shortcut(e))return;
    if(mode==='trial'){simulate(e,el('typing'),trial,true);return;}
    if(e.repeat)return;
    if(!isEnter(e)){
      if(e.key.length===1||e.key==='Backspace'||e.key==='Delete'){justComposed=false;compositionEnter='none';}
      return;
    }
    if(justComposed)return;
    e.preventDefault();grade();
  });
  // WebKit may deliver confirmation keyup before compositionend. Accept only
  // identified Enter release; an ambiguous sequence keeps the guard until an
  // explicit button action. No timer or event history is retained.
  el('typing').addEventListener('keyup',e=>{
    if(!isEnter(e)||shortcut(e)||e.repeat)return;
    if(composing){
      if(compositionEnter==='down')compositionEnter='released';
    } else {justComposed=false;compositionEnter='none';}
  });
  el('grade').addEventListener('click',()=>{
    if(composing||itemDone)return;
    justComposed=false;compositionEnter='none';
    if(mode==='trial')el('typing').value=trial.flush();
    grade();
  });
  el('next').addEventListener('click',()=>{if(!itemDone)return;if(lessonDone)start((lessonIndex+1)%data.lessons.length);else{itemIndex++;render();}el('typing').focus();});
  el('retry').addEventListener('click',()=>{start(lessonIndex);el('typing').focus();});
  document.querySelectorAll('input[name=mode]').forEach(n=>n.addEventListener('change',()=>{mode=n.value;start(lessonIndex);}));
  el('save').addEventListener('change',()=>{if(el('save').checked){save=true;persist();}else clearSaved();});
  el('delete').addEventListener('click',clearSaved);
  window.addEventListener('pagehide',()=>{trial.reset();freeTrial.reset();composing=false;justComposed=false;compositionEnter='none';el('grade').disabled=itemDone;el('typing').value='';el('free-typing').value='';});
  el('versions').textContent='練習 '+data.practiceVersion+' / 配列 '+data.layoutVersion;
  data.keyboard.forEach(row=>{const line=document.createElement('div');line.className='keyrow';row.forEach(k=>{const cap=document.createElement('div');cap.className='keycap';const b=document.createElement('b');b.textContent=k.key.toUpperCase();const s=document.createElement('span');s.textContent=k.label;cap.append(b,s);line.append(cap);});el('keyboard').append(line);});
  start(0);read();
})();
