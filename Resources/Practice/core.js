/* Pure aggregate validation shared by browser UI and Node tests. */
(function (root) {
  'use strict';
  const MAX = 1000000;
  function clean(value, ids, layoutVersion) {
    const empty = {schemaVersion: 2, layoutVersion, lessons: {}};
    if (!value || value.schemaVersion !== 2 || value.layoutVersion !== layoutVersion ||
        !value.lessons || typeof value.lessons !== 'object' || Array.isArray(value.lessons)) return empty;
    for (const id of ids) {
      const v = value.lessons[id];
      if (!v || !Number.isInteger(v.completed) || v.completed < 1 || v.completed > MAX ||
          !Number.isInteger(v.bestAccuracy) || v.bestAccuracy < 0 || v.bestAccuracy > 100) continue;
      empty.lessons[id] = {completed: v.completed, bestAccuracy: v.bestAccuracy};
    }
    return empty;
  }
  function complete(progress, id, accuracy) {
    const old = progress.lessons[id] || {completed: 0, bestAccuracy: 0};
    progress.lessons[id] = {completed: Math.min(MAX, old.completed + 1),
      bestAccuracy: Math.max(old.bestAccuracy, Math.max(0, Math.min(100, Math.round(accuracy))))};
    return progress;
  }
  const api = {clean, complete};
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.WKRProgress = api;
})(typeof window === 'undefined' ? globalThis : window);
