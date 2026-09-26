/* Page-local kana simulation. Only bounded current text and a prefix are held. */
(function (root) {
  'use strict';
  function create(rules, limit = 160) {
    const exact = new Map(), prefixes = new Set();
    const id = keys => keys.join('\u001f');
    for (const rule of rules) {
      exact.set(id(rule.keys), rule.output);
      for (let i = 1; i < rule.keys.length; i++) prefixes.add(id(rule.keys.slice(0, i)));
    }
    let committed = '', pending = [];
    const trim = s => Array.from(s).slice(0, limit).join('');
    const provisional = () => exact.get(id(pending)) || '';
    const text = () => trim(committed + provisional());
    function flush() { committed = text(); pending = []; return committed; }
    function feed(key) {
      if (Array.from(committed).length >= limit) return text();
      let candidate = pending.concat(key), code = id(candidate);
      if (!exact.has(code) && !prefixes.has(code)) { flush(); candidate = [key]; code = id(candidate); }
      if (!exact.has(code) && !prefixes.has(code)) {
        // Non-layout printable characters have no IME-dependent punctuation conversion.
        if (key.length === 1) committed = trim(committed + key);
        return text();
      }
      pending = candidate;
      if (!prefixes.has(code)) flush();
      return text();
    }
    function backspace() {
      if (pending.length) pending = [];
      else committed = Array.from(committed).slice(0, -1).join('');
      return text();
    }
    return {feed, flush, backspace, text, reset() { committed = ''; pending = []; },
      pending: () => pending.length > 0};
  }
  function token(event) {
    if (event.metaKey || event.ctrlKey || event.altKey || event.isComposing || event.keyCode === 229) return null;
    if (/^Key[A-Z]$/.test(event.code)) return event.shiftKey ? event.key : event.code.slice(3).toLowerCase();
    const codes = {Semicolon: ';', Comma: ',', Period: '.', Slash: '/', BracketLeft: '[', BracketRight: ']',
      Minus: '-', IntlYen: 'JIS-Yen', IntlRo: 'JIS-_'};
    if (/^Digit[0-9]$/.test(event.code)) return (event.shiftKey ? 'Shift+' : '') + event.code.slice(5);
    if (codes[event.code]) return (event.shiftKey ? 'Shift+' : '') + codes[event.code];
    if (event.key.length === 1 && /^[\x20-\x7e]$/.test(event.key)) return event.key;
    return null;
  }
  const api = {create, token};
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.WKRTrial = api;
})(typeof window === 'undefined' ? globalThis : window);
